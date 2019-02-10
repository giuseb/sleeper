classdef EEpower < handle
   %EEpower: power density estimates for signals
   %
   %   The EEpower class helps computing power density estimates of
   %   digitized signals, based on Welch's method. At its core, EEpower
   %   uses Matlab's own pwelch function, but it provides convenience
   %   methods for the analysis of EEG and EMG recordings. Signals are
   %   subdivided in epochs of arbitrary duration and power spectra are
   %   computed for each of the epochs. See "Public methods" below for a
   %   list of things you can do with EEpower objects.
   %
   %   ---<===[[[ Constructor ]]]===>---
   %
   %   eep = EEpower(EEG, SRate) creates an EEpower object based on a
   %   single EEG (or other type of) signal, given as a one-dimensional
   %   numeric vector.
   %
   %   eep = EEpower(EEG, 'name', value, ...)
   %
   %   Default parameters are stored in a separate YAML file. To view them:
   %   >> edit eepower.yml
   %   
   %   The following name-value pairs can be added to the constructor in
   %   order to override defaults:
   %
   %   SRate:  signal sample rate in Hz
   %   Epoch:  time over which spectra are computed (seconds)
   %   Ksize:  length of the moving kernel (seconds)
   %   Kover:  kernel overlap (fraction)
   %   wType:  the kernel window type; choose between:
   %           hann, hamming, blackman, blackmanharris, kaiser
   %   HzMin:  the minimum frequency of interest (Hz)
   %   HzMax:  the maximum frequency of interest (Hz)
   %   Delta:  delta-band frequency range (Hz)
   %   Theta:  theta-band frequency range (Hz)
   %   Alpha:  alpha-band frequency range (Hz)
   %   Beta:   beta-band frequency range (Hz)
   %
   %   ---<===[[[ Public methods ]]]===>---
   %
   %   SPECTRA
   %   LOG_SPECTRA
   %   POWER_DENSITY_CURVE
   %   SPECTROGRAM
   %
   % Last modified: 17 Sep 2017
   
   %----------------------------------------------------------- Properties
   properties (SetAccess = private)
      EEG       % the actual EEG signal
      NumEpochs % the number of epochs in the data file
      MaxPwr    % maximum power computed over the entire signal
      MinPwr    % minimum power computed over the entire signal
      MaxLogPwr % maximum log power computed over the entire signal
      MinLogPwr % minimum log power computed over the entire signal
      HzRange   % the frequencies of interest
   end
   properties (SetObservable)
      SRate     % signal sampling rate
      Epoch     % scoring epoch in seconds  (default: 10)      
      Ksize     % kernel size in seconds    (default: 2)
      Kover     % kernel overlap fraction   (default: 0.5)
      HzMin     % minimum plotted frequency (default: 0)
      HzMax     % maximum plotted frequency (default: 30)
      wType     % the window type (default: 'hanning')
      Delta     % the Delta band (default: [ 0.5   4.0])
      Theta     % the Theta band (default: [ 4.5,  7.5])
      Alpha     % the Alpha band (default: [ 8.0, 15.0])
      Beta      % the Beta  band (default: [15.5, 30.0])
   end
   properties (Access = private)
      spe     % the number of samples in a single epoch
      spk     % the number of samples in a single kernel
      freqs   % vector of frequencies for which power is computed
      hz_rng  % frequency-of-interest indexes
      pxx     % the power spectra over time
      dirty   % true if the spectra need recomputing
      samples % number of total samples after flooring to the closet epoch
      win     % the kernel window
   end
   
   %------------------------------------------------------- Public Methods
   methods
      %------------------------------------------------------- Constructor
      function obj = EEpower(eeg, varargin)
         % type >> help EEpower for help on how to use the EEpower class
         % constructor
         
         % This constructor works on the assumption that no magic numbers
         % are stored in the code, all default parameters are written in
         % the file eepower.yml, in the src directory. To change any values
         % upon construction, a custom YAML file can be passed (via the
         % PFile argument), but individual name-value pairs have
         % precedence, when given.

         % the list of all possible arguments, with a default "null" value
         % and a validation function handle
         args = {
            'PFile',  '', @ishstring;
            'SRate',  [], @isnumscalar;
            'Epoch',  -1, @isnumscalar;
            'Ksize',  -1, @isnumscalar;
            'Kover',  -1, @isnumscalar;
            'HzMin',  -1, @isnumscalar;
            'HzMax',  -1, @isnumscalar;
            'Delta',  [], @isnumvector;
            'Theta',  [], @isnumvector;
            'Alpha',  [], @isnumvector;
            'Beta',   [], @isnumvector;
            'wType',  '', @ishstring;
            };
         
         % input arguments parsing
         p = inputParser;
         p.addRequired( 'EEG', @isnumvector)
         for i=1:length(args)
            p.addParameter(args{i,1}, args{i,2}, args{i,3})
         end
         p.parse(eeg, varargin{:})

         % grab default parameters
         y = readparams('eepower.yml', 'eepower');
         % if an optional params YAML file was given...
         if ~isempty(p.Results.PFile)
            % read the corresponding YAML file
            ty = readparams([p.Results.PFile '.yml'], 'eepower');
            % merge those parameters with the defaults
            for f = fieldnames(ty)'
               y.(f) = ty.(f);
            end
         end

         % transfer parameters to the object
         obj.EEG   = p.Results.EEG;
         % exclude PFile from argument list
         for i=2:length(args)
            a = args{i,1}; % the field
            % has this parametere been passed as an input argument?
            passed = ~isequal(p.Results.(a), args{i,2});
            % if so, then override the default
            obj.(a)=cas(passed, p.Results.(a), getfieldi(y,a));
         end
         obj.addlistener(args(2:end,1), 'PostSet', @obj.HandleProps);
         obj.update_parameters
      end
      %------------------------------------------------ Return raw spectra
      function rv = spectra(obj, epochs)
         % S = eep.spectra
         %
         % where eep is an EEpower object, returns the power spectra for
         % the currently selected frequency range and for the entire
         % recording. Each column in the output matrix S is a spectrum, one
         % for each epoch.
         %
         % S = eep.spectra(epochs)
         %
         % returns spectra only for the specified epochs (as a vector of
         % indices or booleans)
         if obj.dirty, obj.computeWelch; end
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         rv = obj.pxx(obj.hz_rng, epochs);
      end
      %------------------------------------------------ Return log spectra
      function rv = log_spectra(obj, epochs)
         % S = eep.log_spectra
         %
         % where eep is an EEpower object, returns the base-10 logarithms
         % of the power spectra for the currently selected frequency range
         % and for the entire recording. Each column in the output matrix S
         % is a spectrum, one for each epoch.
         %
         % S = eep.log_spectra(epochs)
         %
         % returns spectra only for the specified epochs (as a vector of
         % indices or booleans)
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         rv = 10*log10(obj.spectra(epochs));
         obj.MinLogPwr = min(rv(:));
         obj.MaxLogPwr = max(rv(:));
      end
      %------------------------------------------------ Mean power density
      function rv = mean_power(obj, epochs)
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         rv = mean(obj.spectra(epochs), 2);
      end
      %------------------------------------------- Mean band power density
      function rv = mean_band_power(obj, band, epochs)
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         rv = mean(obj.mean_power(epochs));
      end
      %------------------------------------------------ Plot power density
      function rv = power_density_curve(obj, epochs)
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         sa = mean(obj.spectra(epochs), 2);
         rv = semilogy(obj.HzRange, sa);
      end
      %-------------------------------------------------- Plot spectrogram
      function rv = spectrogram(obj, epochs)
         if nargin < 2, epochs = 1:obj.NumEpochs; end
         rv = imagesc(obj.log_spectra(epochs));
         set(gca, 'tickdir', 'out')
         axis xy
         colormap(jet(256))
      end
   end
   
   methods (Static)
      % triggers the update_parameters function whenever any of the
      % observable properties are modified by the user
      function HandleProps(~, event)
         event.AffectedObject.update_parameters
      end
   end
   %------------------------------------------------------ Private methods
   methods (Access=private)
      %------------------------------------------------- Calculate spectra
      function computeWelch(obj)
         obj.dirty = false;
         % reshape signal so that each column contains an epoch
         data = reshape(obj.EEG(1:obj.samples), obj.spe, obj.NumEpochs);
         % compute the power density estimates
         obj.pxx = pwelch(data, obj.win, obj.spk*obj.Kover, obj.spk, obj.SRate);
         % compute max and min pwr for the frequency region of interest
         t = obj.pxx(obj.hz_rng, :);
         obj.MaxPwr = max(t(:));
         obj.MinPwr = min(t(:));
      end
      
      function update_parameters(obj)
         % spectra will have to be recomputed after this
         obj.dirty = true;
         % the number of samples in a single kernel
         obj.spk       = obj.Ksize * obj.SRate;
         % the kernel window
         p = str2func(validatewindow(obj.wType));
         obj.win = p(obj.spk);
         % setting the number of samples per epoch and
         % the number of available epochs in the data
         if obj.Epoch==0
            % then the entire EEG is the epoch
            obj.spe = length(obj.EEG);
            obj.NumEpochs = 1;
         else
            % epoch duration times Hz
            obj.spe = obj.Epoch * obj.SRate;
            obj.NumEpochs = floor(length(obj.EEG)/obj.spe);
         end
         % the number of total samples after flooring
         obj.samples   = obj.NumEpochs * obj.spe;
         % frequency range; resolution is the inverse of kernel size;
         % maximum frequency is always half of the sampling rate
         obj.freqs     = 0:(1/obj.Ksize):obj.SRate/2;
         % frequency-of-interest indexes
         obj.hz_rng = find(obj.freqs >= obj.HzMin & obj.freqs <= obj.HzMax);
         % frequency-of-interest range
         obj.HzRange = obj.freqs(obj.hz_rng);
      end
   end   
end

function vs = validatewindow(type)
   validwins = {
      'hann'
      'hamming'
      'blackman'
      'blackmanharris'
      'kaiser'
      };
   vs = validatestring(type, validwins);
end

% function value = getfieldi(S,field, default)
%    names   = fieldnames(S);
%    isField = strcmpi(field,names);
   
%    if any(isField)
%       value = S.(names{isField});
%    else
%       value = default;
%    end
% end

%          if nargin==2 % just EEG and params file
%             pf = varargin{1};
%             varargin={};
%          else % in any other case
%             % will try to ready the default params file
%             pf = 'params.yml';
%          end
%
%          % does a parameters file exist?
%          s = which(pf);
%          if isempty(s)
%             warning('Parameter file not found, using defaults')
%             y = struct;
%          else
%             disp(['Using parameter file: ' s])
%             y = readparams(pf, 'eepower');
%          end

% p.addParameter('SRate', NaN, @isnumscalar)
% p.addParameter('Epoch', NaN, @isnumscalar)
% p.addParameter('Ksize', NaN, @isnumscalar)
% p.addParameter('Kover', NaN, @isnumscalar)
% p.addParameter('HzMin', NaN, @isnumscalar)
% p.addParameter('HzMax', NaN, @isnumscalar)
% p.addParameter('Delta', NaN, @isnumvector)
% p.addParameter('Theta', NaN, @isnumvector)
% p.addParameter('Alpha', NaN, @isnumvector)
% p.addParameter('Beta',  NaN, @isnumvector)
% p.addParameter('wType', NaN, @ishstring)
% p.addParameter('PFile', NaN, @ishstring)

% v = getfieldi(y, 'srate', 400);
% v = getfieldi(y, 'epoch', 10);
% v = getfieldi(y, 'ksize', 2);
% v = getfieldi(y, 'kover', .5);
% v = getfieldi(y, 'hzmin', 0);
% v = getfieldi(y, 'hzmax', 30);
% v = getfieldi(y, 'delta', [0.5, 4.0]);
% v = getfieldi(y, 'theta', [4.5, 7.5]);
% v = getfieldi(y, 'alpha', [8.0, 15.0]);
% v = getfieldi(y, 'beta', [15.5, 30.0]);
% v = getfieldi(y, 'wtype', 'hann');

% obj.Epoch = p.Results.Epoch;
% obj.Ksize = p.Results.Ksize;
% obj.Kover = p.Results.Kover;
% obj.HzMin = p.Results.HzMin;
% obj.HzMax = p.Results.HzMax;
% obj.wType = p.Results.wType;
% obj.Delta = p.Results.Delta;
% obj.Theta = p.Results.Theta;
% obj.Alpha = p.Results.Alpha;
% obj.Beta  = p.Results.Beta;
