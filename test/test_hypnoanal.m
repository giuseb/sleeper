% testing the HypnoAnal class using script-based unit tests
% see Matlab documentation for more on how to write and execute tests

% the default test hypnogram
load test/test_hypnogram.mat
ha = HypnoAnal(hypnogram);
def_states = {'REM' 'NREM' 'Wake'};
def_epoch  = 10;

%% Test-01: make sure an object is created
assert(isa(ha, 'HypnoAnal'))

%% Test-02: the object contains default values
assert(isequal(ha.states, def_states))
assert(ha.epoch == def_epoch)

%% Test-03: different parameters can be defined at object creation
st =  {'uno', 'due'};
ep = 4;
t = HypnoAnal(hypnogram, 'states', st, 'epoch', ep);
assert(isequal(t.states, st));
assert(t.epoch == ep)

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
% t = HypnoAnal(hy);
% assert(isequal(t.transitions.Count, [1 0 1 2 2 1]'))

%% Test-06: getting epoch counts by state and block
hy = [1 2 3 1 2 3 1 1 1 1 1 1 2 3 2 3 2 3];
% the 18 epochs will be analyzed in groups of 3
t = HypnoAnal(hy, 'block', 3);
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
t = HypnoAnal(hy, 'block', 4, 'states', {'a' 'b' 'c' 'd'});
assert(isequal(t.fractions, out))

%% Test-08: getting the number of episodes and the durations
hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
out = [
   2 2 0 0
   0 2 1 1
   1 0 1 1
];
t = HypnoAnal(hy, 'block', 5);
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

%% Test-09: playing with markers
hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];

st(1).start_pos  = 1234;
st(1).finish_pos = 1901;
st(1).tag = 'SWD';

st(2).start_pos  = 4022;
st(2).finish_pos = 6234;
st(2).tag = 'SWD';

st(3).start_pos  = 9100;
st(3).finish_pos = 9900;
st(3).tag = 'Art';

t = HypnoAnal(hy, 'markers', st, 'block', 5);
x = t.mark_counts;
assert(isequal(x, [1 1 0 0 0   0 0 0 0 0   0 0 0 0 0   0 0 0 0 0]));
