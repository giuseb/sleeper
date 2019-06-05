classdef EEGenie < handle
   %EEGenie: simple calculations on hypnograms and EEG events
   %
   %   Analyzing vigilance states and “events”, scored/detected on the
   %   basis of video-EEG-EMG recordings.
   %
   %   Objects of the EEGenie class operate on one or more of the following:
   %   * an EEG signal: an array of floats representing the potentials at
   %   the original sampling rate
   %   * a hypnogram: an array of integers representing sequences of epochs
   %   (usually a few seconds each) labeled depending on the vigilance
   %   state scored during that period
   %   * a set of markers: events occurring during the recording, described
   %   with a label (tag), start, and end times.
   %
   %   To create an empty EEGenie object with default parameters:
   %
   %   >> EG = EEGenie
   %
   %   Data can be added to the object like so:
   %
   %   >> EG.EEG = eeg;
   %
   %   Type “doc EEGenie” at the command line or click below for more help

   properties (SetObservable)
      EEG
      Hypno     % hypnogram
      States    % scoring states
      Epoch     % scoring epoch in seconds
      Block     % number of epochs in an analysis block 
      Markers   % the markers structure
      SRate     % the EEG signal's sampling rate
      TOI       % tag of interest
      Ksize     % kernel size for spectral analysis of events (in seconds)
      Kover     % kernel overlap fraction   (default: 0.5)
      HzMin     % minimum plotted frequency (default: 0)
      HzMax     % maximum plotted frequency (default: 30)
      wType     % the window type (default: 'hanning')
      Delta     % the Delta band (default: [ 0.5   4.0])
      Theta     % the Theta band (default: [ 4.5,  7.5])
      Alpha     % the Alpha band (default: [ 8.0, 15.0])
      Beta      % the Beta  band (default: [15.5, 30.0])
      Verbose
      Bin       % time bin in hours: different from Block, which may
                % eventually be abandoned, if we drop epochs altogether
   end
   
   properties (SetAccess = private)
      hyplen % number of epochs in the hypnogram
      Tags
   end
   
   properties (Access = private)
      changes % all the transitions computed as diff
      binsec  % size of bin in seconds
      nbins   % the number of time bins in the recording
      nblocks % the number of blocks in the hypnogram
      nstates % the number of states in the hypnogram
      aidx    % the indices of events tagged with the TOI
      spk     % the number of samples for the given kernel duration (Ksize)
      ntags
      NoHyp
      NoMrk
      NoEEG
   end
   
   methods %-------------------------------------------------- CONSTRUCTOR
      function obj = EEGenie(varargin)
         %   Input data and other parameters can be provided at construction time
         %   as name/value “argument pairs”, e.g.
         %
         %   >> hypnogram = [1 1 2 3 2 3 2 2 3 2 2 1 2]
         %   >> ee = EEGenie('hyp', hypnogram)
         %
         %   or can be added to a previously created object, like so:
         %
         %   >> ee = EEGenie
         %   >> ee.Hypno = hypnogram
         
         % This constructor works on the assumption that no magic numbers
         % are stored in the code, all default parameters are written in
         % the file eegenie.yml, in the src directory. To change any values
         % upon construction, a custom YAML file can be passed (via the
         % PFile argument), but individual name-value pairs have
         % precedence, when given.
         
         % the list of all possible arguments, with a default "null" value
         % and a validation function handle
         args = {
            'PFile',      '', @ishstring; % do not move PFile from args{1}
            'EEG',        [], @isnumvector;
            'Hypno',      [], @isnumvector;
            'Markers',    [], @isstruct;
            'States',     {}, @iscellstr;
            'Epoch',      -1, @isnumscalar;
            'Block',      -1, @isnumscalar;
            'Bin',         0, @isnumscalar;
            'TOI',        '', @ishstring;
            'SRate',      -1, @isnumscalar;
            'Ksize',      -1, @isnumscalar;
            'Kover',      -1, @isnumscalar;
            'HzMin',      -1, @isnumscalar;
            'HzMax',      -1, @isnumscalar;
            'Delta',      [], @isnumvector;
            'Theta',      [], @isnumvector;
            'Alpha',      [], @isnumvector;
            'Beta',       [], @isnumvector;
            'wType',      '', @ishstring;
            'Verbose', false, @islogical;
            };

         % input argument parsing
         p = inputParser;
         for i=1:length(args)
            p.addParameter(args{i,1}, args{i,2}, args{i,3})
         end
         p.parse(varargin{:})
         
         % grab default parameters
         y = readparams('eegenie.yml', 'eegenie');
         % if an optional params YAML file was given...
         if ~isempty(p.Results.PFile)
            % read the corresponding YAML file
            ty = readparams([p.Results.PFile '.yml'], 'eegenie');
            % merge those parameters with the defaults
            for f = fieldnames(ty)'
               y.(f) = ty.(f);
            end
         end
         
         % transfer all parameters to the object
         % (excluding PFile!)
         for i=2:length(args)
            a = args{i,1}; % the field
            % has this parameter been passed as an input argument?
            passed = ~isequal(p.Results.(a), args{i,2});
            % if so, then override the default
            obj.(a)=cas(passed, p.Results.(a), getfieldi(y,a));
         end
         
         % special treatment for this one
         obj.Hypno = obj.Hypno(:); % enforce vertical!
         
         % make object react if a parameter is set later on
         obj.addlistener(args(2:end,1), 'PostSet', @obj.HandleProps);
         obj.update_parameters
      end
   end
   
   methods %-------------------------------------------------- EEG
      function notcheby(obj, fn)
         % EG.NOTCHEBY  applies a notch a and bandpass chebyshev2 filter to
         % the EEG vector
         if isempty(obj.EEG)
            disp('No EEG to filter')
            return
         end
         
         if nargin==1
            obj.EEG = notcheby(obj.EEG);
         else
            obj.EEG = notcheby(obj.EEG, fn);
         end
      end
      
      function rv = spectra(obj)
         % EG.SPECTRA computes power spectra over each of the events
         % tagged with the TOI in the markers array
         
         % retrieve start and end stamps for the currently tagged markers
         stimes = obj.ssv;
         etimes = obj.esv;
         
         % number of TOI-tagged markers
         nm = length(stimes);
         
         % spectra will be placed here
         rv = [];
         
         for i = 1:nm
            if obj.Verbose
               fprintf('Marker %d of %d\n', i, nm)
            end
            % num of samples in fragment
            dt = etimes(i)-stimes(i)+1;
            % num of samples after the last whole kernel duration
            tte = rem(dt, obj.SRate);
            % round up to the next kernel if necessary
            if tte > 0
               etimes(i) = etimes(i) + obj.spk - tte;
            end
            % the EEG fragment to analyze
            eeg = obj.EEG(stimes(i):etimes(i));
            % the epoch needed by EEpower should be equal to the length of
            % the EEG fragment, so that only one spectrum is computed
            ep = EEpower(eeg, 'SRate', obj.SRate, ...
                              'Ksize', obj.Ksize, ...
                              'Epoch', 0, ...
                              'Kover', obj.Kover);
            ee = ep.spectra;
            rv = [rv ee]; %#ok<AGROW>
         end
      end
   end
   
   methods %-------------------------------------------------- HYPNOGRAM
      
      %------ AGGREGATE METHODS, returning one element per state
      
      function rv = epochs(obj)
         % EG.EPOCHS, where EG is an EEGenie object, returns the number of
         % epochs for each state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i, :) = sum(obj.blocked==i);
         end
      end
      
      function rv = minutes(obj)
         % EG.MINUTES, where EG is an EEGenie object, returns the total
         % duration in minutes for each state scored in the hypnogram
         rv = obj.seconds / 60;
      end
      
      function rv = seconds(obj)
         % EG.SECONDS, where EG is an EEGenie object, returns the total
         % duration in seconds for each state scored in the hypnogram
         rv = obj.epochs * obj.Epoch;
      end
      
      function rv = fractions(obj)
         % EG.FRACTIONS, where EG is an EEGenie object, returns the
         % fraction of time spent in each state scored in the hypnogram
         s = sum(obj.epochs);
         r = repmat(s, obj.nstates, 1);
         rv = obj.epochs ./ r;
      end
      
      function rv = episodes(obj)
         % EG.EPISODES, where EG is an EEGenie object, returns the number
         % of scored episodes for each state in the hypnogram
         t = diff([0; obj.Hypno]);
         r = reshape(t, obj.Block, obj.nblocks);
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i,:) = sum(obj.blocked==i & r);
         end
      end
      
      function rv = durations(obj)
         % EG.DURATIONS, where EG is an EEGenie object, collects state
         % episode durations. It returns a cell matrix, one row for each
         % state, one column for each block of epochs. Each cell contains
         % an array of episode durations in seconds.
         
         % set up the cell array to be returned
         rv = cell(obj.nstates, obj.nblocks);
         
         hy = obj.Hypno;
         % use the first epoch as a starting point
         c_stg = hy(1); % the current stage
         c_len = 1;     % the current episode duration (in epochs)
         c_blo = 1;     % the current block
         
         % find all state changes
         df = [0; diff(hy)];
         
         % brute force approach, not very idiomatic, but it seems
         % complicated to solve otherwise; looping over each epoch,
         % starting from the second
         for i=2:obj.hyplen
            if df(i)
               % we have found a state change, so the duration of the
               % previous state must be saved
               rv{c_stg, c_blo} = [rv{c_stg, c_blo}; c_len * obj.Epoch];
               % save the current state and reset vars
               c_stg = hy(i);
               c_len = 1;
               c_blo = floor((i-1)/obj.Block)+1;
            else
               c_len = c_len + 1;
            end
         end
         rv{c_stg, c_blo} = [rv{c_stg, c_blo}; c_len * obj.Epoch];
      end
      
      function rv = mean_durations(obj)
         % EG.MEAN_DURATIONS, where EG is an EEGenie object, returns the
         % mean episode durations (in seconds) for each state scored in the
         % hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         du = obj.durations;
         for i = 1:obj.nstates
            for j = 1:obj.nblocks
               rv(i, j) = mean(du{i,j});
            end
         end
      end
      
      function rv = std_durations(obj)
         % EG.STD_DURATIONS, where EG is an EEGenie object, returns the
         % standard deviation of episode durations (in seconds) for each
         % state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         du = obj.durations;
         for i = 1:obj.nstates
            for j = 1:obj.nblocks
               rv(i,j) = std(du{i,j});
            end
         end
      end
      
      function rv = transitions(obj)
         % EG.TRANSITIONS, where EG is an EEGenie object, returns a table
         % containing counts of all transition types
         
         % find all possible state pairs
         b = combnk(1:obj.nstates, 2);
         % also use the flipped pairs (e.g. both 1-4 AND 4-1)
         c = [b; fliplr(b)]';
         % encode all pairs
         d = diff(2.^(c-1));
         % the number of possible combinations
         n = length(d);
         % allocating vectors
         s1 = cell(n, 1);
         s2 = cell(n, 1);
         ct = zeros(n, obj.nblocks);
         % for each state pair...
         for i = 1:n
            s1(i) = obj.States(c(1,i));
            s2(i) = obj.States(c(2,i));
            ct(i,:) = sum(obj.changes==d(i));
         end
         rv = table(s1, s2, ct, 'variablenames', {'Before' 'After' 'Count'});
      end
      
      function rv = blocked(obj)
         rv = reshape(obj.Hypno, obj.Block, obj.nblocks);
      end
   end
   
   methods %-------------------------------------------------- MARKERS
      
      function rv = total(obj)
         % TOTAL: returns the total number of events for the current TOI
         rv = histcounts(obj.start_times, 'BinWidth', obj.binsec);
      end
      
      function rv = events_per_epoch(obj)
         % the list of start positions
         sss = obj.ssv;
         % the number of samples per epoch
         spe = obj.Epoch * obj.SRate;
         % the binning ceiling
         cei = ceil(sss(end)/spe)*spe;
         % the bins, including the right edge
         bin = 0:spe:cei;
         % event count per epoch
         rv = histcounts(sss, bin);
      end
      
      function rv = start_stamps(obj)
         rv = obj.ssv;
      end
      
      function rv = end_stamps(obj)
         rv = obj.esv;
      end
      
      function rv = start_times(obj)
         rv = obj.ssv / obj.SRate;
      end
      
      function rv = end_times(obj)
         rv = obj.esv / obj.SRate;
      end
      
      function rv = event_durations(obj)
         dif = obj.esv - obj.ssv;
         rv = dif / obj.SRate;
      end
 
      function rv = event_duration_mean(obj)
         rv = mean(obj.event_durations);
      end
 
      function rv = event_duration_std(obj)
         rv = std(obj.event_durations);
      end
 
      function replacetag(obj, before, after)
         [obj.Markers(obj.tagged(before)).tag] = deal(after);
         obj.settags;
      end
      
      function set_rms(obj)
         ss = obj.ssv(idx);
         es = obj.esv(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.Markers(id(i)).rms = rms(frag);
         end
      end
      
      function set_freq(obj, eeg, tag)
         if nargin>1, idx=obj.tagged(tag); else, idx=obj.all; end
         
         ss = obj.ssv(idx);
         es = obj.esv(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.Markers(id(i)).rms = rms(frag);
         end
      end
   end
   
   methods (Static)
      % triggers the update_parameters function whenever any of the
      % observable properties are modified by the user
      function HandleProps(~, event)
         event.AffectedObject.update_parameters
      end
   end
   
   methods (Access = private)
      % start stamp vector
      function rv = ssv(obj)
         % the special notation to extract field values from a structure
         rv = [obj.Markers(obj.aidx).start_pos];
      end
      
      % end stamp vector
      function rv = esv(obj)
         % the special notation to extract field values from a structure
         rv = [obj.Markers(obj.aidx).finish_pos];
      end
      
      % resetting tag info after changes
      function obj = settags(obj)
         obj.Tags  = unique({obj.Markers.tag});
         obj.ntags = length(obj.Tags);
      end
      
      % finding events tagged with tag
      function rv = tagged(obj, tag)
         rv = ismember({obj.Markers.tag}, tag);
      end
      
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      %%%%%%%%%%%%%%%%%%% PARAMETER UPDATING %%%%%%%%%%%%%%%%%%%%%
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      function update_parameters(obj)
         obj.nstates = length(obj.States);
         obj.spk     = obj.Ksize * obj.SRate;
         
         obj.NoEEG = isempty(obj.EEG);
         
         % checking Markers
         m = obj.Markers;
         if isa(m, 'char')
            load(m, 'markers')
            obj.Markers = markers;
         end
         
         if isempty(obj.Markers)
            obj.NoMrk = true;
         else
            obj.NoMrk = false;            
            obj.settags;

            % checking tag of interest
            if obj.TOI == false
               obj.aidx = true(1, length(obj.Markers));
            else
               obj.aidx = obj.tagged(obj.TOI);
            end
            
            % Set binsize in seconds
            if obj.Bin
               % Bin is given in hours, so multiply
               obj.binsec = obj.Bin * 3600;
            else
               % Bin is zero, use the last marker time stamp as binsize
               obj.binsec = max(obj.start_times);
            end
         end

         % checking hypnogram
         if isempty(obj.Hypno)
            obj.NoHyp = true;
         else
            obj.NoHyp = false;

            nani = isnan(obj.Hypno);
            if any(nani)
               error('NaNs in hypnogram at positions: %d', find(nani))
            end

            hl = length(obj.Hypno);
            % trim the hypnogram if necessary, based on block size
            if obj.Block
               % blocking has been specified, determine the number of blocks
               obj.nblocks = floor(hl / obj.Block);
               % getting the trimmed hypnogram size...
               obj.hyplen  = obj.Block * obj.nblocks;
               % and trim if necessary
               if obj.hyplen < length(obj.Hypno)
                  obj.Hypno(obj.hyplen:end) = [];
               end
            else
               % whole hypnogram as a single block
               obj.nblocks = 1;
               obj.Block = hl;
            end
            c = [diff(2.^(obj.Hypno-1)); 0];
            obj.changes = reshape(c, obj.Block, obj.nblocks);
         end
      end % OF UPDATE_PARAMETERS
   end
end

% function rv = mark_count(obj, tag)
%    % samples per epoch
%    spe = obj.hz * obj.epoch;
%    % find all markers tagged with tag
%    x = ismember({obj.Markers.tag}, tag);
%    beg = [obj.Markers.start_pos];
%    fin = [obj.Markers.finish_pos];
%    em = floor(beg / spe) + 1;
%    rv = 0;
% end

% function rv = totals(obj)
%    % TOTALS: returns the total number of events, one value per
%    % existing tag (sorted alphabetically)
%    for i=1:obj.ntags
%       rv(i) = obj.total(obj.Tags{i}); %#ok<AGROW>
%    end
% end

