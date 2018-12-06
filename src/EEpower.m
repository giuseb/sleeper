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
   %   vector, sampled at SRate Hertz.
   %
   %   eep = EEpower(EEG, SRate, 'name', value, ...)
   %
   %   The following name-value pairs can be added as optional arguments:
   %   Epoch:  time over which spectra are computed (10 sec by default)
   %   Ksize:  length of the moving kernel (2 sec by default)
   %   Kovrl:  kernel overlap fraction (default is 0.5)
   %   HzMin:  the minimum frequency of interest (0 Hz by default)
   %   HzMax:  the maximum frequency of interest (30 Hz by default)
   %   wType:  the window type ('hanning' by default); choose between:
   %           hann, hamming, blackman, blackmanharris, kaiser
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
      SRate     % signal sampling rate
      NumEpochs % the number of epochs in the data file
      MaxPwr    % maximum power computed over the entire signal
      MinPwr    % minimum power computed over the entire signal
      MaxLogPwr % maximum log power computed over the entire signal
      MinLogPwr % minimum log power computed over the entire signal
      HzRange   % the frequencies of interest
   end
   properties (SetObservable)
      Epoch     % scoring epoch in seconds  (default: 10)      
      Ksize     % kernel size in seconds    (default: 2)
      Kovrl     % kernel overlap fraction   (default: 0.5)
      HzMin     % minimum plotted frequency (default: 0)
      HzMax     % maximum plotted frequency (default: 30)
      wType     % the window type (default: 'hanning')
   end
   properties
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
      function obj = EEpower(eeg, SRate, varargin)
         % type >> help EEpower for help on how to use the EEpower class
         % constructor
         p = inputParser;
         p.addRequired( 'EEG',       @isnumvector)
         p.addRequired( 'SRate',     @isnumscalar)
         p.addParameter('Epoch', 10, @isnumscalar)
         p.addParameter('Ksize',  2, @isnumscalar)
         p.addParameter('Kovrl', .5, @isnumscalar)
         p.addParameter('HzMin',  0, @isnumscalar)
         p.addParameter('HzMax', 30, @isnumscalar)
         p.addParameter('Delta', [ 0.5   4.0], @isnumvector)
         p.addParameter('Theta', [ 4.5,  7.5], @isnumvector)
         p.addParameter('Alpha', [ 8.0, 15.0], @isnumvector)
         p.addParameter('Beta',  [15.5, 30.0], @isnumvector)
         p.addParameter('wType', 'hann')
         p.parse(eeg, SRate, varargin{:})
         
         obj.EEG   = p.Results.EEG;
         obj.SRate = p.Results.SRate;
         obj.Epoch = p.Results.Epoch;
         obj.Ksize = p.Results.Ksize;
         obj.Kovrl = p.Results.Kovrl;
         obj.HzMin = p.Results.HzMin;
         obj.HzMax = p.Results.HzMax;
         obj.wType = p.Results.wType;
         obj.Delta = p.Results.Delta;
         obj.Theta = p.Results.Theta;
         obj.Alpha = p.Results.Alpha;
         obj.Beta  = p.Results.Beta;
         
         lprops = { 'Epoch' 'Ksize' 'HzMin' 'HzMax' 'wType'};
         obj.addlistener(lprops, 'PostSet', @obj.HandleProps);
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
         obj.pxx = pwelch(data, obj.win, obj.spk*obj.Kovrl, obj.spk, obj.SRate);
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
         obj.win       = p(obj.spk);
         % the number of samples in a single epoch
         obj.spe       = obj.Epoch * obj.SRate;
         % the number of available epochs in the data file
         obj.NumEpochs = floor(length(obj.EEG)/obj.spe);
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

