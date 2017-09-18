classdef ERPool < handle
   %ERPool: quick analysis of event-related potentials
   %
   %ep = ERPool(EEG, EVENT_TIMES, EVENT_CODES)
   %
   %     Creates an ERPool object from a stream of EEG data and a list of
   %     events described by two vectors that must have the same length:
   %     EVENT_TIMES are expressed as seconds*Hz (in other words, an
   %     event_time corresponds to an index in the EEG signal); EVENT_CODES
   %     are integers indicating event type (e.g. 1=non target; 2=oddball).
   %
   %ep = ERPool(..., 'SRate', Hz) sets the sampling rate of the EEG signal
   %     to Hz. The default value is 4000
   %
   %ep = ERPool(..., 'Baseline', MS) sets the analysis epoch in
   %     milliseconds prior to stimulus onset; the default value is 200
   %
   %ep = ERPool(..., 'Response', MS) sets the analysis epoch in
   %     milliseconds following stimulus onset; the default value is 600
   %
   %Note that the above parameters can also be set at a later time, e.g.:
   %     ep.Response = 500;
   %
   %mx = ep.trials(CODE)
   %     returns a matrix of responses (one row for each repetition)
   %     time-locked to the stimulus indicated by CODE.
   %
   %mx = ep.average(CODE)
   %     returns the average response vector time-locked to the stimulus
   %     indicated by CODE.
   %
   %tr = ep.time_range
   %     returns an array of time points in milliseconds corresponding to
   %     the analysis epoch (eg: -200:1/KHz:600); useful for plotting ERPs
   %     if you are not using the built-in plot function (see below)
   %
   %     plot(ep.time_range, ep.average(CODE))
   %
   %ph = ep.plot(CODE)
   %     plots average ERPs time-locked to the stimulus specified by CODE.
   %     If CODE is omitted, all trials are plotted as separate lines, one
   %     for each CODE found. Returns the handle to the PLOT object
   
   properties (SetAccess = private)
      Hz
      baseline
      response
   end
   
   properties (Access = private)
      eeg
      times
      codes
      dirty
      matz
      KHz
      bl_samples % number of samples during baseline
      rs_samples % number of samples during response
   end
   
   %------------------------------------------------------- Public Methods
   methods
      %------------------------------------------------------- Constructor
      function obj = ERPool(eeg, event_times, event_codes, varargin)
         p = inputParser;
         p.addRequired('EEG',   @isnumvector)
         p.addRequired('Times', @isnumvector)
         p.addRequired('Codes', @isnumvector)
         p.addParameter('SRate',   4000, @isnumscalar)
         p.addParameter('Baseline', 200, @isnumscalar)
         p.addParameter('Response', 600, @isnumscalar)         
         p.parse(eeg, event_times, event_codes, varargin{:})
         
         obj.Hz       = p.Results.SRate;
         obj.baseline = p.Results.Baseline;
         obj.response = p.Results.Response;
         
         obj.eeg   = eeg;
         obj.times = event_times;
         obj.codes = event_codes;
         obj.dirty = true;
         obj.update_params
      end
      
      function rv = average(obj, code)
         rv = mean(obj.trials(code));
      end
      
      function rv = trials(obj, code)
         if obj.dirty, obj.create_mat; end
         rv = obj.matz(obj.codes==code, :);
      end
      
      function rv = plot(obj, codes)
         if nargin < 2, codes=unique(obj.codes); end
         d = zeros(length(codes), obj.bl_samples+obj.rs_samples);
         for x = codes(:)'
            d(x,:) = obj.average(x);
         end
         rv = plot(obj.time_range, d);
         set(gca, 'xlim', [-obj.baseline obj.response])
      end
      
      function rv = time_range(obj)
         if obj.dirty, obj.create_mat; end
         t = -obj.baseline:1/obj.KHz:obj.response;
         rv = t(2:end);
      end
      
      function setHz(obj, value)
         obj.Hz = value;
         obj.dirty = true;
      end
      
      function setBaseLine(obj, value)
         obj.baseline = value;
         obj.dirty = true;
      end
      
      function setResponse(obj, value)
         obj.response = value;
         obj.dirty = true;
      end
   end
   
   methods (Access=private)
      function create_mat(obj)
         obj.update_params
         bl = obj.bl_samples;
         rs = obj.rs_samples;
         obj.matz = zeros(length(obj.codes), bl+rs);
         for n = 1:length(obj.times)
            ce = obj.times(n);
            obj.matz(n, :) = obj.eeg(ce-bl+1:ce+rs);
         end
         obj.dirty = false;
      end
      
      function update_params(obj)
         obj.KHz = obj.Hz / 1000;
         obj.bl_samples = obj.baseline * obj.KHz;
         obj.rs_samples = obj.response * obj.KHz;
      end
   end
 end