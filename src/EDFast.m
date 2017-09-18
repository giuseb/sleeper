classdef EDFast < handle
   %EDFast: efficiently import EDF signals into matrices
   %
   % Create an EDFast object from an EDF file:
   % >> edf = EDFast('data.edf')
   %
   % type the variable name at the command line to see the object's
   % publicly visible properties:
   %
   % >> edf
   %
   % Set verbosity to get information in the Command Window while
   % processing (default is false to reduce clutter)
   % >> edf.Verbose = true
   %
   % By changing the processing block size, you may improve execution
   % speed. Optimal values depend on available PC memory, duration of
   % recordings, and number of channels. You need to experiment.
   % >> edf.RecordsPerBlock = 1000
   %
   % Retrieve the specified signal:
   % >> sig = edf.get_signal(2);
   %
   % Inspired by Dennis A. Dean's blockEdfLoadClass
   % http://www.mathworks.com/matlabcentral/fileexchange/45227-blockedfloadclass
   % https://github.com/DennisDean/BlockEdfLoadClass
   % Some of his code is still here.
   %
   % Here, the focus is to extract one signal at a time,
   % especially useful for very large data files.
   %
   % GB: 3 May 2016
      
   %----------------------------------------------------------- Properties
   properties (Access = public)
      Verbose = false
      RecordsPerBlock = 100
   end
   
   properties (SetAccess = private)
      Filename         % source EDF file path/name
      RecStart         % the recording start datetime
      RecEnd           % the recording end datetime
      NSignals         % the number of signals in the EDF
      SigLabels        % the labels for each of the signals
      SigHertz         % the sampling rate for each of the signals
      Header = struct  % the entire header
      SignalHeader = struct(...
         'signal_labels', {}, ...
         'tranducer_type', {}, ...
         'physical_dimension', {}, ...
         'physical_min', {}, ...
         'physical_max', {}, ...
         'digital_min', {}, ...
         'digital_max', {}, ...
         'prefiltering', {}, ...
         'samples_in_record', {}, ...
         'reserve_2', {});
   end
   
   properties (Access = private)
      ActiveSignal
      NumMemBlocks
      BlockSize
      BlockBounds
      SSize
      SigMask
      % SigMatObj
   end
   
   properties (Constant, Access = private)
      headSize = 256
      headVars = {
         'edf_ver';
         'patient_id';
         'local_rec_id';
         'recording_startdate';
         'recording_starttime';
         'num_header_bytes';
         'reserve_1';
         'num_data_records';
         'data_record_duration';
         'num_signals'
         }
      headVarsConF = {
         @strtrim; @strtrim; @strtrim; @strtrim; @strtrim;
         @str2num; @strtrim; @str2num; @str2num; @str2num
         }
      headVarSize = [8 80 80 8 8 8 44 8 8 4]
      sigHeadVar = {
         'signal_labels';
         'tranducer_type';
         'physical_dimension';
         'physical_min';
         'physical_max';
         'digital_min';
         'digital_max';
         'prefiltering';
         'samples_in_record';
         'reserve_2'
         };
      sigHeadVarConvF = {
         @strtrim; @strtrim; @strtrim; @str2num; @str2num;
         @str2num; @str2num; @strtrim; @str2num; @strtrim
         }
      sigHeadVarSize = [16 80 8 8 8 8 8 80 8 32]
      uVconv = 1000000; % turning EDF's Volts into ?V
   end
   
   %------------------------------------------------------- Public Methods
   methods
      %------------------------------------------------------- Constructor
      function obj = EDFast(filename)
         obj.Filename = filename;
         % Open the input file
         [fid, msg] = fopen(filename);
         if fid < 0, error(msg); end
         % Load header data
         A = fread(fid, obj.headSize);
         % Place header data into its structure
         hvl = [0, cumsum(obj.headVarSize)];
         for h = 1:length(obj.headVars)
            conF = obj.headVarsConF{h};
            value = conF(char((A(hvl(h)+1:hvl(h+1)))'));
            obj.Header.(obj.headVars{h}) = value;
         end
         % Load Signal Header data
         ss = obj.Header.num_header_bytes - sum(obj.headVarSize);
         A = fread(fid, ss);
         % Place signal header data into its structure
         ns = obj.Header.num_signals;
         svl = [0, cumsum(obj.sigHeadVarSize*ns)];
         for v = 1:length(obj.sigHeadVar)
            varBlock = A(svl(v)+1:svl(v+1))';
            varSize = obj.sigHeadVarSize(v);
            conF = obj.sigHeadVarConvF{v};
            for s = 1:ns
               range = varSize*(s-1)+1:varSize*s;
               value = conF(char(varBlock(range)));
               obj.SignalHeader(s).(obj.sigHeadVar{v}) = value;
            end
         end
         fclose(fid);
         
         % set up rec start and end datetimes
         ds = [obj.Header.recording_startdate obj.Header.recording_starttime];
         off = obj.Header.num_data_records * obj.Header.data_record_duration;
         obj.RecStart = datetime(ds, 'Inputformat', 'dd.MM.yyHH.mm.ss');
         obj.RecEnd   = obj.RecStart + seconds(off);
         % set up signal labels and Hz
         obj.SigLabels = {obj.SignalHeader.signal_labels};
         obj.NSignals = length(obj.SigLabels);
         obj.SigHertz = cell2mat({ obj.SignalHeader.samples_in_record } )/ obj.Header.data_record_duration;
      end
      
      % Return an entire signal as a vector
      function rv = get_signal(obj, sig)
         % set up properties
         obj.setup_params(sig);
         % Open the input file
         [fid, msg] = fopen(obj.Filename);
         if fid < 0, error(msg); end
         % move file pointer past the header
         fseek(fid, obj.Header.num_header_bytes, -1);
         % allocate memory for the entire digital signal
         if obj.Verbose, fprintf('Allocating %d bytes\n', obj.SSize*2); end
         A = zeros(obj.SSize, 1, 'int16');
         if obj.Verbose, disp('Done.'); end
         % process data in chunks
         for block = 1:obj.NumMemBlocks
            a = fread(fid, obj.BlockSize, 'int16');
            t = obj.SigMask;
            t(length(a)+1:end) = [];
            A(obj.BlockRange(block)) = a(t);
            if obj.Verbose
               fprintf('Read block #%d of %d\n', block, obj.NumMemBlocks);
            end
         end
         fclose(fid);
         % convert to analog; this normalization adapted from edfread by
         % Brett Shoelson
         th = obj.SignalHeader(obj.ActiveSignal);
         scalefac = (th.physical_max - th.physical_min)/ ...
            (th.digital_max  - th.digital_min);
         dc = th.physical_max - scalefac * th.digital_max;
         rv = (double(A) * scalefac + dc) * obj.uVconv;
      end
   end
   %---------------------------------------------------- Private functions
   methods (Access=private)
      function setup_params(obj, signal)
         % Save argument to current Signal
         obj.ActiveSignal = signal;
         % data record size broken down by signal
         drsizes = [obj.SignalHeader.samples_in_record];
         % to extract the active signal from a loaded record
         cum = [0, cumsum(drsizes)];
         a = false(sum(drsizes), 1);
         a(cum(obj.ActiveSignal)+1 : cum(obj.ActiveSignal+1)) = true;
         obj.SigMask = repmat(a, obj.RecordsPerBlock, 1);
         % the number of iterations to read signals from the entire data file
         obj.NumMemBlocks = ceil(obj.Header.num_data_records / obj.RecordsPerBlock);
         % number of samples read on each iteration while loading signals
         obj.BlockSize = obj.RecordsPerBlock * sum(drsizes);
         % number of samples per record, for the active signal
         srsize = obj.SignalHeader(obj.ActiveSignal).samples_in_record;
         % the total number of samples for the active signal
         obj.SSize = srsize * obj.Header.num_data_records;
         % boundaries to get the block range
         obj.BlockBounds = [0:srsize*obj.RecordsPerBlock:obj.SSize, obj.SSize];
      end
      
      % range for the current block
      function rv = BlockRange(obj, block)
         rv = (obj.BlockBounds(block)+1 : obj.BlockBounds(block+1))';
      end
   end
end

% TO TRASH? MAYBE
% If you don't need to use the signal right away, you can instead
% directly save to a MAT file:
% >> mat_file_name = 'exp01.mat';
% >> signal_label = 'eeg2';
% >> edf.save_signal(mat_file_name, signal_label, 2)
%
% To save multiple signals to the same MAT file, loop over the append
% function:
% >> sig_labels = {'EEG1', 'EMG1'};
% >> for n = 1:length(sig_labels)
% >>    edf.append_signal(mat_file_name, sig_labels{n}, n);
% >> end
%
%       function SigMatSetup(obj, fn)
%          obj.SigMatObj = SigMat(fn, obj.RecStart, obj.SigHertz);
%          obj.SigMatPath = obj.SigMatObj.Properties.Source;
%       end
%
%       function save_signal(obj, signal, label)
%          if nargin < 3
%             label = regexprep(obj.SigLabels{signal}, '\W', '_');
%          end
%          obj.SigMatObj.write(label, obj.get_signal(signal));
%       end
%
%       function sidx = SigNos(obj)
%          sidx = 1:length(obj.SigLabels);
%       end
%       function sps = SigHertz(obj)
%          sps = cell2mat({ obj.SignalHeader.samples_in_record } )/ obj.Header.data_record_duration;
%       end

