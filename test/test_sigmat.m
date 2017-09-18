%% testing the SigMat data file format

% working with a temporary SigMat
tmpFile = [tempname '.mat'];

% create the file but don't use it
SigMat(tmpFile, '2016-04-25 11:23:10', 'topolino');

% load the empty SigMat
sm = SigMat(tmpFile);

% have the header variables been stored?
assert(strcmp(sm.Subject, 'topolino'))
assert(sm.RecStart==datetime('2016-04-25 11:23:10'))
assert(sm.NSignals==0)

% generating and writing fake signals
s1 = signalgen(3600, 500, [8, 10], 23);
sm.write('ts1', 500, s1)
s2 = signalgen(3600, 400, [8, 10], 21);
sm.write('ts2', 400, s2)

% test readout
tmp = sm.read(1);
assert(isequal(tmp, s1));
tmp = sm.read(2);
assert(isequal(tmp, s2));

% test variable size
assert(isequal(sm.length('ts1'), length(s1)))
assert(isequal(sm.length('ts2'), length(s2)))

% test loading variables
x = load(tmpFile);
assert(isequal(x.ts1, s1))
assert(isequal(x.ts2, s2))
assert(isequal(x.labels, {'ts1', 'ts2'}), 'Unequal labels')
assert(isequal(x.hertz, [500 400]));
% clean up
delete(tmpFile)
clear sm s1 s2 tmp x tmpFile



