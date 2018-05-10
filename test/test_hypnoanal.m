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

assert(isequal(ha.epochs, [e1, e2, e3]'));
ep = [def_epoch*e1; def_epoch*e2; def_epoch*e3];
assert(isequal(ha.seconds, ep))
assert(isequal(ha.minutes, ep/60))

%% Test-05: find transitions in a short, dummy hypnogram
hy = [1 1 2 3 3 2 3 1 1 NaN 1 3 1];
t = HypnoAnal(hy);
assert(isequal(t.transitions.Count, [1 0 1 2 2 1]'))

%% Test-06: getting epoch counts by state and block
hy = [1 2 3 1 2 3 1 1 1 1 1 1 2 3 2 3 2 3];
% the 18 epochs will be analyzed in groups of 3
t = HypnoAnal(hy, 'block', 3);
out = [
     1     1     3     3     0     0
     1     1     0     0     2     1
     1     1     0     0     1     2
];
assert(isequal(t.epochs, out))