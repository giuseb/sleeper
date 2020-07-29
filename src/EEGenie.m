classdef EEGenie < handle
   %EEGenie: simple calculations on hypnograms and EEG events
   %
   %   Analyzing vigilance states and "events", scored/detected on the
   %   basis of video-EEG-EMG recordings.
   %
   %   Objects of the EEGenie class operate on one or more of the following:
   %   * an EEG signal: an array of floats representing the potentials at
   %   the original sampling rate
   %   * an EMG signal: an array of floats representing the potentials at
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
   %   Type "doc EEGenie" at the command line or click below for more help

   properties (SetObservable)
      EEG
      EMG
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
      Delta     % the Delta band (default: [ 0.5   5.0])
      Theta     % the Theta band (default: [ 6,  9.5])
      Alpha     % the Alpha band (default: [ 8.0, 15.0])
      Sigma     % the Sigma band (default: [ 10.5, 15.0])
      Beta      % the Beta  band (default: [15.5, 30.0])
      Gamma     % the Gamma band (default: [ 30.0, 60.0])
      All       % the All band represent all frequencies (default: [ 0, 60])
      MinPad    % the minimum time (in seconds) between the beginning of an
                % event and the beginning of the corresponding epoch,
                % before flagging the event as problematic
      Verbose
      Bin       % time bin in hours: different from Block, which may
                % eventually be abandoned, if we drop epochs altogether
      Exclude   % tags to look for in order to remove the corresponding
                % epochs from the spectral analysis
      excluded  % epochs that contain one or more Exclusion tags
      nEpochs   % number epochs in the EEG/EMG

   end
   
   properties (SetAccess = private)
      hyplen      % number of epochs in the hypnogram
      nCurrEvents % number of events matching the TOI
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
   end
   
   methods %-------------------------------------------------- CONSTRUCTOR
      function obj = EEGenie(varargin)
         %   Input data and other parameters can be provided at construction time
         %   as name/value "argument pairs", e.g.
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
         % precedence, when provided.
         
         % the list of all possible arguments, with a default "null" value
         % and a validation function handle
         args = {
            'PFile',      '', @ishstring; % do not move PFile from args{1}
            'EEG',        [], @isnumvector;
            'EMG',        [], @isnumvector;
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
            'Sigma',      [], @isnumvector;
            'Gamma',      [], @isnumvector;  
            'All',        [], @isnumvector;  
            'MinPad',      1, @isnumscalar;
            'wType',      '', @ishstring;
            'Verbose', false, @islogical;
            'Exclude', {'ART'}, @iscellstr;
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
    
        %EG.SPECTRUM: returns the average power spectrum density for the 
         %given Hz bin dependin on Hz Max and Hz Min, one value for eache
         %Bin and for each state. If you specify 'normstate' power spectrum
         %density wil be normalized on total spectrum of the corresponding
         %vigilance status for the length of EEG rec. If you specify 
         %'normtot'power spectrum density wil be normalized on total
         %spectrum for the length of EEG rec. If you don't specify
         %anything function returns raw power spectrum density for 
         %the length of EEG rec. Specifying also 'bin' as second argument
         %function returns the power spectrum density normalized on each 
         %bin of interest. When you specified type of normalization
         %you can also specify as third element 'all' in order to obtain 
         %normalizaztion of power for each bin but in all recording.
  
     function spect= spectrum(varargin)
             narginchk(1,4);
             [varargin{:}] = convertStringsToChars(varargin{:});
              matches_bin = find(strcmpi('bin',varargin));
              matches_all = find(strcmpi('all',varargin));
              matches_normstate= find(strcmpi('normstate',varargin));
              matches_normtot= find(strcmpi('normtot',varargin));
              
              
               if any(matches_normstate)&& isempty(matches_bin) && isempty(matches_all)
              
                 varargin(matches_normstate)=[];
                 spect = spectrumstate(varargin{:});
               
               elseif any(matches_normtot)&& isempty(matches_bin)&& isempty(matches_all)
                   
                 varargin(matches_normtot)=[];
                 spect = spectrumtot(varargin{:});
                 
                elseif any(matches_normstate)&& any(matches_bin)&& isempty(matches_all)
                   varargin([matches_normstate matches_bin])=[];
                   spect = spectrumstatebin(varargin{:});
               
               elseif any(matches_normtot)&& any(matches_bin)&& isempty(matches_all)
                   varargin([matches_normtot matches_bin])=[];
                   spect = spectrumtotbin(varargin{:});
                
               elseif any(matches_bin)&& isempty(matches_normtot)&& isempty(matches_normstate)&& isempty(matches_all) 
                   varargin(matches_bin)=[];
                   spect = spectrumrawbin(varargin{:});
               
               elseif any(matches_bin)&& any(matches_normstate)&&isempty(matches_normtot) && any(matches_all) 
                   varargin([matches_normstate matches_bin matches_all])=[];
                   spect=spectrumstatebinall(varargin{:});
                   
               elseif any(matches_bin)&& isempty(matches_normstate)&& any(matches_normtot) && any(matches_all) 
                   varargin([matches_normtot matches_bin matches_all])=[];
                   spect=spectrumtotbinall(varargin{:});    
               
                                                  
               elseif isempty(matches_bin)&& isempty(matches_normtot)|| isempty(matches_normstate)&& isempty(matches_all)
                   spect = spectrumraw(varargin{:});
               end
     end
     
     %EG.SPECTRUMTOTBINALL: returns the total spectrum power in each Hz-BIN for
     %each time bin for each vigilance state normalized in the total power
     %of each vigilance state throughout all recording
     function rv=spectrumtotbinall(obj)
           sp_bin= obj.spectrum('bin');
           all_power= obj.allpower;  
           for i=1:obj.nblocks
            rv{i}=(sp_bin{i}/all_power)*100;
            end
         end
     %EG.SPECTRUMSTATEBINALL: returns the total spectrum power in each Hz-BIN for
     %each time bin for each vigilance state normalized in the total power
     %of each vigilance state throughout all recording
          function rv=spectrumstatebinall(obj)
           sp_bin= obj.spectrum('bin');
           all_power_state= obj.allpower('state');  
           for i=1:obj.nblocks
            rv{i}=(sp_bin{i}./all_power_state)*100;
            end
         end
          
     
     %EG.SPECTRUMRAW:returns the total spectrum power in each Hz-BIN for
     %all recording time for each vigilance state;
          function rv = spectrumraw(obj)
                 ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'HzMin', obj.HzMin,...
            'HzMax', obj.HzMax);
         sp = ep.spectra;
         % total epochs
         teps = length(sp);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
        %state
        states=obj.Hypno';

         if isempty(obj.excluded)
             for s=1:obj.nstates
               sp=sp(:,1:nepochs);
               sp1 = sp(:,states==s);
               rv(s,:) = mean(sp1,2,'omitnan'); 
             end
         else
          tex = ~obj.excluded;
            for s=1:obj.nstates
             sp=sp(:,1:nepochs);  
             sp1 = sp(:,states==s & tex);
             rv(s,:) = mean(sp1,2,'omitnan'); 
            end
         end
        end
       
    %EG.SPECTRUMRAWBIN:returns the total spectrum power in each Hz-BIN
    %for each time bin for each vigilance state;
          function rv = spectrumrawbin(obj)
                 ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'HzMin', obj.HzMin,...
            'HzMax', obj.HzMax);
         sp = ep.spectra;
         % total epochs
         teps = length(sp);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
        %state
        states=obj.Hypno';
        sp=sp(:,1:nepochs);
        split= size(sp, 2) / obj.nblocks*ones(1,obj.nblocks);
        statesplit=mat2cell(states,1,size(states, 2) / obj.nblocks*ones(1,obj.nblocks));
        spsplit = mat2cell(sp, size(sp,1), split);

         if isempty(obj.excluded)
             for i=1:obj.nblocks
                for s=1:obj.nstates
               sp1=spsplit{i}(:,statesplit{i}==s);
               rv{i}(s,:) = mean(sp1,2,'omitnan')'; 
                end
             end
         else
          tex = ~obj.excluded;
          texsplit=mat2cell(tex,1,size(tex, 2)/obj.nblocks*ones(1,obj.nblocks));
           for i=1:obj.nblocks
                for s=1:obj.nstates
               sp1=spsplit{i}(:,statesplit{i}==s & texsplit{i});
               rv{i}(s,:) = mean(sp1,2,'omitnan')'; 
                end
             end
         end
       end
       
     %EG.SPECTRUMSTATE:returns the spectrum power normalized for the power
     %of corresponding vigilance state in all recordings
          function rv = spectrumstate(obj) 
        rv=(obj.spectrum()./obj.allpower('state'))*100;
      end 
       
     %EG.SPECTRUMSTATEBIN:returns the spectrum power normalized for the
     %power of corresponding vigilance state in each time bin
         function rv = spectrumstatebin(obj) 
            sp_bin= obj.spectrum('bin');
            all_bin= obj.allpower('state','bin');
            for i=1:obj.nblocks
            rv{i}=(sp_bin{i}./all_bin(:,1))*100;
            end
         end
      
     %EG.SPECTRUMTOT:returns the spectrum power for each vigilance state 
     %normalized for total power in all recording;
         function rv = spectrumtot(obj) 
        rv=(obj.spectrum()/obj.allpower())*100; 
        end
        
     %EG.SPECTRUMTOTBIN:returns the spectrum power for each vigilance 
     %state normalized for total power in each time bin; 
         function rv = spectrumtotbin(obj) 
            sp_bin= obj.spectrum('bin');
            all_bin= obj.allpower('bin');
            for i=1:obj.nblocks
            rv{i}=(sp_bin{i}./all_bin(i))*100;
            end
         end
      
   %%%%%%%%%%%%%%%%%%% internal functions
          
    %EG.SPECTRUMTOTRAW:returns the total spectrum power in each Hz-BIN 
    %for all recording time indipendently from vigilance state;
     function rv = spectrumtotraw(obj)%total power per HZ in all EEG
           ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'HzMin', obj.HzMin,...
            'HzMax', obj.HzMax);
        sp=ep.spectra;
         % total epochs
        teps=length(sp);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
         
        if isempty(obj.excluded)
           sp=sp(:,1:nepochs);
           rv=mean(sp,2,'omitnan');        
        else
        tex = ~obj.excluded;
               sp=sp(:,1:nepochs);
               sp1= sp(:,tex);
               rv = mean(sp1,2,'omitnan');
            end
     end
     
     %EG.SPECTRUMTOTRAWBIN:returns the total spectrum power in each Hz-BIN 
     %each bin time indipendently from vigilance state;
     function rv = spectrumtotrawbin(obj)
         
           ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'HzMin', obj.HzMin,...
            'HzMax', obj.HzMax);
        sp=ep.spectra;
        % total epochs
        teps=length(sp);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
         blocksize=[1,obj.Block];
         FF= @(theBlockStructure) mean(theBlockStructure.data(:),'omitnan');
      if isempty(obj.excluded)
         rv = blockproc(sp(:,1:nepochs), blocksize, FF);
      else
          tex = ~obj.excluded;
          sp(:,tex==0)=[NaN];
          rv = blockproc(sp(:,1:nepochs), blocksize, FF);
      end
     end
        
            
         %EG.ALLPOWER: returns the average power for the given All BAND,
         % one value for Bin (if you specify 'Bin')and/or for state (if
         % you specify 'state' 
                         
   function pwr= allpower(varargin);
          narginchk(1,3);
          [varargin{:}] = convertStringsToChars(varargin{:});
          matches_bin = find(strcmpi('bin',varargin));
          matches_state= find(strcmpi('state',varargin));
          
          
    if any(matches_bin)& isempty(matches_state)
        varargin(matches_bin)=[];
        pwr = binallpower(varargin{:});
    elseif any(matches_state)& any(matches_bin)
        varargin([matches_bin,matches_state])=[];
        pwr = binstateallpower(varargin{:});
     elseif any(matches_state)& isempty(matches_bin)
        varargin([matches_state])=[];
        pwr = stateallpower(varargin{:});
    else
        pwr = generalpower(varargin{:}); 
    end
       end
       
     function rv= binallpower(obj)%total power for each bin
           ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'All', obj.All);
         pow = ep.bandpower('All');
         % total epochs
         teps = length(pow);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
         % "blocked" power: values by, eg, hour
         bpow = reshape(pow(1:nepochs), obj.Block, obj.nblocks);
         % negate "excluded" and reshape to mimic the above
        state_blocked=obj.blocked;

         if isempty(obj.excluded)
              for i=1:obj.nblocks
               t1 = bpow(:,i);
               rv(i) = mean(t1); %#ok<AGROW>
            end
             
         else
        tex = reshape(~obj.excluded, obj.Block, obj.nblocks);
               for i=1:obj.nblocks
               t1 = bpow(:,i);
               t2 = t1(tex(:,i));
               rv(i) = mean(t2,'omitnan'); %#ok<AGROW>
            end
         end
     end
       
     function rv = binstateallpower(obj, band)
                 ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'All', obj.All);
         pow = ep.bandpower('All');
         % total epochs
         teps = length(pow);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
         % "blocked" power: values by, eg, hour
         bpow = reshape(pow(1:nepochs), obj.Block, obj.nblocks);
         % negate "excluded" and reshape to mimic the above
        state_blocked=obj.blocked;

         if isempty(obj.excluded)
             for s=1:obj.nstates
            for i=1:obj.nblocks
               t1 = bpow(:,i);
               t2 = t1(state_blocked(:,i)==s);
               rv(s,i) = mean(t2); %#ok<AGROW>
            end
             end
         else
        tex = reshape(~obj.excluded, obj.Block, obj.nblocks);
         for s=1:obj.nstates
            for i=1:obj.nblocks
               t1 = bpow(:,i);
               t2 = t1(state_blocked(:,i)==s & tex(:,i));
               rv(s,i) = mean(t2,'omitnan'); %#ok<AGROW>
            end
         end
         end
                    end
       
     function rv = stateallpower(obj, band)
            ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'All', obj.All);
         pow = ep.bandpower('All');
         
         if isempty(obj.excluded)
             for s=1:obj.nstates
               t = pow(obj.Hypno==s);
               rv(s,:) = mean(t); %#ok<AGROW>
            end
             
         else
        tex = ~obj.excluded;
         for s=1:obj.nstates
               t1 = pow(obj.Hypno'==s & tex);
               rv(s,:) = mean(t1,'omitnan'); %#ok<AGROW>
            end
         end
         
                    end
       
     function rv = generalpower(obj, band)
            ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'All', obj.All);
         pow = ep.bandpower('All');
         
         if isempty(obj.excluded)
             rv = mean(pow); %#ok<AGROW>
            else
        tex = ~obj.excluded;
          rv = mean(pow(tex),'omitnan'); %#ok<AGROW>
          end
          
   end
         
        % BANDPOWER(BAND): returns the average power for the given BAND,
         % one value per epoch, for the entire EEG
       function rv = bandpower(obj, band)
         ep = EEpower(obj.EEG, ...
            'SRate', obj.SRate, ...
            'Ksize', obj.Ksize, ...
            'Kover', obj.Kover,...
            'Delta', obj.Delta,...
            'Theta', obj.Theta,...
            'Alpha', obj.Alpha,...
            'Beta', obj.Beta,...
            'Gamma', obj.Gamma,...
            'Sigma', obj.Sigma,...
            'All', obj.All);
         pow = ep.bandpower(band);
         % total epochs
         teps = length(pow);
         % number of valid epochs (discarding trailing epochs)
         nepochs = teps - rem(teps, obj.Block);
         % "blocked" power: values by, eg, hour
         bpow = reshape(pow(1:nepochs), obj.Block, obj.nblocks);
         % negate "excluded" and reshape to mimic the above
        state_blocked=obj.blocked;

         if isempty(obj.excluded)
             for s=1:obj.nstates
            for i=1:obj.nblocks
               t1 = bpow(:,i);
               t2 = t1(state_blocked(:,i)==s);
               rv(s,i) = mean(t2); %#ok<AGROW>
            end
             end
         else
        tex = reshape(~obj.excluded, obj.Block, obj.nblocks);
         for s=1:obj.nstates
            for i=1:obj.nblocks
               t1 = bpow(:,i);
               t2 = t1(state_blocked(:,i)==s & tex(:,i));
               rv(s,i) = mean(t2,'omitnan'); %#ok<AGROW>
            end
         end
         end
       end
       
           
       % EG.FILTER_EEG applies a Butterworth notch and a bandpass
         % chebyshev2 filter to the EEG vector
      function filter_eeg(obj, fn)
        
         if isempty(obj.EEG)
            disp('No EEG to filter')
            return
         end
         
         if nargin==1
            obj.EEG = notchband(obj.EEG);
         else
            obj.EEG = notchband(obj.EEG, fn);
         end
      end
      
      function rv = spectra(obj)
         % EG.SPECTRA, where EG is an EEGenie object, computes power
         % spectra over each of the events tagged with the TOI in the
         % markers array
         
         % retrieve start and end stamps for the currently tagged markers
         stimes = obj.ev_ini_pos;
         etimes = obj.ev_fin_pos;
         
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
                              'Kover', obj.Kover, ...
                              'HzMin',obj.HzMin,...
                              'HzMax',obj.HzMax);
            ee = ep.spectra;
            rv = [rv ee]; %#ok<AGROW>
         end
      end
   end
   
   methods %----------------------------------------------------> HYPNOGRAM
            
      function rv = state_epoch_counts(obj)
         % EG.STATE_EPOCH_COUNTS, where EG is an EEGenie object, returns
         % the number of epochs for each state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i, :) = sum(obj.blocked==i);
         end
      end
      
      %       function rv = state_minutes(obj)
      %          % EG.MINUTES, where EG is an EEGenie object, returns the total
      %          % duration in minutes for each state scored in the hypnogram
      %          rv = obj.state_seconds / 60;
      %       end
      
      function rv = state_total_durations(obj)
         % EG.STATE_TOTAL_DURATIONS, where EG is an EEGenie object, returns
         % the total duration in seconds for each state scored in the
         % hypnogram
         rv = obj.state_epoch_counts * obj.Epoch;
      end
      
      function rv = state_proportions(obj)
         % EG.STATE_PROPORTIONS, where EG is an EEGenie object, returns the
         % fraction of time spent in each state scored in the hypnogram
         s = sum(obj.state_epoch_counts);
         r = repmat(s, obj.nstates, 1);
         rv = obj.state_epoch_counts ./ r;
      end
      
      function rv = state_episode_counts(obj)
         % EG.STATE_EPISODE_COUNTS, where EG is an EEGenie object, returns
         % the number of scored episodes for each state in the hypnogram
         t = diff([0; obj.Hypno]);
         r = reshape(t, obj.Block, obj.nblocks);
         rv = zeros(obj.nstates, obj.nblocks);
         for i=1:obj.nstates
            rv(i,:) = sum(obj.blocked==i & r);
         end
      end
      
      function rv = state_episode_durations(obj)
         % EG.STATE_EPISODE_DURATIONS, where EG is an EEGenie object,
         % collects state episode durations. It returns a cell matrix, one
         % row for each state, one column for each block of epochs. Each
         % cell contains an array of episode durations in seconds.
         
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
      
      function rv = state_episode_duration_mean(obj)
         % EG.STATE_EPISODE_DURATION_MEAN, where EG is an EEGenie object,
         % returns the mean episode durations (in seconds) for each state
         % scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         du = obj.state_episode_durations;
         for i = 1:obj.nstates
            for j = 1:obj.nblocks
               rv(i, j) = mean(du{i,j});
            end
         end
      end
      
      function rv = state_episode_duration_std(obj)
         % EG.STATE_EPISODE_DURATION_STD, where EG is an EEGenie object,
         % returns the standard deviation of episode durations (in seconds)
         % for each state scored in the hypnogram
         rv = zeros(obj.nstates, obj.nblocks);
         du = obj.state_episode_durations;
         for i = 1:obj.nstates
            for j = 1:obj.nblocks
               rv(i,j) = std(du{i,j});
            end
         end
      end
      
      function rv = state_transitions(obj)
         % EG.STATE_TRANSITIONS, where EG is an EEGenie object, returns a
         % table containing counts of all transition types
         
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
    
   
   methods %-------------------------------------------------------> EVENTS
      
      function rv = event_total_count(obj)
         % EG.event_total_count, where EG is an EEGenie object, returns the
         % total number of events for the current TOI
         rv = histcounts(obj.event_ini_times, 'BinWidth', obj.binsec);
      end
      
      function rv = events_per_epoch(obj)
         % EG.EVENTS_PER_EPOCH, where EG is an EEGenie object, returns the
         % number of events for the current TOI that begin in each epoch
         
         sss = obj.ev_ini_pos;
         % the number of samples per epoch
         spe = obj.Epoch * obj.SRate;
         % the binning ceiling
         cei = ceil(sss(end)/spe)*spe;
         % the bins, including the right edge
         bin = 0:spe:cei;
         % event count per epoch
         rv = histcounts(sss, bin);
      end
      
      function [rv, warn] = event_states(obj)
         % EG.event_states, where EG is an EEGenie object, returns the
         % number of events for the current TOI that begin in each epoch
         rv = zeros(obj.nCurrEvents, 1);
         warn = [];
         if obj.NoHyp
            warning('No hypnogram present, no action taken')
            return
         end
         tm = obj.event_ini_times;
         for i = 1:obj.nCurrEvents
            epo = floor(tm(i) / obj.Epoch) + 1;
            off = tm(i) - (epo-1) * obj.Epoch;
            rv(i) = obj.Hypno(epo);
            if epo > 1 && off < obj.MinPad && rv(i) ~= obj.Hypno(epo-1)
               warn = [warn, i]; %#ok<AGROW>
               warning('Double-check event #%d', i)
            end
         end
      end
      
      function rv = event_ini_times(obj)
         rv = obj.ev_ini_pos / obj.SRate;
      end
      
      function rv = event_fin_times(obj)
         rv = obj.ev_fin_pos / obj.SRate;
      end
      
      function rv = event_durations(obj)
         dif = obj.ev_fin_pos - obj.ev_ini_pos;
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
         ss = obj.ev_ini_pos(idx);
         es = obj.ev_fin_pos(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.Markers(id(i)).rms = rms(frag);
         end
      end
      
      function set_freq(obj, eeg, tag)
         if nargin>1, idx=obj.tagged(tag); else, idx=obj.all; end
         
         ss = obj.ev_ini_pos(idx);
         es = obj.ev_fin_pos(idx);
         id = find(idx);
         
         for i=1:length(idx)
            frag = eeg(ss(i):es(i));
            obj.Markers(id(i)).rms = rms(frag);
         end
      end
   end
   
   methods (Static, Access=private)
      % triggers the update_parameters function whenever any of the
      % observable properties are modified by the user
      function HandleProps(~, event)
         event.AffectedObject.update_parameters
      end
   end
   
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   %%%%%%%%%%%%%%%%%%% PRIVATE METHODS%%%%%%%%%%%%%%%%%%%%%
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   methods (Access = private)
      % current TOI: list of initial stamps
      function rv = ev_ini_pos(obj)
         % the special notation to extract field values from a structure
         rv = [obj.Markers(obj.aidx).start_pos];
      end
      
      % current TOI: list of final stamps
      function rv = ev_fin_pos(obj)
         % the special notation to extract field values from a structure
         rv = [obj.Markers(obj.aidx).finish_pos];
      end
      
      % resetting tag info after changes
      function obj = settags(obj)
         obj.Tags  = unique({obj.Markers.tag});
         obj.ntags = length(obj.Tags);
      end
      
      % finding tagged events: argument tag is the event's string, the
      % return value is a boolean array pointing to all matching markers.
      function rv = tagged(obj, tag)
         rv = ismember({obj.Markers.tag}, tag);
      end
      
      % find epoch number given an event's start_pos or finish_pos
      function rv = epoch_of_event(obj, pos)
          if floor(pos / (obj.SRate * obj.Epoch))==obj.nEpochs;
              rv=floor(pos / (obj.SRate * obj.Epoch));
          else
         rv = floor(pos / (obj.SRate * obj.Epoch))+1;
          end
      end
      
      %------------------------------------------------> PARAMETER UPDATING
      function update_parameters(obj)
         obj.nstates = length(obj.States);
         obj.spk     = obj.Ksize * obj.SRate;
         
         %!obj.NoEEG = isempty(obj.EEG);
         %!obj.NoEMG = isempty(obj.EMG);
         
         if ~isempty(obj.EEG)
            obj.nEpochs = floor(length(obj.EEG) / (obj.SRate * obj.Epoch));
         elseif ~isempty(obj.EMG)
            obj.nEpochs = floor(length(obj.EMG) / (obj.SRate * obj.Epoch));
         end
         
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
            
            obj.nCurrEvents = sum(obj.aidx);
            
            % Set binsize in seconds
            if obj.Bin
               % Bin is given in hours, so multiply
               obj.binsec = obj.Bin * 3600;
            else
               % Bin is zero, use the last marker time stamp as binsize
               obj.binsec = max(obj.event_ini_times);
            end
            
            % checking exclusions
            obj.excluded = false(1, obj.nEpochs);
            tidx = obj.tagged(obj.Exclude);
            for i=obj.Markers(tidx)
               start_epoch = obj.epoch_of_event(i.start_pos);
               finish_epoch = obj.epoch_of_event(i.finish_pos);
               obj.excluded(start_epoch:finish_epoch) = true;
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

            hl = obj.nEpochs;
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

% function rv = start_stamps(obj)
%    rv = obj.ev_ini_pos;
% end
% 
% function rv = end_stamps(obj)
%    rv = obj.ev_fin_pos;
% end

