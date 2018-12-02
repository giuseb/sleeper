% testing the EEGenie class using script-based unit tests
% see Matlab documentation for more on how to write and execute tests

% the default test hypnogram
load test/test_hypnogram.mat
ha = EEGenie('hyp', hypnogram);
def_states = {'REM' 'NREM' 'Wake'};
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

%% Test-01: make sure an object is created
assert(isa(ha, 'EEGenie'))

%% Test-02: the object contains default values
assert(isequal(ha.States, def_states))
assert(ha.Epoch == def_epoch)

%% Test-03: different parameters can be defined at object creation
stt =  {'uno', 'due'};
ep = 4;
t = EEGenie('hyp', hypnogram, 'states', stt, 'epoch', ep);
assert(isequal(t.States, stt));
assert(t.Epoch == ep)

%% Test-04: epoch, seconds, minutes
e1 = sum(hypnogram==1);
e2 = sum(hypnogram==2);
e3 = sum(hypnogram==3);

assert(isequal(ha.epochs, [e1, e2, e3]'))
ep = [def_epoch*e1; def_epoch*e2; def_epoch*e3];
assert(isequal(ha.seconds, ep))
assert(isequal(ha.minutes, ep/60))

%% Test-05: find transitions in a short, dummy hypnogram
% hy = [1 1 2 3 3 2 3 1 1 2 1 3 1];
% t = EEGenie(hy);
% assert(isequal(t.transitions.Count, [1 0 1 2 2 1]'))

%% Test-06: getting epoch counts by state and block
hy = [1 2 3 1 2 3 1 1 1 1 1 1 2 3 2 3 2 3];
% the 18 epochs will be analyzed in groups of 3
t = EEGenie('hyp', hy, 'block', 3);
out = [
   1 1 3 3 0 0
   1 1 0 0 2 1
   1 1 0 0 1 2
];
assert(isequal(t.epochs, out))

%% Test-07: fractions of time, by state and block
hy = [1 1 1 1  1 1 2 2  1 2 3 4];
out = [
   1  .5  .25
   0  .5  .25
   0  0   .25
   0  0   .25
];
t = EEGenie('hyp', hy, 'block', 4, 'states', {'a' 'b' 'c' 'd'});
assert(isequal(t.fractions, out))

%% Test-08: getting the number of episodes and the durations
hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
out = [
   2 2 0 0
   0 2 1 1
   1 0 1 1
];
t = EEGenie('hyp', hy, 'block', 5);
assert(isequal(t.episodes, out));

dur = {
   [30;10], [10;20], [], []
        [], [10;20], 30, 10
        10,      [], 20, 30
};
assert(isequal(t.durations, dur));

means = [
   20  15 NaN NaN
  NaN  15  30  10
   10 NaN  20  30
];
assert(isequaln(t.mean_durations, means));

%% Test-09: getting all start and end times (assuming 400Hz)
me = EEGenie('mark', st);
me.TOI = false;
ss = me.start_times;
assert(isequal([1234/400 4022/400 7182/400 9100/400 13400/400], ss));
se = me.end_times;
assert(isequal([1901/400 6234/400 8302/400 9900/400 15985/400], se));

%% Test-10: getting times for SWD tags (assuming 400Hz)
me = EEGenie('mark', st);
ss = me.start_times;
assert(isequal([1234/400 4022/400 13400/400], ss));
se = me.end_times;
assert(isequal([1901/400 6234/400 15985/400], se));

%% Test-11: getting included tags, alphabetically ordered
me = EEGenie('mark', st);
assert(isequal(me.Tags, {'Art' 'SWD'}))

%% Test-12: getting total number of events by tag
me = EEGenie('mark', st);
assert(isequal(me.totals, [2 3]))

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