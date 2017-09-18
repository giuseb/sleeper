function edf2sigmat(edfname, subjects, channels, outdir)
   % EDF2SIGMAT(EDFNAME, SUBJECTS, CHANNELS, OUTDIR) converts EDF to SigMat
   %
   %     EDFNAME:  a string with the path/name of the EDF source
   %     SUBJECTS: a cell array of strings with the names of the subjects
   %     CHANNELS: a cell array of strings with the channel labels
   %     OUTDIR:   a string with the destination path for SigMats
   %
   % Unlike human clinical EEG studies, experimental electrophysiological
   % recordings are typically run on several subjects at once. Since
   % studies can be very long (i.e. days) the resulting data files can be
   % unmanageable. EDF2SIGMAT splits EDF files into as many SigMat objects
   % as there are subjects in the original recording.
   %
   % EDF2SIGMAT assumes a specific, orderly arrangement of recorded
   % signals, where blocks of consecutive channels come from the same
   % subject. For example, an EDF containing 32 signals, 4 for each of 8
   % subjects, can be parsed using these arguments:
   %
   %     subjects = {'s1' 's2' 's3' 's4' 's5' 's6' 's7' 's8'};
   %     channels = {'EEG1' 'EEG2' 'EEG3' 'EMG'};
   %
   % SigMat files, one for each subject, are created and placed in the
   % specified output directory. The name of the output .MAT file is
   % composed of the recording date and the subject's name.
   %
   % Last modified 2 May 2016
   
   p = inputParser;
   p.addRequired('EDFname',     @ishstring)
   p.addRequired('Subjects',    @iscellstr)
   p.addRequired('Channels',    @iscellstr)
   p.addOptional('OutDir', '.', @ishstring)
   p.parse(edfname, subjects, channels, outdir)
   
   % the counter to keep track of which signal to load next
   signum = 0;
   % instantiating the EDFast
   edf = EDFast(p.Results.EDFname);
   % save the string representation of the recording start datetime
   ds = datestr(edf.RecStart, 'yyyy-mm-dd');
   % for each subject...
   for s = p.Results.Subjects
      subj = s{:};
      % the name of the SigMat output, composed of the two characterizing
      % pieces of information, ie the recording start and the subject name
      ofn = fullfile(p.Results.OutDir, [ds '_' subj]);
      sm = SigMat(ofn, edf.RecStart, subj);
      % ...and for each channel...
      for c = p.Results.Channels
         signum = signum + 1;
         sm.write(c{:}, edf.SigHertz(signum), edf.get_signal(signum));
      end
   end
end

