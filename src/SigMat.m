classdef SigMat < handle
   % SigMat: managing our own .MAT files containing eeg/emg signals
   %
   % The aim of the SigMat class is to provide a simple interface to
   % consistently store EEG, EMG, and other physiological signals as .MAT
   % files. Internally, SigMat makes use of Matlab's built-in MATFILE
   % class, which allows to read from .mat files only parts of saved
   % arrays, thereby making very long recording sessions manageable.
   %
   % While SigMat offers some convenience methods, nothing prevents users
   % from directly accessing data stored in SigMat-generated files, as they
   % are standard .MAT files containing a simple list of matrices.
   %
   % SigMat is meant to remain much simpler than other general-purpose data
   % file formats (e.g. EDF) and the following limitations are by design.
   %
   % A SigMat contains a single time stamp indicating the start of the
   % recording, i.e. all signals stored in a SigMat should come from the
   % same recording session.
   %
   % A SigMat contains a single label indicating the name of the subject,
   % i.e. all signals should come from the same subject.
   %
   % On the other hand, each signal will have its own label and sampling
   % frequency.
   %
   % SigMat constructor
   %     SigMat(FILENAME, START, SUBJECT) creates a new SigMat object and
   %     writes in the .MAT file specified by FILENAME the time stamp
   %     indicating the START of the recording and the name of the SUBJECT.
   %     If FILENAME already exists, an error is raised.
   %
   %     SigMat(FILENAME) instantiates a SigMat object based on the existing
   %     .MAT file specified by FILENAME. If the file cannot be found, an
   %     error is raised.
   %
   % Publicly readable properties
   %     Type the SigMat variable name at the command line for a list, or
   %     visit >> doc SigMat
   %
   % Readin'n'riting...
   %     >> help SigMat.read
   %     >> help SigMat.write
   %
   % THIS IS AN ALPHA VERSION, THE API MAY CHANGE
   %
   % Last modified: 30 Apr 16
   
   properties (SetAccess = private)
      SigMatPath % The path of the .MAT file containing the data
      Subject    % Subject name (please use the unique ID!)
      RecStart   % The beginning of the recording (as a datetime)
      NSignals   % The number of signals already written in the SigMat
      SigLabels  % The list of signal labels (as a cell array of strings)
      Hertz      % The list of signal acquisition rates (in Hertz)
   end
   
   properties(Access=private)
      MatFileObj
   end
   
   methods
      % -----------------------------------------------------> Constructor
      function obj = SigMat(fn, start, subject)
         % The SigMat Constructor
         %
         %     SigMat(FILENAME, START, SUBJECT) creates a new SigMat object
         %     and writes in the .MAT file specified by FILENAME the time
         %     stamp indicating the START of the recording (as a datetime
         %     object or a valid datetime string) and the name of the
         %     SUBJECT (as a valid variable name). If FILENAME already
         %     exists, an error is raised.
         %
         %     SigMat(FILENAME) instantiates a SigMat object based on the
         %     existing .MAT file specified by FILENAME. If the file cannot
         %     be found, an error is raised.
         
         % initialize the matfile in a temporary var
         switch nargin
            case 3 % creating a new SigMat
               if exist(fn, 'file')
                  error('A .MAT file by that name already exists')
               else
                  if ~isvaliddatetime(start)
                     error('Argument START should be a valid datetime object or string')
                  end
                  if ~ishstring(subject)
                     error('Argument SUBJECT should be a string')
                  end                     
                  mf = matfile(fn, 'writable', true);
                  mf.start   = datetime(start);
                  mf.subject = subject;
                  mf.hertz   = [];
                  mf.labels  = {};
                  disp('Creating a new SigMat')
               end               
            case 1 % opening an existing SigMat
               mf = matfile(fn, 'writable', true);
               disp('Opening an existing SigMat');
            otherwise
               error('Wrong number of arguments. Should be either 1 or 3')
         end
         % store away the matfile, for subsequent use
         obj.MatFileObj = mf;
         obj.SigMatPath = mf.Properties.Source;
         obj.Subject    = mf.subject;
         obj.RecStart   = mf.start;
         obj.NSignals   = length(mf.labels);
         obj.SigLabels  = mf.labels;
         obj.Hertz      = mf.hertz;
      end
      
      function write(obj, label, hertz, signal)
         % WRITE   storing a signal
         %
         %    sm = SigMat(...)
         %    sm.write(LABEL, HZ, SIGNAL)
         %
         %    stores in the SigMat the SIGNAL (a linear numerical vector)
         %    named LABEL (a string), sampled at HZ Hertz.
         %
         %    If a signal by this LABEL already exists in the SigMat, it
         %    will be overwritten.
         if ~isvarname(label)
            error('Signal LABEL should be a string that is also a valid variable name')
         end
         if find(strcmp({'start' 'subject' 'hertz' 'labels'}, label), 1)
            error(['Invalid label: ' label ' is a reserved SigMat variable']);
         end
         if ~isnumscalar(hertz)
            error('Invalid HERTZ argument; it should be a numerical scalar')
         end
         if ~isnumvector(signal)
            error('SIGNAL should be a numerical array')
         end

         % overwrite if label exists
         idx = find(strcmp(obj.SigLabels, label), 1);
         if isempty(idx)
            % this is a new signal!
            obj.NSignals = obj.NSignals+1;
            obj.SigLabels{obj.NSignals} = label;
            obj.MatFileObj.labels = obj.SigLabels;
         end
         obj.Hertz(obj.NSignals) = hertz;
         obj.MatFileObj.hertz = obj.Hertz;
         obj.MatFileObj.(label) = signal;
      end
      
      function rv = length(obj, signal)
         
         % TODO: refactor this with identical code in READ
         if nargin < 2
            error('Too few arguments; SIGNAL is mandatory')
         else
            if isintscalar(signal)
               if signal > obj.NSignals || signal < 1
                  error('Invalid signal number')
               else                  
                  signal = obj.SigLabels{signal};
               end
            elseif ishstring(signal)
               if ~find(strcmp(obj.SigLabels, signal), 1)
                  error('Signal label not found')
               end
            else
               error('Invalid argument type; SIGNAL should be an integer or a string')
            end
         end
         rv = max(size(obj.MatFileObj, signal));
      end
      
      function rv = read(obj, signal, start, finish)
         % READ reading a signal
         %
         %    sm.SigMat(...)
         %
         %    sm.read(N)
         %    sm.read(LABEL)
         %
         %    loads from the disk file the N-th signal (as an integer) or
         %    the signal named LABEL (a string).
         
         if nargin < 2
            error('Too few arguments; SIGNAL is mandatory')
         else
            if isintscalar(signal)
               if signal > obj.NSignals || signal < 1
                  error('Invalid signal number')
               else                  
                  signal = obj.SigLabels{signal};
               end
            elseif ishstring(signal)
               if ~find(strcmp(obj.SigLabels, signal), 1)
                  error('Signal label not found')
               end
            else
               error('Invalid argument type; SIGNAL should be an integer or a string')
            end
            
            if nargin == 2               
               rv = obj.MatFileObj.(signal);
            elseif nargin==4
               dtstart = datetime(start);
               dtfin   = datetime(finish);
               if dtstart > dtfin
                  error('start occurs after end')
               end
               istart = seconds(dtstart-obj.RecStart) * obj.Hertz + 1;
               iend   = seconds(dtfin  -obj.RecStart) * obj.Hertz;
               rv = obj.MatFileObj.(signal)(istart:iend,1);
            else
               error('Invalid number of arguments')
            end
         end
      end
   end
end