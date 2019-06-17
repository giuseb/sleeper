% testing the EEGenie class using script-based unit tests
% see Matlab documentation for more on how to write and execute tests

% sample hypnogram and markers
t = load('test/test_hypnogram.mat');
hyp = t.hypnogram;
mrk = t.markers;
% sample signals
t= load('test/test_sleeper.mat');
eeg = t.eeg;
emg = t.emg;

% defaults
def_states = {'REM' 'NREM' 'Wake'}';
def_epoch  = 10;

% the default test marker structure
st(1).start_pos  = 1234;
st(1).finish_pos = 1901;
st(1).tag = 'SWD';

st(2).start_pos  = 4022;
st(2).finish_pos = 6234;
st(2).tag = 'SWD';

st(3).start_pos  = 7182;
st(3).finish_pos = 8302;
st(3).tag = 'Art';

st(4).start_pos  = 9100;
st(4).finish_pos = 9900;
st(4).tag = 'Art';

st(5).start_pos  = 13400;
st(5).finish_pos = 15985;
st(5).tag = 'SWD';

%% Test-01: make sure an object is created, with default values
t = EEGenie;
assert(isa(t, 'EEGenie'))
assert(isequal(t.States, def_states))
assert(t.Epoch == def_epoch)

%% Test-02: different parameters can be defined at object creation
stt =  {'uno', 'due'};
ep = 4;
t = EEGenie('hyp', hyp, 'states', stt, 'epoch', ep);
assert(isequal(t.States, stt));
assert(t.Epoch == ep)

%% Test-03: epoch, seconds, minutes
e1 = sum(hyp==1);
e2 = sum(hyp==2);
e3 = sum(hyp==3);

t = EEGenie('hyp', hyp);
assert(isequal(t.state_epoch_counts, [e1, e2, e3]'))

ep = [def_epoch*e1; def_epoch*e2; def_epoch*e3];
assert(isequal(t.state_total_durations, ep))

%% Test-05: find transitions in a short, dummy hypnogram
hy = [1 1 2 3 3 2 3 1 1 2 1 3 1];
t = EEGenie('hyp', hy);
assert(isequal(t.state_transitions.Count, [2 1 2 1 2 1]'))

%% Test-06: getting epoch counts by state and block
hy = [1 2 3 1 2 3 1 1 1 1 1 1 2 3 2 3 2 3];
% the 18 epochs will be analyzed in groups of 3
t = EEGenie('hyp', hy, 'block', 3);
out = [
   1 1 3 3 0 0
   1 1 0 0 2 1
   1 1 0 0 1 2
];
assert(isequal(t.state_epoch_counts, out))

%% Test-07: fractions of time, by state and block
hy = [1 1 1 1  1 1 2 2  1 2 3 4];
out = [
   1  .5  .25
   0  .5  .25
   0  0   .25
   0  0   .25
];
t = EEGenie('hyp', hy, 'block', 4, 'states', {'a' 'b' 'c' 'd'});
assert(isequal(t.state_proportions, out))

%% Test-08: getting the number of episodes and the durations
hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
out = [
   2 2 0 0
   0 2 1 1
   1 0 1 1
];
t = EEGenie('hyp', hy, 'block', 5);
assert(isequal(t.state_episode_counts, out));

dur = {
   [30;10], [10;20], [], []
        [], [10;20], 30, 10
        10,      [], 20, 30
};
assert(isequal(t.state_episode_durations, dur));

means = [
   20  15 NaN NaN
  NaN  15  30  10
   10 NaN  20  30
];
assert(isequaln(t.state_episode_duration_mean, means));

%% Test-09: getting all start and end times (assuming 400Hz)
me = EEGenie('mark', st);
me.TOI = false;
ss = me.ev_ini_times;
assert(isequal([1234/400 4022/400 7182/400 9100/400 13400/400], ss));
se = me.ev_fin_times;
assert(isequal([1901/400 6234/400 8302/400 9900/400 15985/400], se));

%% Test-10: getting times for SWD tags (assuming 400Hz)
me = EEGenie('mark', st);
ss = me.ev_ini_times;
assert(isequal([1234/400 4022/400 13400/400], ss));
se = me.ev_fin_times;
assert(isequal([1901/400 6234/400 15985/400], se));

%% Test-11: getting included tags, alphabetically ordered
me = EEGenie('mark', st);
assert(isequal(me.Tags, {'Art' 'SWD'}))

%% Test-12: getting total number of events by tag
% me = EEGenie('mark', st);
% assert(isequal(me.totals, [2 3]))

%% Test-13: replacing tags
me = EEGenie('mark', st);
me.replacetag('SWD', 'xxx');
assert(isequal(me.Tags, {'Art' 'xxx'}))

%% Test-14: counting events per epoch
me = EEGenie('mark', st);
mm = me.events_per_epoch;
assert(isequal(mm, [1 1 0 1]))
me.TOI = false;
mm = me.events_per_epoch;
assert(isequal(mm, [1 2 1 1]))

%% Test-15: adding an EEG signal and markers
me = EEGenie('EEG', eeg, 'mark', mrk);
neg = me.EEG;
assert(isequal(neg, eeg))
mar = me.Markers;
assert(isequal(mrk, mar))

%% Test-16: computing event spectra
me = EEGenie('EEG', eeg, 'mark', mrk);
s = me.spectra;
disp('spectra computed')

%% Test-17: computing event durations, mean, std
me = EEGenie('mark', mrk);
t = [1134,1369,1214,998,219,477]/400;
assert(isequal(me.event_durations, t))
assert(isequal(me.event_duration_mean, mean(t)))
assert(isequal(me.event_duration_std, std(t)))

%% Test-18: computing the binned frequency of events
hz = 400;
% rng(0, 'twister') % always the same random numbers
maxlen = 5000000; % over 3 hrs at 400Hz
r = maxlen*rand(1000,1); % random start_positions
c = histcounts(r, 'binw', hz*3600); % compute distribution
tm = struct('start_pos', num2cell(r), 'tag', {'SWD'}, 'finish_pos', num2cell(r+3*hz));

me = EEGenie('mar', tm, 'sra', hz, 'bin', 1, 'toi', 'SWD');
assert(isequal(me.event_total_count, c))

me.Bin = 0;
assert(isequal(me.event_total_count, sum(c)))

%% Test-19: assigning state to events
clear t
t.start_pos = 12399;
t.finish_pos = 12900;
t.tag = 'SWD';
t.prev = '';
t.next = '';

hy



me = EEGenie('mark', [mrk t], 'hyp', hyp, 'srate', 400, 'minpad', 1);
[st, warn] = me.event_states


