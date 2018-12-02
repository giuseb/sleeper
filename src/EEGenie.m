classdef EEGenie < handle
   %EEGenie: simple calculations on hypnograms and EEG events
   %
   %   The EEGenie class helps to analyze vigilance states and “events”,
   %   scored/detected on the basis of video-EEG-EMG recordings.
   %
   %   Typically, one would feed EEGenie with the output of the program
   %   “sleeper”, which generates: 1) hypnograms, i.e. arbitrarily long
   %   sequences of epochs (usually a few seconds each) labeled depending
   %   on the vigilance state scored during that period; 2) “markers”, i.e.
   %   events described with a label (tag), start, and end times.
   %
   % WIP
   %
   %   The HYPNOANAL constructor takes one such vector as a mandatory
   %   argument and returns a HYPNOANAL object:
   %
   %   ha = HYPNOANAL(hyp)
   %
   %   The following name/value pair parameters may be added to the
   %   constructor call:
   %
   %   ha = HYPNOANAL(hyp, 'Epoch', s) specifies the epoch duration in
   %   seconds (default is 10).
   %
   %   ha = HYPNOANAL(hyp, 'States', {'REM', 'NREM', 'Wake'}) specifies the
   %   states (those shown here are the defaults); every "1" in the
   %   hystogram vector is interpreted as 'REM', every "2" is 'NREM', and
   %   so on.
   %
   %   You can verify these values by simply typing the object variable
   %   name at the command line:
   %
   %   >> ha
   %
   %     HypnoAnal with properties:
   %
   %       hypno: [450×1 double]
   %      states: {'REM'  'NREM'  'Wake'}
   %       epoch: 10
   %
   %   The HYPNOANAL object responds to the following aggregate methods,
   %   which return an an array with as many elements as there are states
   %   (in the order specified at object creation):
   %
   %   - ha.epochs
   %   - ha.minutes
   %   - ha.seconds
   %   - ha.episodes
   %   - ha.durations
   %   - ha.mean_durations
   %   - ha.std_durations
   %   - ha.fractions
   %
   %   In addition, ha.transitions returns a table with the number of all
   %   possible transitions
   %

   properties (SetObservable)
      EEG
      Hypno
      States
      Epoch
      Block
      Markers   % the markers structure
      SRate     % the EEG signal's sampling rate
      TOI       % tag of interest
   end
   
   properties (SetAccess = private)
      hyplen % number of epochs in the hypnogram
      Tags
   end
   
   properties (Access = private)
      changes % all the transitions computed as diff
      nblocks % the number of blocks in the hypnogram
      nstates % the number of states in the hypnogram
      aidx    % the indices of events tagged with the TOI
      ntags
      NoHyp
      NoMrk
   end
   
   methods %-------------------------------------------------- CONSTRUCTOR
      function obj = EEGenie(varargin)
         % parameter parsing
         p = inputParser;
         p.addParameter('EEG',    [], @isnumvector)
         p.addParameter('Epoch',  10, @isnumscalar)
         p.addParameter('SRate', 400, @isnumscalar)
         p.addParameter('Hypno',  [], @isnumvector)
         p.addParameter('States', {'REM', 'NREM', 'Wake'}, @iscellstr)
         p.addParameter('Block',   0, @isnumscalar)
         p.addParameter('Markers', [])
         p.addParameter('TOI',    'SWD', @ischar)
         p.parse(varargin{:})
         
         % assigning parameters to properties
         obj.EEG     = p.Results.EEG;
         obj.Block   = p.Results.Block;
         obj.Epoch   = p.Results.Epoch;
         obj.SRate   = p.Results.SRate;
         obj.States  = p.Results.States;
         obj.TOI     = p.Results.TOI;
         obj.Markers = p.Results.Markers;
         obj.Hypno   = p.Results.Hypno(:); % enforce vertical!
         
         % setting up observables
         lprops = { 'Epoch' 'EEG' 'SRate' 'Markers' 'States' 'Hypno' 'Block' 'TOI'};
         obj.addlistener(lprops, 'PostSet', @obj.HandleProps);
         
         % update all internals
         obj.update_parameters
      end
   end
   
   methods %-------------------------------------------------- HYPNOGRAM
      
      %------ AGGREGATE METHODS, returning one element per state
      
      function rv = epochs(obj)
         % HA.EPOCHS, where HA is an EEGenie object, returns the number of
         % epochs for each state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i, :) = sum(obj.blocked==i);
         end
      end
      
      function rv = minutes(obj)
         % HA.MINUTES, where HA is an EEGenie object, returns the total
         % duration in minutes for each state scored in the hypnogram
         rv = obj.seconds / 60;
      end
      
      function rv = seconds(obj)
         % HA.SECONDS, where HA is an EEGenie object, returns the total
         % duration in seconds for each state scored in the hypnogram
         rv = obj.epochs * obj.Epoch;
      end
      
      function rv = fractions(obj)
         % HA.FRACTIONS, where HA is an EEGenie object, returns the
         % fraction of time spent in each state scored in the hypnogram
         s = sum(obj.epochs);
         r = repmat(s, obj.nstates, 1);
         rv = obj.epochs ./ r;
      end
      
      function rv = episodes(obj)
         % HA.EPISODES, where HA is an EEGenie object, returns the number
         % of scored episodes for each state in the hypnogram
         t = diff([0; obj.Hypno]);
         r = reshape(t, obj.Block, obj.nblocks);
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i,:) = sum(obj.blocked==i & r);
         end
      end
      
      function rv = durations(obj)
         % HA.DURATIONS, where HA is an EEGenie object, collects state
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
         % HA.MEAN_DURATIONS, where HA is an EEGenie object, returns the
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
         % HA.STD_DURATIONS, where HA is an EEGenie object, returns the
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
         % HA.TRANSITIONS, where HA is an EEGenie object, returns a table
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
      
      function rv = totals(obj)
         % TOTALS: returns the total number of events, one value per
         % existing tag (sorted alphabetically)
         for i=1:obj.ntags
            rv(i) = obj.total(obj.Tags{i}); %#ok<AGROW>
         end
      end
      
      function rv = total(obj, tag)
         % TOTAL(TAG): returns the total number of events for the given tag
         rv = sum(obj.tagged(tag));
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
         dif = obj.Markers(obj.aidx).esv - obj.Markers(obj.aidx).ssv;
         rv = dif / obj.SRate;
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
      
      function update_parameters(obj)
         obj.nstates = length(obj.States);
         
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
      end
   end
end

%       
%       function rv = mark_count(obj, tag)
%          % samples per epoch
%          spe = obj.hz * obj.epoch;
%          % find all markers tagged with tag
%          x = ismember({obj.Markers.tag}, tag);
%          beg = [obj.Markers.start_pos];
%          fin = [obj.Markers.finish_pos];
%          em = floor(beg / spe) + 1;
%          rv = 0;
%       end
