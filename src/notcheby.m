function ne = notcheby(eeg, fn)
   % EEG = NOTCHEBY(EEG) applies a 50 Hz notch and a Chebyshev bandpass
   % filter to an EEG signal. All default parameters are written in the
   % YAML file src/notcheby.yml. To override such defaults, copy the
   % content of notcheby.yml into your own file, edit and use it instead:
   % EEG = NOTCHEBY(EEG, 'my_params.yml')
   
   % first read the defaults
   y = readparams('notcheby.yml', 'notcheby');
   if nargin > 1
      % if a different params file is passed, read it 
      p2 = readparams(fn, 'notcheby');
      % and override the default values
      for f = fieldnames(p2)'
         y.(f) = p2.(f);
      end
   end
   
   % these filters require the Signal Processing Toolbox
   %   
   % notch filter design
   n = designfilt('bandstopiir', ...
      'FilterOrder',y.NotchOrder, ...
      'HalfPowerFrequency1',y.Notch1, ...
      'HalfPowerFrequency2',y.Notch2, ...
      'DesignMethod',y.NotchMethod, ...
      'SampleRate',y.SRate);
            
   %
   %    Wo    = y.NotchHz/(y.SRate/2);
   %    BW    = Wo/y.NotchQ;
   %    [b,a] = iirnotch(Wo,BW);
   
   % CHEBY2 filter design
   c = designfilt('bandpassiir', ...
      'FilterOrder', y.BandOrder, ...
      '
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