function varargout = sleeper(varargin)
   % SLEEPER - sleep scoring and seizure detection system
   %      Sleeper is a GUI tool aimed at facilitating vigilance state scoring.
   %      Additionally, it aids the detection of abnormal brain activity.
   %      Sleeper currently supports one EEG, one EMG signal, and one
   %      actigram as data sources.
   %
   %
   %      SLEEPER(EEG) opens the sleeper GUI to display and score the signal
   %      in EEG

   % Last Modified by GUIDE v2.5 01-Jun-2016 14:55:16

   % Begin initialization code - DO NOT EDIT
   gui_Singleton = 1;
   gui_State = struct('gui_Name',       mfilename, ...
      'gui_Singleton',  gui_Singleton, ...
      'gui_OpeningFcn', @sleeper_OpeningFcn, ...
      'gui_OutputFcn',  @sleeper_OutputFcn, ...
      'gui_LayoutFcn',  [] , ...
      'gui_Callback',   []);
   if nargin && ischar(varargin{1})
      gui_State.gui_Callback = str2func(varargin{1});
   end

   if nargout
      [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
   else
      gui_mainfcn(gui_State, varargin{:});
   end
end% End initialization code - DO NOT EDIT

% --- Outputs from this function are returned to the command line.
function varargout = sleeper_OutputFcn(~, ~, h)
   varargout{1} = h.output;
end

% --- Executes just before sleeper is made visible.
function sleeper_OpeningFcn(hObject, ~, h, eeg, varargin)
   %-------------------------------------------------------- Parse input args
   p = inputParser;
   p.addRequired('EEG', @isnumeric)
   p.addOptional('EMG',       [], @isnumeric)
   p.addParameter('SRate',   400, @isintscalar)
   p.addParameter('Epoch',    10, @isintscalar)
   p.addParameter('EpInSeg', 180, @isintscalar)
   p.addParameter('Hypno',    [], @isnumeric)
   p.addParameter('Markers', mrkstr, @isstruct)
   p.addParameter('KLength',   1, @isnumeric)
   p.addParameter('EEGPeak',   0, @ispositivescalar)
   p.addParameter('EMGPeak',   0, @ispositivescalar)
   p.addParameter('MinHz',     0, @isintscalar)
   p.addParameter('MaxHz',    20, @isintscalar)
   p.addParameter('States', {'REM', 'nREM', 'Wake'}, @iscell)
   p.parse(eeg, varargin{:})
   %------------------------------ transfer inputParser Results to the handle
   r = p.Results;
   h.eeg = r.EEG;
   h.emg = r.EMG;
   h.markers = r.Markers;
   h.patches = struct('start', {}, 'finish', {});

   h.cm = length(h.markers); % current marker

   h.sampling_rate = r.SRate;   % in Hz
   h.scoring_epoch = r.Epoch;   % in seconds
   h.kernel_len    = r.KLength; % in seconds
   h.epochs_in_seg = r.EpInSeg; % number of epochs in a segment
   h.hz_min        = r.MinHz;   % only plot spectra above this
   h.hz_max        = r.MaxHz;   % only plot spectra below this
   h.vig_states    = r.States;

   % the eeg & emg charts' initial ylim
   if r.EEGPeak == 0
      h.eeg_peak = max(h.eeg)*1.05;
   else
      h.eeg_peak = r.EEGPeak;
   end
   if r.EMGPeak == 0
      h.emg_peak = max(h.emg)*1.05;
   else
      h.emg_peak = r.EMGPeak;
   end

   %------------------------------------------------------------------- States
   h.k.NORMAL       = 0; % the "normal" state
   h.k.MARK         = 1;
   h.k.MARKING      = 2; % waiting for the end mark
   h.k.THRESHOLDING = 3;
   h.k.ZOOM         = 4;
   h.k.ZOOMING      = 5;
   h.k.ZOOMED       = 6;
   h.k.ZOOMARKING   = 7;
   h.gui_state = h.k.NORMAL;
   %-------------------------------------------------------------> Various
   h.zoom_start = 0;
   h.zoom_end   = 0;
   h.default_event_tag = 'Tag';
   h.marking = false;


   %------------ compute here parameters that cannot be changed while scoring

   % size of epoch in nof samples
   h.epoch_size = h.sampling_rate * h.scoring_epoch;
   % total signal samples after trimming excess
   h.signal_size = length(h.eeg)-rem(length(h.eeg), h.epoch_size);
   % signal duration in seconds, after rounding to whole scoring epochs
   h.signal_len = h.signal_size/h.sampling_rate;
   % number of epochs in the signal
   h.tot_epochs = h.signal_len / h.scoring_epoch;

   %----------- compute here parameters that can be modified during execution
   h = update_parameters(h);

   %-------------------------------------------------------- set up hypnogram
   if isempty(r.Hypno)
      h.score = nan(h.tot_epochs, 1);
   else
      h.score = r.Hypno;
   end

   %----------------------------------------------------- set up GUI controls
   h.txtEpInSeg.String = h.epochs_in_seg;
   h.currSeg.String = 1;
   h.currEpoch.String = 1;
   set(h.lblInfo, 'string', ...
      sprintf('%d Hz, %d-s epoch', h.sampling_rate, h.scoring_epoch))
   % set up signal time slider; the 12-segment increment is based on the
   % assumption that the segment will often last one hour
   set(h.segment, ...
      'Min', 1, ...
      'Max', h.num_segments, ...
      'Value', 1, ...
      'SliderStep', [1/(h.num_segments-1), 12/(h.num_segments-1)]);
   h.lblSegNum.String = sprintf('of %d', h.num_segments);
   h.actiPlot.XTickLabel = '';
   %---------------------------------------------- Setting up the spectrogram
   h.pow = EEpower(h.eeg, ...
      'SRate', h.sampling_rate, ...
      'Epoch', h.scoring_epoch, ...
      'Ksize', h.kernel_len, ...
      'HzMin', h.hz_min, ...
      'HzMax', h.hz_max);

   h.spectrarrow = 0;

   jump_to(h, 1);

   % Choose default command line output for sleeper
   h.output = hObject;
   % Update handles structure
   guidata(hObject, h);
end
%=========================================================================
%==================================================== Capture mouse clicks
%=========================================================================
function hypno_ButtonDownFcn(hObject, eventdata)
   % I do not know why the handles are not passed here!
   h = guidata(hObject);
   set(h.currEpoch, 'string', ceil(x_btn_pos(eventdata)));
   h = draw_epoch(h);
   guidata(hObject, h)
end

function spectra_ButtonDownFcn(hObject, eventdata, h) %#ok<DEFNU>
   set(h.currEpoch, 'string', ceil(x_btn_pos(eventdata)-.5));
   h = draw_epoch(h);
   guidata(hObject, h)
end

function eegPlot_ButtonDownFcn(hObject, eventdata, h) %#ok<DEFNU>
   switch h.gui_state
      case h.k.NORMAL
         beep
      case h.k.MARKING
         if h.marking
            h = finish_normal_marker(h, eventdata);
         else
            h = start_normal_marker(h, eventdata);
         end
      case h.k.THRESHOLDING
         % with thresholding activated, set an EEG threshold
         h = setting_EEG_thr(h, eventdata);
      case h.k.ZOOM
         % we asked to zoom into the EEG, now collecting start point
         h = set_zoom_start(h, eventdata);
      case h.k.ZOOMING
         % zoom start point already taken, now collecting the end point
         h = set_zoom_end(h, eventdata);
      case h.k.ZOOMED
         if h.marking
            h = finish_zoomed_marker(h, eventdata);
         else
            h = start_zoomed_marker(h, eventdata);
         end
   end
   guidata(hObject, h)
end
%=========================================================================
%============================================================== Keypresses
%=========================================================================
function window_WindowKeyPressFcn(hObject, key, h) %#ok<DEFNU>

   switch key.Key
      case 'rightarrow'
         h = next_epoch(h);
      case 'leftarrow'
         h = prev_epoch(h);
      case '1'
         h = set_state(h, 1);
      case '2'
         h = set_state(h, 2);
      case '3'
         h = set_state(h, 3);
      case '4'
         h = set_state(h, 4);
      case '5'
         h = set_state(h, 5);
      case '6'
         h = set_state(h, 6);
      case '7'
         h = set_state(h, 7);
      case '8'
         h = set_state(h, 8);
      case '9'
         h = set_state(h, 9);
      case 'n'
         h = set_state(h, nan);
      case 'z'
         h = toggle_zoom(h);
      case 'm'
         h = toggle_mark(h);
   end
   guidata(hObject, h)
end
%--------------------------------------------------------> Set epoch.gui_state
function h = set_state(h, state)
   if h.marking || h.gui_state ~= h.k.NORMAL || ...
      (state > length(h.vig_states) && ~isnan(state))
      beep
      return
   end
   e = h.epochs_in_seg * (uivalue(h.currSeg) - 1) + uivalue(h.currEpoch);
   h.score(e) = state;
   h = next_epoch(h);
end

%=========================================================================
%=========================================================== Button clicks
%=========================================================================

%-------------------------------------------------------> Save output file
function btnSave_Callback(hObject, ~, h) %#ok<DEFNU>
   t = h.txtHypnoFName.String;
   h.txtHypnoFName.String = 'Saving...';
   hypnogram = h.score; %#ok<NASGU>
   markers = h.markers; %#ok<NASGU>
   save(t, 'hypnogram', 'markers')
   h.txtHypnoFName.String = 'Saved.';
   hObject.BackgroundColor = 'green';
   uiwait(h.window, 1);
   hObject.BackgroundColor = 'white';
   h.txtHypnoFName.String = t;
end
%---------------------------------------------> Setting an event threshold
function btnSetEEGThr_Callback(hObject, ~, h) %#ok<DEFNU>
   highlight_eeg(h, 'thres')
   h.gui_state = h.k.THRESHOLDING;
   guidata(hObject, h)
end
% -----------------------------------------------------> Show Markers list
function btnMarkerList_Callback(~, ~, h) %#ok<DEFNU>
   if h.marking || h.cm==0
      return
   end
   for n = 1:h.cm
      m = h.markers(n);
      [seg, epo] = parsed_eeg_position(h, m.start_pos);
      ts{n} = sprintf('S%02d-E%03d: %s (%s-%s)', seg, epo, m.tag, m.prev, m.next); %#ok<AGROW>
   end
   [item, ok] = listdlg( ...
      'ListString', ts, ...
      'SelectionMode', 'single', ...
      'Name', 'Marker list');
   if ok
      mrk = h.markers(item);
      [seg, epo] = parsed_eeg_position(h, mrk.start_pos);
      h.currEpoch.String = epo;
      h.currSeg.String = seg;
      draw_epoch(h);
   end
end
%-------------------------------------------------> Modifying signal YLims
function moreEEGpeak_Callback(~, ~, h) %#ok<DEFNU>
   set_ylim(h, .9, 1)
end
function lessEEGpeak_Callback(~, ~, h) %#ok<DEFNU>
   set_ylim(h, 1.1, 1)
end
function moreEMGpeak_Callback(~, ~, h) %#ok<DEFNU>
   set_ylim(h, 1, .9)
end
function lessEMGpeak_Callback(~, ~, h) %#ok<DEFNU>
   set_ylim(h, 1, 1.1)
end

function set_ylim(h, deeg, demg)
   p = h.eeg_peak * deeg;
   h.eegPlot.YLim = [-p p];
   h.eeg_peak = p;
   if ~isempty(h.emg)
      p = h.emg_peak * demg;
      h.emgPlot.YLim = [-p p];
      h.emg_peak = p;
   end
   guidata(h.window, h);
end
%----------------------------------------------> Manually setting EEG YLim
function btnEEGuV_Callback(hObject, ~, h) %#ok<DEFNU>
   curr_YLim = num2str(h.eegPlot.YLim(2));
   x = inputdlg('Set Y limit in microvolts', 'EEG plot', 1, {curr_YLim});
   if ~isempty(x)
      l = str2double(x{1});
      h.eegPlot.YLim = [-l l];
      h.eeg_peak = l;
      guidata(hObject, h)
   end
end
%----------------------------------------------> Manually setting EMG YLim
function btnEMGuV_Callback(hObject, ~, h) %#ok<DEFNU>
   curr_YLim = num2str(h.emgPlot.YLim(2));
   x = inputdlg('Set Y limit in microvolts', 'EMG plot', 1, {curr_YLim});
   if ~isempty(x)
      l = str2double(x{1});
      h.emgPlot.YLim = [-l l];
      h.emg_peak = l;
      guidata(hObject, h)
   end
end

%=========================================================================
%====================================================== edit-box callbacks
%=========================================================================

%----------------------------------------------------> Set current segment
function currSeg_Callback(hObject, ~, h) %#ok<DEFNU>
   t = uivalue(hObject);
   if t<1, t=1; end
   if t>h.num_segments, t=h.num_segments; end
   h = jump_to(h, t);
   guidata(hObject, h)
end
%------------------------------------------------------> Set current epoch
function currEpoch_Callback(hObject, ~, h) %#ok<DEFNU>
   t = uivalue(hObject);
   if t<1, t=1; end
   if t>h.epochs_in_seg, t=h.epochs_in_seg; end
   set(hObject, 'String', t)
   h = draw_epoch(h);
   guidata(hObject, h)
end
%-------------------------------------------------> Set epochs-per-segment
function txtEpInSeg_Callback(hObject, ~, h) %#ok<DEFNU>
   h.epochs_in_seg = uivalue(hObject);
   h = update_parameters(h);
   h = jump_to(h, 1);
   guidata(hObject, h)
end
%----------------------------------------------------> Set output filename
function txtHypnoFName_Callback(hObject, ~, h) %#ok<DEFNU>
   % ensure that file name is only made of letters, numbers, underscores
   m = regexp(hObject.String, '\W', 'once');
   if isempty(m)
      h.btnSave.Enable = 'on';
   else
      hObject.String = 'Invalid file name!';
      h.btnSave.Enable = 'off';
   end
end
%---------------------------------------------------------> Set marker tag
function txtMarkerTag_Callback(hObject, ~, h) %#ok<DEFNU>
   mrk = h.sldMarkers.Value;
   h.markers(mrk).tag = hObject.String;
   guidata(hObject, h)
end
%=========================================================================
%======================================================== slider callbacks
%=========================================================================

%----------------------------------------------------> Set current segment
function segment_Callback(hObject, ~, h) %#ok<DEFNU>
   h = jump_to(h, uisnapslider(hObject));
   guidata(hObject, h)
end
%-------------------------------------- Browsing events through the slider
function sldEvents_Callback(hObject, ~, h)
   v = uisnapslider(hObject);
   set_event_thr_label(h, v)
   h.lblCurrEvent.String = sprintf('%d of %d events', v, hObject.Max);
   epInSeg = uivalue(h.txtEpInSeg);
   h = jump_to(h, floor(h.watch_epochs(v)/epInSeg)+1, rem(h.watch_epochs(v), epInSeg)+1);
   guidata(hObject, h)
end
%=========================================================================
%================================================================ BROWSING
%=========================================================================

%--------------------------------------------------> Set segment and epoch
function h = jump_to(h, seg, epo)
   if nargin<3, epo=1; end
   h.currSeg.String = seg;
   h.currEpoch.String = epo;
   draw_spectra(h)
   h = draw_epoch(h);
end
%-------------------------------------------------------> Go to next epoch
function h = next_epoch(h)
   %    if h.gui_state == h.k.NORMAL
   e = uivalue(h.currEpoch) + 1;
   s = uivalue(h.currSeg);
   if e > h.epochs_in_seg && s < h.num_segments
      h.currEpoch.String = 1;
      h.currSeg.String = s+1;
      draw_spectra(h)
   else
      h.currEpoch.String = min(e, h.epochs_in_seg);
   end
   % end
   h = draw_epoch(h);
end
%---------------------------------------------------> Go to previous epoch
function h = prev_epoch(h)
   %    if h.gui_state == h.k.NORMAL
   e = uivalue(h.currEpoch) - 1;
   s = uivalue(h.currSeg);
   if e < 1 && s > 1
      h.currEpoch.String = h.epochs_in_seg;
      h.currSeg.String = s-1;
      draw_spectra(h)
   else
      h.currEpoch.String = max(uivalue(h.currEpoch)-1, 1);
   end
   % end
   h = draw_epoch(h);
end
%=========================================================================
%========================================================== DRAWING THINGS
%=========================================================================

%-----------------------------------------------------------> Draw spectra
function draw_spectra(h)
   axes(h.spectra)
   sg = h.pow.spectrogram(seg_range(h, uivalue(h.currSeg)));
   sg.HitTest = 'off';
   h.spectra.XLim = [0.5 h.epochs_in_seg+0.5];
   h.spectra.YLim = [h.hz_min h.hz_max]+0.5;
   h.spectra.XTick = 0.5:10: h.epochs_in_seg+0.5;
   h.spectra.XTickLabel = 0:10:h.epochs_in_seg;
   h.spectra.TickLength = [.007 .007];
   box on
end
%------------------------------------------------------> Draw epoch charts
function h = draw_epoch(h)
   %    h.gui_state = h.k.NORMAL;
   %    highlight_eeg(h, 'normal')

   seg = uivalue(h.currSeg);
   epo = uivalue(h.currEpoch);

   if h.tot_epochs >= ep1(h, seg) + epo
      h = draw_eeg(h, seg, epo);
      draw_hypno(h, seg, epo);
      draw_power(h, seg, epo);
   end
end
%-------------------------------------------------------- Draw EEG and EMG
function h = draw_eeg(h, seg, epo)
   axes(h.eegPlot)
   sig = eeg_for(h, seg, epo);
   plot(sig, 'k', 'hittest', 'off')
   h.eegPlot.YLim = [-h.eeg_peak h.eeg_peak];
   h.eegPlot.XLim = [0 length(sig)];
   h.eegPlot.XTickLabel = '';

   % if this epoch contains event markers, draw them
   if h.cm
      [segs, epos, poss] = parsed_eeg_position(h, [h.markers.finish_pos]);
      for ev = find(and(segs==seg, epos==epo))
         h.patches(ev).finish = draw_marker_finish(h, poss(ev), ev, h.markers(ev).tag);
      end
      [segs, epos, poss] = parsed_eeg_position(h, [h.markers.start_pos]);
      for ev = find(and(segs==seg, epos==epo))
         h.patches(ev).start = draw_marker_start(h, poss(ev), ev);
      end
   end

   if ~isempty(h.emg)
      axes(h.emgPlot)
      plot(emg_for(h, seg, epo), 'k', 'hittest', 'off');
      h.emgPlot.YLim = [-h.emg_peak h.emg_peak];
   end

   sp = 0:h.scoring_epoch;
   set([h.eegPlot, h.emgPlot, h.actiPlot], ...
      'ticklength', [.007 .007], ...
      'xlim', [0 length(sig)], ...
      'xtick', sp*h.sampling_rate)
   h.emgPlot.XTickLabel = sp;
end
%-----------------------------------------------------> Draw zoomed epoch
function draw_zoomed_epoch(h)
   axes(h.eegPlot)
   eeg = h.eeg(h.zoom_start:h.zoom_end);
   plot(eeg, 'k', 'hittest', 'off')
   h.eegPlot.XLim = [1 h.zoom_end-h.zoom_start];
   
   if ~isempty(h.emg)
      axes(h.emgPlot)
      emg = h.emg(h.zoom_start:h.zoom_end);
      plot(emg, 'k', 'hittest', 'off');
      h.emgPlot.XLim = [1 h.zoom_end-h.zoom_start];
   end
end
%-----------------------------------------------------> Draw the hypnogram
function draw_hypno(h, seg, epo)
   axes(h.hypno)
   ns = length(h.vig_states);
   l = fill([epo-1 epo epo epo-1], [0 0 ns+1 ns+1], [1 .7 1]);
   set(l, 'linestyle', 'none')
   hold on
   y = h.score(seg_range(h, seg));
   x = 0:length(y)-1;
   stairs(x, y, 'hittest', 'off', 'color', 'k');
   set(h.hypno, ...
      'ticklen', [.007 .007], ...
      'tickdir', 'out', ...
      'ylim', [.5 .5+ns], ...
      'ytick', 1:ns, ...
      'xlim', [0 h.epochs_in_seg], ...
      'xticklabel', '', ...
      'yticklabel', h.vig_states, ...
      'layer', 'top', ...
      'ButtonDownFcn', @hypno_ButtonDownFcn);
   hold off
end
%---------------------------------------------------> Draw the power curve
function draw_power(h, seg, epo)
   axes(h.power)
   e = ep1(h, seg) + epo -1;
   h.pow.power_density_curve(e);
   set(h.power, ...
      'ylim', [h.pow.MinPwr h.pow.MaxPwr], ...
      'ticklen', [.05 .05])
end
%--------------------------------------------------> Draw the marker start
function rv = draw_marker_start(h, x, mkr)
   [cx, cy, c] = draw_marker_util(h, x, 1);
   rv = patch(cx, cy, c, ...
      'linestyle', 'none', ...
      'ButtonDownFcn',{@modify_event, mkr, h}, ...
      'PickableParts','all');
end
%----------------------------------------------------> Draw the marker end
function rv = draw_marker_finish(h, x, mkr, tag)
   [cx, cy, c] = draw_marker_util(h, x, -1);
   rv = patch(cx, cy, c, ...
      'linestyle', 'none', ...
      'ButtonDownFcn',{@modify_event, mkr, h}, ...
      'PickableParts','all');
   text(cx(1)+30, cy(2)*0.75, tag, 'EdgeColor', [0.333 0.4 1])
end
%----------------------------------------------------> Hackish marker util
function [cx, cy, c] = draw_marker_util(h, x, sig)
   axes(h.eegPlot)
   y1 = -h.eeg_peak;
   y2 =  h.eeg_peak;
   mx = diff(h.eegPlot.XLim)/80;
   cx = [x x x+mx*sig x+1*sig x+1*sig x+mx*sig];
   cy = [y1 y2 y2 y2*.75 y1*.75 y1];
   c = [1/3, 4/10, 1];
end
%-----------------------------------------------------> Draw zoom boundary
function draw_zoom_marker(h, x)
   axes(h.eegPlot)
   yl = h.eegPlot.YLim;
   patch([x x x+1 x+1], [yl(1) yl(2) yl(2) yl(1)], 'r' )
end

%=========================================================================
%============================================================ THRESHOLDING
%=========================================================================
function h = setting_EEG_thr(h, eventdata)
   h.gui_state = h.k.NORMAL;
   cp = eventdata.IntersectionPoint(2);
   h.event_thr = cp;
   highlight_eeg(h, 'normal')
   x = inputdlg('Do you want to find events based on this threshold?', 'Finding events', 1, {num2str(cp)});
   if ~isempty(x), h = find_events(h); end
end

function h = find_events(h)
   over_thr = find(abs(h.eeg) > abs(h.event_thr));
   h.watch_epochs = unique(floor(over_thr / h.epoch_size));
   ne = length(h.watch_epochs);
   if ne==0
      h.sldEvents.Enabled = 'off';
   else
      set(h.sldEvents, ...
         'Enable', 'on', ...
         'Min', 1, ...
         'Max', ne, ...
         'SliderStep', [1/(ne-1), 10/(ne-1)], ...
         'Value', 1)
      set_event_thr_label(h, 1)
      sldEvents_Callback(h.sldEvents, 0, h)
   end
end
%=========================================================================
%================================================================= ZOOMING
%=========================================================================
function h = toggle_zoom(h)
   switch h.gui_state
      case { h.k.ZOOM, h.k.ZOOMING, h.k.ZOOMED }
         h.gui_state = h.k.NORMAL;
         h = draw_epoch(h);
      case h.k.NORMAL
         h.gui_state = h.k.ZOOM;
         highlight_eeg(h, 'zoom')
      case h.k.MARKING
         % TODO manage zooming while marking!
      otherwise
         beep
         return
   end
end

function h = set_zoom_start(h, eventdata)
   x = x_btn_pos(eventdata);
   draw_zoom_marker(h, x)
   h.zoom_start = global_eeg_position(h, x);
   h.gui_state = h.k.ZOOMING;
end

function h = set_zoom_end(h, eventdata)
   x = x_btn_pos(eventdata);
   ze = global_eeg_position(h, x);
   if ze < h.zoom_start
      beep
      return
   end
   h.zoom_end = global_eeg_position(h, x);
   draw_zoomed_epoch(h)
   h.gui_state = h.k.ZOOMED;
end

%=========================================================================
%================================================================= MARKERS
%=========================================================================
function h = toggle_mark(h)
   switch h.gui_state
      case { h.k.NORMAL, h.k.ZOOMED }
         h = set_mark_on(h);
      case { h.k.MARKING }
         if h.marking, h = delete_marker(h); end
         h = set_mark_off(h);
      otherwise
         beep
   end
end

function h = set_mark_on(h)
   h.gui_state = h.k.MARKING;
   highlight_eeg(h, 'mark');
end

function h = set_mark_off(h)
   h.gui_state = h.k.NORMAL;
   h.marking = false;
   highlight_eeg(h, 'normal');
end


function h = start_normal_marker(h, eventdata)
   x = x_btn_pos(eventdata);
   h = start_marker(h, global_eeg_position(h, x), x);
end

function h = start_zoomed_marker(h, eventdata)
   x = x_btn_pos(eventdata);
   h = start_marker(h, h.zoom_start+x, x);
end

function h = start_marker(h, absx, relx)
   h.cm = h.cm+1;
   h.markers(h.cm).start_pos = absx;
   h.patches(h.cm).start = draw_marker_start(h, relx, h.cm);
   h.marking = true;
end

function h = finish_normal_marker(h, eventdata)
   relx = x_btn_pos(eventdata);
   absx = global_eeg_position(h, relx);
   h = finish_marker(h, absx, relx);
end

function h = finish_zoomed_marker(h, eventdata)
   relx = x_btn_pos(eventdata);
   absx = h.zoom_start + relx;
   h = finish_marker(h, absx, relx);
end

function h = finish_marker(h, absx, relx)
   if absx <= h.markers(h.cm).start_pos, beep; return; end
   %! h.btnCancelMarker.Visible = 'off';
   h.patches(h.cm).finish = draw_marker_finish(h, relx, h.cm, '?');
   p = {
      'Assign tag to event or cancel'
      'Preceding state'
      'Following state'
      };
   s = inputdlg(p, 'Tagging events', 1, {h.default_event_tag, 'Prev', 'Next'});
   if isempty(s) % never mind... ignore this marker
      delete([h.patches(h.cm).start h.patches(h.cm).finish]);
      h = delete_marker(h);
   else % we do have a new marker
      h.markers(h.cm).finish_pos = absx;
      h.markers(h.cm).prev = s{2};
      h.markers(h.cm).next = s{3};
      h.markers(h.cm).tag = s{1};
      h.default_event_tag = s{1};
      h.patches(h.cm).finish = draw_marker_finish(h, relx, h.cm, s{1});
      %       h = set_marker_info(h, h.cm);
   end
   h = set_mark_off(h);
   h = draw_epoch(h);
end
%=========================================================================
% subfunctions/utilities
%=========================================================================

% format eegPlot according to current state
function highlight_eeg(h, style)
   switch style
      case 'zoom'
         h.eegPlot.Color = [.961 .922 .922];
      case 'normal'
         h.eegPlot.Color = 'white';
      case 'thres'
         h.eegPlot.Color = 'yellow';
      case 'mark'
         h.eegPlot.Color = [.95 .95 1];
   end
end

function set_event_thr_label(h, curr)
   s = sprintf('Event #%d of %d @ %f mV', curr, h.sldEvents.Max, h.event_thr);
   h.lblEventThr.String = s;
end
function rv = seg_range(h, seg)
   rv = ep1(h, seg):epN(h, seg);
end
function rv = ep1(h, seg)
   rv = (seg-1) * h.epochs_in_seg + 1;
end
function rv = epN(h, seg)
   rv = min(seg * h.epochs_in_seg, h.tot_epochs);
end

function h = delete_marker(h, ev)
   if nargin<2, ev = h.cm; end
   h.markers(ev) = [];
   h.cm = h.cm-1;
   h.gui_state = h.k.NORMAL;
   h.marking = false;
   h = draw_eeg(h, uivalue(h.currSeg), uivalue(h.currEpoch));
end

%--------------------------------------------------------------------> eeg_for
function rv = eeg_for(h, seg, epo)
   % given a segment and an epoch, return the eeg data
   rv = h.eeg(signal_range_for(h, seg, epo));
end

%--------------------------------------------------------------------> emg_for
function rv = emg_for(h, seg, epo)
   % given a segment and an epoch, return the emg data
   rv = h.emg(signal_range_for(h, seg, epo));
end

%---------------------------------------------------------------> signal_range
function rv = signal_range_for(h, seg, epo)
   first = (seg-1) * h.segment_size + (epo-1) * h.epoch_size + 1;
   last  = first + h.epoch_size - 1;
   rv = first:last;
end

function rv = x_btn_pos(eventdata)
   rv = round(eventdata.IntersectionPoint(1));
end

function rv = global_eeg_position(h, x)
   s1 = (uivalue(h.currSeg)-1) * h.epochs_in_seg;
   s2 = uivalue(h.currEpoch)-1;
   rv = (s1+s2)* h.epoch_size + x;
end

function [seg, epo, pos] = parsed_eeg_position(h, x)
   seg = floor(x / h.segment_size) + 1;
   t   = floor(x / h.epoch_size);
   epo = rem(t, h.epochs_in_seg)+1;
   pos = rem(x, h.epoch_size);
end

function rv = mrkstr
   rv = struct( ...
      'start_pos', {}, ...
      'finish_pos', {}, ...
      'tag', '');
end

function modify_event(~, ~, ev, h)
   m = h.markers(ev);
   s = sprintf('Event: %s (%s <--> %s). Delete?', m.tag, m.prev, m.next);
   choice = questdlg(s, 'Marker management', 'Yes', 'No', 'No');
   switch choice
      case 'Yes'
         h = delete_marker(h, ev);
         guidata(h.window, h);
   end
end
%----------------------------------------------------------> Update params
function h = update_parameters(h)
   % spectro/hypnogram chart duration in seconds
   h.segment_len   = h.scoring_epoch * h.epochs_in_seg;
   % number of segments in the signal
   h.num_segments = ceil(h.signal_len / h.segment_len);
   % the width (in samples) of the spectrogram/hypnogram charts
   h.segment_size = h.sampling_rate * h.segment_len;
end



%--------------------------------------------------------> Set marker info
% function h = set_marker_info(h, mno)
% 
%    if h.cm == 0
%       h.txtMarkerTag.String = '';
%       h.sldMarkers.Enable = 'off';
%       h.lblMarkers.String = 'no markers';
%       % h = draw_eeg(h, uivalue(h.currSeg), uivalue(h.currEpoch));
%    else
%       if h.cm==1 % disable the slider
%          mno = 1;
%          h.sldMarkers.Value = 1;
%          h.sldMarkers.Enable = 'off';
%       else
%          if nargin < 2, mno = h.sldMarkers.Value; end
%          h.sldMarkers.Enable     = 'on';
%          h.sldMarkers.Max        = h.cm;
%          h.sldMarkers.Value      = mno;
%          h.sldMarkers.SliderStep = [1/(h.cm-1), 10/(h.cm-1)];
%       end
%       mrk = h.markers(mno);
%       [seg, epo] = parsed_eeg_position(h, mrk.start_pos);
%       h = jump_to(h, seg, epo);
%       h.txtMarkerTag.String = mrk.tag;
%       h.lblMarkers.String = sprintf('%d of %d', mno, h.cm);
%       highlight_marker(h, mno)
%    end
% end

%------------------------------------------------> Deleting current marker
% function btnDelMarker_Callback(~, ~, h) %#ok<DEFNU>
%    x = questdlg('Delete this marker?', 'EEG Markers', 'No', 'Yes', 'Yes');
%    switch x
%       case 'No'
%       case 'Yes'
%          mrk = h.sldMarkers.Value;
%          h.markers(mrk) = [];
%          h.cm = h.cm-1;
%          guidata(h.window, h)
%          set_marker_info(h, min(mrk, h.cm));
%    end
% end

% function highlight_marker(h, mrk)
%    m = h.patches(mrk);
%    p = m.start;
%    if ishandle(m.finish), p = [p m.finish]; end
%    set(p, 'facecolor', [1 0.5 0])
% end

%-------------------------------------- Browsing markers through the slider
% function sldMarkers_Callback(hObject, ~, h) %#ok<DEFNU>
%    uisnapslider(hObject);
%    set_marker_info(h);
% end

%----------------------------------------------------> Abort marking event
% function btnCancelMarker_Callback(hObject, ~, h) %#ok<DEFNU>
%    hObject.Visible = 'off';
%    h = delete_marker(h);
%    guidata(hObject, h)
% end
