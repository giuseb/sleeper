function rv = notchband(eeg, fn)
   % EEG = NOTCHBAND(EEG) applies a notch and a bandpass filter to an EEG
   % signal. All default parameters are written in the YAML file
   % src/notchband.yml. To override such defaults, copy the content of
   % notchband.yml into your own file, edit and use it instead:
   %
   % EEG = NOTCHBAND(EEG, 'my_params.yml')
   
   % first read the defaults
   y = readparams('notcheband.yml', 'notcheband');
   if nargin > 1
      % if a different params file is passed, read it
      p2 = readparams(fn, 'notcheband');
      % and override the default values
      for f = fieldnames(p2)'
         y.(f) = p2.(f);
      end
   end
   
   % these filters require the Signal Processing Toolbox
   %
   % notch filter design, this might change, let's see...
   n = designfilt('bandstopiir', ...
      'DesignMethod', 'butter', ...
      'SampleRate',           y.SRate, ...
      'FilterOrder',          y.NotchOrder, ...
      'HalfPowerFrequency1',  y.Notch1, ...
      'HalfPowerFrequency2',  y.Notch2);
   
   % CHEBY2 filter design, might change as well   
   b = designfilt('bandpassiir', ...
      'DesignMethod', 'cheby2', ...
      'SampleRate',           y.SRate, ...
      'StopbandFrequency1',   y.BandStop1, ...
      'PassbandFrequency1',   y.BandPass1, ...
      'PassbandFrequency2',   y.BandPass2, ...
      'StopbandFrequency2',   y.BandStop2, ...
      'StopbandAttenuation1', y.BandAtten1, ...
      'StopbandAttenuation2', y.BandAtten2);
   
   % filter signal
   no = filter(n, eeg);
   rv = filter(b, no);
   disp('Done.')
end