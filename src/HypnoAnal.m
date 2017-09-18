classdef HypnoAnal < handle
   %HypnoAnal: simple calculations on hypnograms
   %
   %   ha = HypnoAnal(hyp)
   %
   %   where hyp is a numerical vector, builds the object. The following
   %   name/value pair parameters may be added:
   %
   %   ha = HypnoAnal(hyp, 'Epoch', s) specifies the epoch duration in
   %   seconds (default is 10)
   %
   %   ha = HypnoAnal(hyp, 'Stages', {'REM', 'NREM', 'Wake'}) specifies the
   %   states (the ones shown here are the defaults); every "1" in the
   %   hystogram vector is interpreted as 'REM', every "2" is 'NREM', and
   %   so on.
   %
   %   After constructions, you can execute any of the following:
   %
   %   ha.tot_epochs
   %   ha.tot_seconds
   %   ha.tot_minutes
   %   ha.fractions
   %   ha.n_episodes
   %   ha.durations
   %   ha.mean_sec_durations
   %   ha.std_sec_durations
   %
   %   All these functions return an array with as many elements as there
   %   are states, in the order specified as above.
   %
   %   ha.changes  returns state transitions at the epoch in which they
   %   occur, in number form. The first element is always NaN. Assuming the
   %   default state list {'REM', 'NREM', 'Wake'}, here are the possible
   %   transition values:
   %
   %      0: no transition
   %      1: REM  -> NREM     -1: NREM -> REM
   %      2: NREM -> Wake     -2: Wake -> NREM
   %      3: REM  -> Wake     -3: Wake -> REM
   %
   %   Unique transitions can be encoded for an arbitrary number of states.
   %   For example:
   % 
   
   %----------------------------------------------------------- Properties
   properties (SetAccess = private)
      hypno
      changes
      states
      epoch
   end
   %------------------------------------------------------- Public Methods
   methods
      %------------------------------------------------------- Constructor
      function obj = HypnoAnal(hypnogram, varargin)
         p = inputParser;
         p.addRequired( 'hypnogram', @isnumvector)
         p.addParameter('Epoch', 10, @isnumscalar)
         p.addParameter('States', {'REM', 'NREM', 'Wake'}, @iscellstr)
         p.parse(hypnogram, varargin{:})

         % assumes a vector
         obj.hypno  = p.Results.hypnogram(:); % enforce vertical!
         obj.states = p.Results.States;
         obj.epoch  = p.Results.Epoch;
         obj.changes = [NaN; diff(2.^(obj.hypno-1))];
         
         % the hypnogram should not contain NaNs; warn if any
         nani = isnan(obj.hypno);
         if any(nani)
            warning('NaNs in hypnogram at positions: %d', find(nani))
         end
      end
      
      function rv = istransition(obj, st1, st2)
         rv = obj.hypno(1:end-1)==st1 & obj.hypno(2:end)==st2;
      end
      
      function rv = tr_count(obj, st1, st2)
         rv = sum(obj.istransition(st1, st2));
      end
      
      function rv = tr_counts(obj)
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
      
      function rv = tot_seconds(obj)
         rv = obj.tot_epochs * obj.epoch;
      end
      
      function rv = tot_minutes(obj)
         rv = obj.tot_seconds / 60;
      end
      
      function rv = fractions(obj)
         tots = length(obj.hypno) * obj.epoch;
         rv = obj.tot_seconds / tots;         
      end
      
      function rv = n_episodes(obj)
         for i=1:obj.n_states
            rv(i) = sum(obj.hypno==i & obj.changes); %#ok<AGROW>
         end
      end
      
      function rv = mean_sec_durations(obj)
         d = obj.durations;
         for i = 1:obj.n_states
            rv(i) = mean(d{i} * obj.epoch); %#ok<AGROW>         
         end
      end
      
      function rv = std_sec_durations(obj)
         d = obj.durations;
         for i = 1:obj.n_states
            rv(i) = std(d{i} * obj.epoch); %#ok<AGROW>         
         end
      end
      
      function rv = durations(obj)
         n = obj.n_states;
         % set up the cell array to be returned
         rv = cell(1, n);
         % use the first epoch as a starting point
         c_stg = obj.hypno(1);
         c_len = 1;
         % loop over each epoch
         for i=2:length(obj.hypno)
            if obj.changes(i)
               rv{c_stg} = [rv{c_stg}; c_len];
               c_stg = obj.hypno(i);
               c_len = 1;
            else
               c_len = c_len + 1;
            end
         end
         rv{c_stg} = [rv{c_stg}; c_len];
      end
      
      function rv = tot_epochs(obj)
         for i=1:obj.n_states
            rv(i) = sum(obj.hypno==i); %#ok<AGROW>
         end
      end
      
      function rv = n_states(obj)
         rv = length(obj.states);
      end
   end
end