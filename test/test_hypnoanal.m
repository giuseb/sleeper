clear
load test/test_hypnogram.mat
ha = HypnoAnal(hypnogram);

disp(ha)

disp([hypnogram ha.changes])
