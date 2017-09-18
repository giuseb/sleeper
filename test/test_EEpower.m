%% testing the EEpower class, for the analysis of power spectra in EEG
es = load('test_EEpower');
eep = EEpower(es.eeg,500)  %#ok<NOPTS>
assert(isequal(eep.NumEpochs, 360))
assert(isequal(eep.SRate, 500))
assert(isequal(eep.Ksize, 2))
assert(isequal(eep.HzMin, 0))
assert(isequal(eep.HzMax, 30))
assert(isequal(eep.spectra, es.spectra))

%% quickly test a made-up signal
pars = [
   10, 4;
   16, 3;
   50, 1;
   235, .5
   ];

s1 = signalgen(60, 500, pars, 20);
subplot(1,2,1)
plot(s1(1:1000))
eep = EEpower(s1,500);
x = eep.spectra(1);
subplot(1,2,2)
plot(eep.HzRange, x)
