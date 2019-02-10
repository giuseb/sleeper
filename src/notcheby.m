function ne = notcheby(eeg, fn)
   % EEG = NOTCHEBY(EEG) applies a 50 Hz notch and a Chebyshev bandpass
   % filter to an EEG signal. All default parameters are written in the
   % YAML file src/notcheby.yml. To override such defaults, copy the
   % content of notcheby.yml into your own file, edit and use it instead:
   % EEG = NOTCHEBY(EEG, 'my_params.yml')
   
   if nargin < 2
      fn = 'notcheby.yml';
   end
   y = readparams(fn, 'notcheby');
   
   disp('==================================')
   disp('FILTERING PARAMETERS')
   for j=1:length(x{1})
      k = x{1}{j};
      v = x{2}(j);
      y.(k) = v;
      disp([k ': ' num2str(v)])
   end
   disp('==================================')
   
   % notch filter design
   Wo    = y.NotchHz/(y.SRate/2);
   BW    = Wo/y.QFactor;
   [b,a] = iirnotch(Wo,BW);
   
   % CHEBY2 filter design
   h  = fdesign.bandpass(y.Fstop1, ...
                         y.Fpass1, ...
                         y.Fpass2, ...
                         y.Fstop2, ...
                         y.Astop1, ...
                         y.Apass,  ...
                         y.Astop2, ...
                         y.SRate);
   ch = design(h, 'cheby2', 'MatchExactly', 'passband');

   % filter signal
   no = filter(b,a,eeg);
   ne = filter(ch, no);
   disp('Done.')
end