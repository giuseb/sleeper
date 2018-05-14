classdef HypnoAnal < handle
   %HYPNOANAL: simple calculations on hypnograms
   %
   %   The HYPNOANAL class (pun intended) helps to analyze hypnograms, i.e.
   %   arbitrarily long sequences of epochs (typically a few seconds each)
   %   classified depending on vigilance states. The program “sleeper”
   %   generates hypnograms as vectors of integers, where each value
   %   corresponds to a specific state.
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

   %----------------------------------------------------------- Properties
   properties (SetAccess = private)
      hypno
      states
      epoch  % epoch duration in seconds
      block  % number of epochs in a block
      hyplen % number of epochs in the hypnogram
   end

   properties (Access = private)
      changes % all the transitions computed as diff
      nblocks % the number of blocks in the hypnogram
      nstates % the number of states in the hypnogram
      blocked % the hypongram reshaped based on block size
   end
   %------------------------------------------------------- Public Methods
   methods
      %------------------------------------------------------- Constructor
      function obj = HypnoAnal(hypnogram, varargin)
         p = inputParser;
         p.addRequired( 'hypnogram', @isnumvector)
         p.addParameter('Epoch', 10, @isnumscalar)
         p.addParameter('States', {'REM', 'NREM', 'Wake'}, @iscellstr)
         p.addParameter('Block', 0, @isnumscalar)
         p.parse(hypnogram, varargin{:})

         hy = p.Results.hypnogram(:); % enforce vertical!
         obj.block  = p.Results.Block;
         % trim the hypnogram if necessary, based on block size
         if obj.block
            % blocking has been specified, determine the number of blocks
            obj.nblocks = floor(length(hy) / obj.block);
         else
            % whole hypnogram as a single block
            obj.nblocks = 1;
            obj.block = length(hy);
         end
         % getting the trimmed hypnogram size...
         obj.hyplen  = obj.block * obj.nblocks;
         % ...and the trimmed hypnogram
         obj.hypno   = hy(1:obj.hyplen);
         obj.blocked = reshape(obj.hypno, obj.block, obj.nblocks);
         c = [diff(2.^(obj.hypno-1)); 0];
         obj.changes = reshape(c, obj.block, obj.nblocks);
         obj.states  = p.Results.States;
         obj.nstates = length(obj.states);
         obj.epoch   = p.Results.Epoch;     

         % the hypnogram should not contain NaNs; warn if any
         nani = isnan(obj.hypno);
         if any(nani)
            error('NaNs in hypnogram at positions: %d', find(nani))
         end
      end

      %------ AGGREGATE METHODS, returning one element per state

      function rv = epochs(obj)
         % HA.EPOCHS, where HA is a HypnoAnal object, returns the number of
         % epochs for each state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i, :) = sum(obj.blocked==i);
         end
      end

      function rv = minutes(obj)
         % HA.MINUTES, where HA is a HypnoAnal object, returns the total
         % duration in minutes for each state scored in the hypnogram
         rv = obj.seconds / 60;
      end

      function rv = seconds(obj)
         % HA.SECONDS, where HA is a HypnoAnal object, returns the total
         % duration in seconds for each state scored in the hypnogram
         rv = obj.epochs * obj.epoch;
      end
      
      function rv = fractions(obj)
         % HA.FRACTIONS, where HA is a HypnoAnal object, returns the
         % fraction of time spent in each state scored in the hypnogram
         s = sum(obj.epochs);
         r = repmat(s, obj.nstates, 1);
         rv = obj.epochs ./ r;
      end

      function rv = episodes(obj)
         % HA.EPISODES, where HA is a HypnoAnal object, returns the number
         % of scored episodes for each state in the hypnogram
         t = diff([0; obj.hypno]);
         r = reshape(t, obj.block, obj.nblocks);
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i,:) = sum(obj.blocked==i & r);
         end
      end

      function rv = durations(obj)
         % HA.DURATIONS, where HA is a HypnoAnal object, collects state
         % episode durations. It returns a cell matrix, one row for each
         % state, one column for each block of epochs. Each cell contains
         % an array of episode durations in seconds.

         % set up the cell array to be returned
         rv = cell(obj.nstates, obj.nblocks);
         
         % get a straightened temporary hypnogram
         hy = obj.blocked(:);
         % use the first epoch as a starting point
         c_stg = hy(1); % the current stage
         c_len = 1;     % the current episode duration (in epochs)
         c_blo = 1;     % the current block
         
         % find all state changes
         df = diff(hy);
         % we don't need the first epoch anymore
         hy(1) = [];
         
         % brute force approach, not very idiomatic, but it seems
         % complicated to solve otherwise; looping over each epoch...
         for i=1:obj.hyplen-1
            if df(i)
               % we have found a state change, so the duration of the
               % previous state must be saved
               rv{c_stg, c_blo} = [rv{c_stg, c_blo}; c_len * obj.epoch];
               % save the current state and reset vars
               c_stg = hy(i);
               c_len = 1;
               c_blo = floor(i/obj.block)+1;
            else
               c_len = c_len + 1;
            end
         end
         rv{c_stg, c_blo} = [rv{c_stg, c_blo}; c_len * obj.epoch];
      end

      function rv = mean_durations(obj)
         % HA.MEAN_DURATIONS, where HA is a HypnoAnal object, returns the
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
         % HA.STD_DURATIONS, where HA is a HypnoAnal object, returns the
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
         % HA.TRANSITIONS, where HA is a HypnoAnal object, returns a table
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
            s1(i) = obj.states(c(1,i));
            s2(i) = obj.states(c(2,i));
            ct(i,:) = sum(obj.changes==d(i));
         end
         rv = table(s1, s2, ct, 'variablenames', {'Before' 'After' 'Count'});
      end

      function rv = istransition(obj, st1, st2)
         rv = obj.blocked(1:end-1)==st1 & obj.hypno(2:end)==st2;
      end

      function rv = tr_count(obj, st1, st2)
         rv = sum(obj.istransition(st1, st2));
      end
   end
end
