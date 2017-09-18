%% testing the ERPool class

clear
% start with a sample data file provided by Andrea R, output by LabChart
% change path according to your setup!
load ~/data/erp/E7_25enero2015_p32080.mat

% this is a two-channel recording; let's load the first signal
first_sample = datastart(1);
last_sample  = dataend(1);
eeg = data(first_sample:last_sample);

% events are identified by data sample index, rather than time.
% NB: the (70*4) correction fixes a problem with this dataset.
idx = com(:, 3)' - (70*4);
code = com(:, 5)';

% the analysis is performed by "objects of the ERPool class"
% in practice, do the following:
ep = ERPool(eeg, idx, code);
ep.plot
