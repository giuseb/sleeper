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
         obj.hyplen  = obj.block * obj.nblocks;
         obj.hypno   = hy(1:obj.hyplen);
         obj.blocked = reshape(obj.hypno, obj.block, obj.nblocks);
         obj.states  = p.Results.States;
         obj.nstates = length(obj.states);
         obj.epoch   = p.Results.Epoch;
         obj.changes = [NaN; diff(2.^(obj.hypno-1))];

         % the hypnogram should not contain NaNs; warn if any
         nani = isnan(obj.hypno);
         if any(nani)
            warning('NaNs in hypnogram at positions: %d', find(nani))
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

      function rv = episodes(obj)
         % HA.EPISODES, where HA is a HypnoAnal object, returns the number
         % of scored episodes for each state in the hypnogram
         t = obj.changes;
         t(1) = 0;
         for i=1:obj.n_states
            rv(i) = sum(obj.hypno==i & t); %#ok<AGROW>
         end
      end

      function rv = durations(obj)
         % HA.DURATIONS, where HA is a HypnoAnal object, collects state
         % episode durations. It returns a cell array, one cell for each
         % scored state. Each cell contains an array of episode durations
         % in seconds.
         n = obj.n_states;
         % set up the cell array to be returned
         rv = cell(1, n);
         % use the first epoch as a starting point
         c_stg = obj.hypno(1);
         c_len = 1;
         % loop over each epoch
         for i=2:length(obj.hypno)
            if obj.changes(i)
               rv{c_stg} = [rv{c_stg}; c_len * obj.epoch];
               c_stg = obj.hypno(i);
               c_len = 1;
            else
               c_len = c_len + 1;
            end
         end
         rv{c_stg} = [rv{c_stg}; c_len * obj.epoch];
      end

      function rv = mean_durations(obj)
         % HA.MEAN_DURATIONS, where HA is a HypnoAnal object, returns the
         % mean episode durations (in seconds) for each state scored in the
         % hypnogram
         for i = 1:obj.n_states
            rv(i) = mean(obj.durations{i}); %#ok<AGROW>
         end
      end

      function rv = std_durations(obj)
         % HA.STD_DURATIONS, where HA is a HypnoAnal object, returns the
         % standard deviation of episode durations (in seconds) for each
         % state scored in the hypnogram
         for i = 1:obj.n_states
            rv(i) = std(obj.durations{i}); %#ok<AGROW>
         end
      end


      function rv = fractions(obj)
         % HA.FRACTIONS, where HA is a HypnoAnal object, returns the
         % fraction of time spent in each state scored in the hypnogram
         tots = length(obj.hypno) * obj.epoch;
         rv = obj.seconds / tots;
      end

      function rv = transitions(obj)
         i = 0;
         for st1 = 1:length(obj.states)-1
            for st2 = st1+1:length(obj.states)
               i = i+1;
               s1(i) = obj.states(st1);
               s2(i) = obj.states(st2);
               ct(i) = obj.tr_count(st1, st2);
               i = i+1;
               s1(i) = obj.states(st2);
               s2(i) = obj.states(st1);
               ct(i) = obj.tr_count(st2, st1);
            end
         end
         rv = table(s1', s2', ct', 'variablenames', {'Before' 'After' 'Count'});
      end

      function rv = istransition(obj, st1, st2)
         rv = obj.hypno(1:end-1)==st1 & obj.hypno(2:end)==st2;
      end

      function rv = tr_count(obj, st1, st2)
         rv = sum(obj.istransition(st1, st2));
      end

      function rv = n_states(obj)
         rv = length(obj.states);
      end
   end
end
