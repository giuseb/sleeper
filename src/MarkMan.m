classdef MarkMan < handle
   properties (SetAccess = private)
      marks
      tags
      ntags
      epoch
      block
      hz
   end
   
   methods
      function obj = MarkMan(varargin)
         p = inputParser;
         p.addRequired('Markers')
         p.addParameter('Epoch', 10, @isnumscalar)
         p.addParameter('States', {'REM', 'NREM', 'Wake'}, @iscellstr)
         p.addParameter('Block', 0, @isnumscalar)
         p.addParameter('Hz', 400, @isnumscalar)
         p.parse(varargin{:})
         
         m = p.Results.Markers;
         if isa(m, 'char')
            load(m, 'markers')
            obj.marks = markers;
         elseif isa(m, 'struct')
            obj.marks = m;
         else
            error('wrong argument type')
         end
         obj.settags
         
         obj.hz    = p.Results.Hz;
         obj.epoch = p.Results.Epoch;
         obj.block = p.Results.Block;
         
      end

      function obj = tagfix(obj, before, after)
         [obj.marks(obj.ids(before)).tag] = deal(after);
         obj.settags;
      end

      function rv = totals(obj)
         for i=1:obj.ntags
            t = obj.tags{i};
            rv(i) = sum(obj.ids(t)); %#ok<AGROW>
         end
      end
      
      function rv = events_per_epoch(obj, varargin)
         idx = obj.ids(varargin);
         % the list of start positions
         sss = obj.start_stamps(idx);
         % the number of samples per epoch
         spe = obj.epoch * obj.hz;
         % the binning ceiling
         cei = ceil(sss(end)/spe)*spe;
         % the bins, including the right edge
         bin = 0:spe:cei;
         % event count per epoch
         rv = histcounts(sss, bin);
      end
      
      function rv = start_times(obj, varargin)
         idx = obj.ids(varargin);
         rv = obj.start_stamps(idx) / obj.hz;
      end
      
      function rv = end_times(obj, varargin)
         idx = obj.ids(varargin);
         rv = obj.end_stamps(idx) / obj.hz;
      end
      
      function rv = durations(obj, varargin)
         idx = obj.ids(varargin);
         dif = obj.marks(idx).end_stamps - obj.marks(idx).start_stamps;
         rv = dif / obj.hz;
      end     
      
      function obj = settags(obj)
         obj.tags  = unique({obj.marks.tag});
         obj.ntags = length(obj.tags);
      end
   end
   
   methods (Access=private)
      function rv = start_stamps(obj, idx)
         rv = [obj.marks(idx).start_pos];
      end
      
      function rv = end_stamps(obj, idx)
         rv = [obj.marks(idx).finish_pos];
      end
      
      function rv = ids(obj, tag)
         if isempty(tag)
            rv = true(1, length(obj.marks));
         else
            rv = ismember({obj.marks.tag}, tag);
         end
      end
   end
   
   methods (Static)
      function rv = mrkstr
         % the same function appears in sleeper. consider drying up
         rv = struct( ...
            'start_pos', {}, ...
            'finish_pos', {}, ...
            'tag', '');
      end
   end
end