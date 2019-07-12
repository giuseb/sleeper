classdef EEGenieTest < matlab.unittest.TestCase
   properties
      eeg
      emg
      hyp
      epo
      mrk
      mrk2
   end
   
   methods (TestClassSetup)
      function getSampleData(TC)
         % sample signals
         t= load('test/test_sleeper.mat');
         TC.eeg = t.eeg;
         TC.emg = t.emg;
         
         % hypnogram and markers
         t = load('test/test_hypnogram.mat');
         TC.hyp = t.hypnogram;
         TC.mrk = t.markers;
         TC.epo = [sum(TC.hyp==1); sum(TC.hyp==2); sum(TC.hyp==3)];
         
         % another test marker structure
         s = {1234 4022 7182 9100 13400};
         f = {1901 6234 8302 9900 15985};
         t = {'SWD' 'SWD' 'Art' 'Art' 'SWD'};
         TC.mrk2 = struct('start_pos', s, 'finish_pos', f, 'tag', t);
      end
   end
   
   methods (Test)
      function testObjectCreation(TC)
         % Make sure an object is created, with default values
         t = EEGenie;
         TC.verifyTrue(isa(t, 'EEGenie'));
      end
      
      function testCustomParameters(TC)
         % Different parameters can be defined at object creation
         stt =  {'uno', 'due'};
         ep = 4;
         t = EEGenie('states', stt, 'epoch', ep);
         TC.verifyEqual(t.States, stt);
         TC.verifyEqual(t.Epoch, ep)
      end
      
      function testStateEpochCount(TC)
         % Count epochs by state
         t = EEGenie('hyp', TC.hyp, 'epo', 10);
         TC.verifyEqual(t.state_epoch_counts, TC.epo)
      end
      
      function testStateEpochCountBlocked(TC)
         % Count epochs by state, in blocks
         hy = [1 2 3 1 2 3 1 1 1 1 1 1 2 3 2 3 2 3];
         out = [
            1 1 3 3 0 0
            1 1 0 0 2 1
            1 1 0 0 1 2
            ];
         t = EEGenie('hyp', hy, 'block', 3);
         TC.verifyEqual(t.state_epoch_counts, out)
      end
      
      function testStateDuration(TC)
         % Count total duration of states
         t = EEGenie('hyp', TC.hyp);
         TC.verifyEqual(t.state_total_durations, TC.epo*10)
      end
      
      function testFindTransitions(TC)
         % Count all state transitions
         hy = [1 1 2 3 3 2 3 1 1 2 1 3 1];
         ac = [2 1 2 1 2 1]';
         t = EEGenie('hyp', hy);
         TC.verifyEqual(t.state_transitions.Count, ac)
      end
      
      function testStateFractions(TC)
         % Compute the fractions of time spent in each state (blocked)
         hy = [1 1 1 1  1 1 2 2  1 2 3 4];
         out = [
            1  .5  .25
            0  .5  .25
            0   0  .25
            0   0  .25
            ];
         t = EEGenie('hyp', hy, 'block', 4, 'states', {'a' 'b' 'c' 'd'});
         TC.verifyEqual(t.state_proportions, out)
      end
      
      function testStateEpisodeCounts(TC)
         % Count the number of state episodes (blocked)
         hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
         out = [
            2 2 0 0
            0 2 1 1
            1 0 1 1
            ];
         t = EEGenie('hyp', hy, 'block', 5);
         TC.verifyEqual(t.state_episode_counts, out)
      end
      
      function testStateEpisodeDuration(TC)
         % Compute duration of each state episode
         hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
         dur = {
            [30;10], [10;20], [], []
            [], [10;20], 30, 10
            10,      [], 20, 30
            };
         t = EEGenie('hyp', hy, 'block', 5);
         TC.verifyEqual(t.state_episode_durations, dur)
      end
      
      function testStateEpisodeMeanDuration(TC)
         % Mean state episode durations
         hy = [1 1 1 3 1   2 1 2 2 1   1 3 3 2 2   2 3 3 3 2];
         means = [
            20  15 NaN NaN
            NaN  15  30  10
            10 NaN  20  30
            ];
         t = EEGenie('hyp', hy, 'blo', 5);
         TC.verifyEqual(t.state_episode_duration_mean, means)
      end
      
      function testAllEventTimes(TC)
         t = EEGenie('mark', TC.mrk2);
         t.TOI = false;
         ss = t.event_ini_times;
         TC.verifyEqual([1234/400 4022/400 7182/400 9100/400 13400/400], ss)
         se = t.event_fin_times;
         TC.verifyEqual([1901/400 6234/400 8302/400 9900/400 15985/400], se)
      end
      
      function testEventTimes(TC)
         t = EEGenie('mark', TC.mrk2);
         ss = t.event_ini_times;
         TC.verifyEqual([1234/400 4022/400 13400/400], ss)
         se = t.event_fin_times;
         TC.verifyEqual([1901/400 6234/400 15985/400], se)
      end
      
      function testTagList(TC)
         t = EEGenie('mark', TC.mrk2);
         TC.verifyEqual(t.Tags, {'Art' 'SWD'})
      end
      
      function testTagReplacement(TC)
         % Replace tags
         t = EEGenie('mark', TC.mrk2);
         t.replacetag('SWD', 'xxx');
         TC.verifyEqual(t.Tags, {'Art' 'xxx'})
      end
      
      function testEventsPerEpoch(TC)
         t = EEGenie('mark', TC.mrk2);
         mm = t.events_per_epoch;
         TC.verifyEqual(mm, [1 1 0 1])
         t.TOI = false;
         mm = t.events_per_epoch;
         TC.verifyEqual(mm, [1 2 1 1])
      end
      
      function testAddStuffToObject(TC)
         t = EEGenie('EEG', TC.eeg, 'mark', TC.mrk);
         TC.verifyEqual(t.EEG, TC.eeg)
         TC.verifyEqual(t.Markers, TC.mrk)         
      end
      
      function testEventDescription(TC)
         t = EEGenie('mark', TC.mrk);
         tm = [1134,1369,1214,998,219,477]/400;
         TC.verifyEqual(t.event_durations, tm)
         TC.verifyEqual(t.event_duration_mean, mean(tm))
         TC.verifyEqual(t.event_duration_std, std(tm))
      end
      
      function testEventFrequency(TC)
         hz = 400;
         maxlen = 5000000; % over 3 hrs at 400Hz
         r = maxlen*rand(1000,1); % random start_positions
         c = histcounts(r, 'binw', hz*3600); % compute distribution
         tm = struct('start_pos', num2cell(r), 'tag', {'SWD'}, 'finish_pos', num2cell(r+3*hz));
         t = EEGenie('mar', tm, 'sra', hz, 'bin', 1, 'toi', 'SWD');
         TC.verifyEqual(t.event_total_count, c)
         t.Bin = 0;
         TC.verifyEqual(t.event_total_count, sum(c))
      end
      
      function testStateToEventDT(TC)
         
      end
      
      function testAssignStateToEvents(TC)
         m = TC.mrk;
         m(end+1).start_pos = 12399;
         m(end).finish_pos = 12900;
         m(end).tag = 'SWD';
         m(end).prev = '';
         m(end).next = '';
         t = EEGenie('mark', m, 'hyp', TC.hyp, 'SRate', 400, 'minpad', 1);
         fprintf('\nA warning is expected here!\n')
         [st, warn] = t.event_states;
         TC.verifyEqual(st, [3 2 3 3 2 3 1]');
         TC.verifyEqual(warn, 7);
      end
      
      function testSpectralComputation(TC)
         % Computing event spectra
         t = EEGenie('EEG', TC.eeg, 'mark', TC.mrk);
         t.spectra;
         fprintf('\nspectra computed, no assertions\n')
      end
      
      function testNotcheby(TC)
         t = EEGenie('EEG', TC.eeg);
         t.notcheby
      end
   end
end