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

%% Test-01: construct
me = MarkMan(st);
assert(isa(me, 'MarkMan'))

%% Test-02: get all start and end stamps
me = MarkMan(st);
ss = me.start_times;
assert(isequal([1234/400 4022/400 7182/400 9100/400 13400/400], ss));
se = me.end_times;
assert(isequal([1901/400 6234/400 8302/400 9900/400 15985/400], se));

%% Test-03: get stamps for SWD tags
me = MarkMan(st);
ss = me.start_times('SWD');
assert(isequal([1234/400 4022/400 13400/400], ss));
se = me.end_times('SWD');
assert(isequal([1901/400 6234/400 15985/400], se));

%% Test-04: get all tags
me = MarkMan(st);
assert(isequal(me.tags, {'Art' 'SWD'}))

%% Test-05: get total number of events by tag
me = MarkMan(st);
assert(isequal(me.totals, [2 3]))

%% Test-06: fix tags
me = MarkMan(st);
me.tagfix('SWD', 'xxx');
assert(isequal(me.tags, {'Art' 'xxx'}))
%% Test-07: counts of events per epoch
me = MarkMan(st);
mm = me.events_per_epoch;
assert(isequal(mm, [1 2 1 1]))
mm = me.events_per_epoch('SWD');
assert(isequal(mm, [1 1 0 1]))
