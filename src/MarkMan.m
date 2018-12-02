classdef MarkMan < handle
   properties (SetAccess = private)
      marks
      tags
      ntags
      epoch
      EEG
      SRate % the sampling rate in Hz
   end
   
   properties (SetObservable)
      TOI % tag of interest
   end
   
   properties (Access = private)
      aidx % the indices of events tagged with the TOI
   end
   
   methods
      function obj = MarkMan(varargin)
         p = inputParser;
         p.addRequired('Markers')
         p.addParameter('Epoch',  10,  @isnumscalar)
         p.addParameter('Hz',    400,  @isnumscalar)
         p.addParameter('TOI', 'SWD', @ischar)
         p.addParameter('EEG',    [], @isnumvector)
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
         obj.settags;      
         obj.SRate = p.Results.Hz;
         obj.epoch = p.Results.Epoch;
         obj.TOI   = p.Results.TOI;
         obj.EEG   = p.Results.EEG;
         
         lprops = { 'TOI' };
         obj.addlistener(lprops, 'PostSet', @obj.HandleProps);
         obj.update_parameters
      end
      
      function rv = totals(obj)
         % TOTALS: returns the total number of events, one value per
         % existing tag (sorted alphabetically)
         for i=1:obj.ntags
            rv(i) = obj.total(obj.tags{i}); %#ok<AGROW>
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
         spe = obj.epoch * obj.SRate;
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
      
      function rv = durations(obj)
         dif = obj.marks(obj.aidx).esv - obj.marks(obj.aidx).ssv;
         rv = dif / obj.SRate;
      end
 
      function replacetag(obj, before, after)
         [obj.marks(obj.tagged(before)).tag] = deal(after);
         obj.settags;
      end
      
      function set_rms(obj)
         
         ss = obj.ssv(idx);
         es = obj.esv(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.marks(id(i)).rms = rms(frag);
         end
      end
      
      function set_freq(obj, eeg, tag)
         if nargin>1, idx=obj.tagged(tag); else, idx=obj.all; end
         
         ss = obj.ssv(idx);
         es = obj.esv(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.marks(id(i)).rms = rms(frag);
         end
      end
   end
   
   methods (Access=private)
      % start stamp vector
      function rv = ssv(obj)
         % the special notation to extract field values from a structure
         rv = [obj.marks(obj.aidx).start_pos];
      end
      
      % end stamp vector
      function rv = esv(obj)
         % the special notation to extract field values from a structure
         rv = [obj.marks(obj.aidx).finish_pos];
      end
      
      
      % resetting tag info after changes
      function obj = settags(obj)
         obj.tags  = unique({obj.marks.tag});
         obj.ntags = length(obj.tags);
      end
      
      function update_parameters(obj)
         if obj.TOI == false
            obj.aidx = true(1, length(obj.marks));
         else
            obj.aidx = obj.tagged(obj.TOI);
         end
      end
      
      % finding events tagged with tag
      function rv = tagged(obj, tag)
         rv = ismember({obj.marks.tag}, tag);
      end
      
   end
   
   methods (Static)
      % triggers the update_parameters function whenever any of the
      % observable properties are modified by the user
      function HandleProps(~, event)
         event.AffectedObject.update_parameters
      end
      
      function rv = mrkstr
         % the same function appears in sleeper. consider drying up
         rv = struct( ...
            'start_pos', {}, ...
            'finish_pos', {}, ...
            'tag', '');
      end
   end
end

%       % lacking a block-like construct (such as ruby's obj.each {||}), use
%       % indices as tokens to process markers in turn
%       function rv = each(obj, tag)
%          rv = find(obj.ids(tag));
%       end