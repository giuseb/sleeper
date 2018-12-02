%% Automatically detect putative SWD events based on spectral properties
%

%%
% Test based on data collected in Marseille on GRIN-2a mice
clear
load ~/data/swd_detection/EEG_HOMO2.mat
sleeper(EEG, 'epoch', 4)

length(EEG)/(3600*400)

%% testing our own A/J JAX data
clear
load test_sleeper.mat




Hz     = 400;  % Sampling Frequency
N      =   4;  % Order
Fstop1 =   7;  % First Stopband Frequency
Fstop2 =  12;  % Second Stopband Frequency
Astop  =  25;  % Stopband Attenuation (dB)

% Construct an FDESIGN object and call its CHEBY2 method.
h  = fdesign.bandpass('N,Fst1,Fst2,Ast', N, Fstop1, Fstop2, Astop, Hz);
Hd = design(h, 'cheby2');

% isolating a fragment containing an SWD
start = 1250 * Hz;
stop  = start + 120 * Hz;

feg = filter(Hd, eeg(start:stop));

plot(feg)
