function [rv, t] = signalgen(seconds, sampling_rate, params, noise)
   % SIGNALGEN   generating simple signals by summing sinusoidal waves
   %
   %     SIGNALGEN(SECONDS, SAMPLING_RATE, PARAMS, NOISE)
   %     generates a SECONDS-long signal at SAMPLING_RATE Hertz, with the
   %     given PARAMS. The latter is a two-column numerical matrix, where
   %     each row defines a sinusoidal wave. The first column is the
   %     periodicity in Hertz, the second is the amplitude.
   %     With a single PARAMS row, the signal is a perfect sinusoid; the
   %     more rows are added, the noisier the signal.
   %     White noise of NOISE amplitude is added, if the argument is
   %     provided.
   %
   %     [SIG, T] = SIGNALGEN(...)  also returns the time array, suitable
   %     for axis labeling in plots.
   %
   % Last modified: 1 Aug 2017
   
   if ~isnumeric(params) || size(params,2) ~= 2
      error('PARAMS should be a two-column numerical matrix')
   end
   % the number of overlapping signals
   harmonics = size(params,1);
   % the temporal line
   t = 0:1/sampling_rate:seconds;
   t(end)=[];
   % the total number of samples
   ns = length(t);
   % laying out params
   wave_hz   = repmat(params(:,1), 1, ns);
   amplitude = repmat(params(:,2), 1, ns);
   % computing the signal
   tx = repmat(t, harmonics,1);
   rv = sum(amplitude .* sin(2*pi*wave_hz.*tx), 1);
   if nargin==4
      rv = rv + randn(size(rv)) * noise;
   end
end