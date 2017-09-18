%% Automatically detect putative SWD events based on spectral properties
%
% Test based on data collected in Marseille on GRIN-2a mice
clear
load ~/data/swd_detection/EEG_HOMO2.mat
sleeper(EEG, 'epoch', 4)

length(EEG)/(3600*400)