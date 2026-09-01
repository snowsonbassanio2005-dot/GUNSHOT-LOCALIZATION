% COLLECT_DATASET - Master Application for 6-Microphone Acoustic Dataset Collection
%
% PURPOSE:
%   Dedicated standalone application for collecting, detecting, labeling, and
%   saving 6-microphone acoustic impulse recordings for DOA localization research.
%
% WORKFLOW:
%   1. Initializes NI DAQ-6221 (Dev1, AI0:AI5 @ 40 kHz) and continuous ring buffer.
%   2. Scans data/ and metadata to automatically resume from the latest event ID.
%   3. Displays real-time 6-channel live oscilloscope waveforms.
%   4. Automatically detects impulsive acoustic wavefronts using 7-stage detector.
%   5. Prompts user for ground-truth Distance (m) and Angle (0-359 deg).
%   6. Saves raw 6-channel waveform CSV and appends to metadata.xlsx / metadata.csv.
%   7. Shows a 2-second confirmation banner and resumes continuous monitoring.
%
% HARDWARE:
%   - NI DAQ-6221, 6 MAX4466 Mics on 26 cm Circular Array (Radius = 13 cm).
%
% COMPATIBILITY:
%   - MATLAB R2020a through R2023b+ (Data Acquisition Toolbox compatible).

function collect_dataset()
    clearvars -except keepVars;
    clc;

    fprintf("======================================================================\n");
    fprintf("    MATLAB 6-MICROPHONE ACOUSTIC DATASET COLLECTION SYSTEM           \n");
    fprintf("    NI DAQ-6221 | 40 kS/s | 26 cm Array | Persistent Logging         \n");
    fprintf("======================================================================\n\n");

    %% 1. Set Path & Load Configuration
    collectorRoot = fileparts(mfilename('fullpath'));
    if isempty(collectorRoot)
        collectorRoot = pwd;
    end
    addpath(collectorRoot);
    addpath(fullfile(collectorRoot, 'acquisition'));
    addpath(fullfile(collectorRoot, 'tests'));

    cfg = config();
    fprintf("[CONFIG] Loaded collector configuration.\n");
    fprintf("         Array Radius: %.2f m | Sample Rate: %d Hz | Channels: 6\n", ...
        cfg.arrayRadius, cfg.fs);

    %% 2. Auto-Create Directories & Resume Session State
    state = initialize_dataset(cfg);
    fprintf("[STORAGE] %s\n", state.statusMsg);
    fprintf("          Waveforms: %s\n", cfg.paths.recordingsDir);
    fprintf("          Metadata:  %s\n\n", cfg.paths.metadataCsv);

    %% 3. Initialize Continuous Acquisition (NI-DAQ or Simulation Streamer)
    [dq, daqInfo] = initDAQ(cfg);
    fprintf("[DAQ] %s\n", daqInfo);

    %% 4. Initialize Synchronized 6-Channel Circular Ring Buffer
    ringBuf = CircularBuffer(cfg.buffer.capacity, cfg.numMics);
    fprintf("[BUFFER] Pre-allocated %d-sample 6-channel circular ring buffer (%.1f s capacity)\n", ...
        cfg.buffer.capacity, cfg.buffer.durationSec);

    %% 5. Initialize Modern High-Contrast GUI Dashboard
    gui = initCollectorGUI(cfg, state, daqInfo);
    fprintf("[GUI] Interactive monitoring dashboard launched. Press 'STOP & QUIT' to exit.\n\n");

    %% 6. Master Acquisition & Event Monitoring Loop
    lastTriggerTic      = -inf;
    lastGuiRefreshTic   = tic;
    guiRefreshInterval  = 1.0 / cfg.gui.refreshRateHz;
    toastExpirationTic  = -inf;
    lastEnteredDistance = "1.00";
    lastEnteredAngle    = "0.0";

    disp("[SYSTEM READY] Live acoustic monitoring armed. Waiting for acoustic impulses...");

    while isgraphics(gui.fig) && gui.isRunning
        try
            % Check if user paused monitoring
            if gui.isPaused
                updateStatusBadge(gui, "PAUSED", "Monitoring paused by user", [0.85, 0.65, 0.15]);
                pause(0.04);
                drawnow limitrate;
                continue;
            end

            % A. Read block from DAQ stream
            [dataBlock, dq] = readBlock(dq, cfg.blockSize);

            % Sanitize block against NaN / Inf
            if ~isempty(dataBlock)
                dataBlock(~isfinite(dataBlock)) = 0.0;
                dataBlock = max(-10.0, min(10.0, dataBlock));
                ringBuf.write(dataBlock);
            end

            % B. Handle Active Toast Expiration
            if ~isinf(toastExpirationTic) && toc(toastExpirationTic) >= cfg.gui.saveToastDurationSec
                toastExpirationTic = -inf;
                updateStatusBadge(gui, "ARMED", "Armed & Monitoring (6 Channels)", [0.10, 0.70, 0.35]);
            end

            % C. Check for Manual Trigger Request from GUI Button
            isManualTrigger = gui.manualTriggerRequested;
            if isManualTrigger
                gui.manualTriggerRequested = false;
            end

            % D. Evaluate Recent Audio for Impulsive Acoustic Transient
            analysisWindow = ringBuf.read(round(0.040 * cfg.fs)); % Recent 40 ms
            [isAutoTrigger, eventMeta] = detect_event(analysisWindow, cfg, lastTriggerTic);

            isTriggered = isAutoTrigger || isManualTrigger;

            % E. Event Detection Handler
            if isTriggered
                lastTriggerTic = tic;

                % Read additional post-trigger block to guarantee complete waveform in buffer
                extraPostSamples = round(0.025 * cfg.fs);
                [postBlock, dq] = readBlock(dq, extraPostSamples);
                if ~isempty(postBlock)
                    postBlock(~isfinite(postBlock)) = 0.0;
                    ringBuf.write(postBlock);
                end

                % Extract exact synchronized (pre + post) event window (60 ms = 2400 samples)
                [rawWindow, isComplete] = ringBuf.extractEventWindow(cfg.trigger.preSamples, cfg.trigger.postSamples);

                if isComplete && size(rawWindow, 1) >= cfg.trigger.totalSamples
                    rawWindow = rawWindow(end - cfg.trigger.totalSamples + 1 : end, :);
                    rawWindow(~isfinite(rawWindow)) = 0.0;

                    % Update status to EVENT DETECTED
                    updateStatusBadge(gui, "EVENT DETECTED", ...
                        sprintf("EVENT DETECTED! (SNR: %.1f dB, %d Mics)", eventMeta.snr_dB, eventMeta.triggeredChannels), ...
                        [0.90, 0.20, 0.20]);
                    
                    % Update oscilloscope with detected event
                    updateOscilloscope(gui, rawWindow, cfg);
                    drawnow;

                    % Prompt user with validation dialog
                    [savedOk, distVal, angVal, canceled] = promptUserLabels(gui.fig, state.nextEventId, lastEnteredDistance, lastEnteredAngle);

                    if canceled
                        fprintf("[USER] Event %04d labeling canceled by user. Resuming monitoring.\n", state.nextEventId);
                        appendLog(cfg, sprintf("[EVENT_CANCELED] Event %04d dismissed without saving.", state.nextEventId));
                        updateStatusBadge(gui, "ARMED", "Armed & Monitoring (6 Channels)", [0.10, 0.70, 0.35]);
                    elseif savedOk
                        % Persist raw waveform and update metadata
                        tStamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                        [success, saveMsg, savedName, savedPath] = save_event( ...
                            rawWindow, state.nextEventId, distVal, angVal, tStamp, cfg, eventMeta);

                        if success
                            fprintf("[SAVE] %s\n", saveMsg);

                            % Remember entered values for subsequent prompt defaults
                            lastEnteredDistance = string(distVal);
                            lastEnteredAngle    = string(angVal);

                            % Update Runtime State
                            state.totalEvents    = state.totalEvents + 1;
                            state.lastSavedEvent = struct('name', savedName, 'distance', distVal, 'angle', angVal, 'timestamp', tStamp);
                            state.nextEventId    = state.nextEventId + 1;

                            % Update GUI Metrics
                            updateMetricsCards(gui, state);

                            % Display 2-second success toast
                            toastMsg = sprintf("%s Saved Successfully (%.2fm, %.1f°)", savedName, distVal, angVal);
                            updateStatusBadge(gui, "SAVED", toastMsg, [0.08, 0.65, 0.40]);
                            toastExpirationTic = tic;
                        else
                            errordlg(saveMsg, "Save Error", "modal");
                            updateStatusBadge(gui, "ARMED", "Armed & Monitoring (6 Channels)", [0.10, 0.70, 0.35]);
                        end
                    end
                end
            else
                % F. Periodic Live Oscilloscope Refresh (25 Hz)
                if toc(lastGuiRefreshTic) >= guiRefreshInterval
                    scopeSamples = round(cfg.gui.waveformWindowSec * cfg.fs);
                    recentAudio = ringBuf.read(scopeSamples);
                    if ~isempty(recentAudio)
                        updateOscilloscope(gui, recentAudio, cfg);
                    end
                    lastGuiRefreshTic = tic;
                end
            end

        catch loopME
            fprintf("[WARNING] Exception caught in acquisition loop: %s\n", loopME.message);
            appendLog(cfg, sprintf("[LOOP_EXCEPTION] %s", loopME.message));
        end

        % Yield thread to UI event queue
        drawnow limitrate;
    end

    %% 7. Clean Teardown & Exit
    fprintf("\n[SHUTDOWN] Stopping acquisition and releasing DAQ hardware...\n");
    stopDAQ(dq);
    timeStr = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    appendLog(cfg, sprintf("[%s] [SESSION_END] Dataset Collector closed. Total events collected: %d.", ...
        timeStr, state.totalEvents));
    fprintf("[SHUTDOWN] Session complete. Total recorded events: %d.\n", state.totalEvents);
end

%% ========================================================================
%% GUI INITIALIZATION AND COMPONENT BUILDER
%% ========================================================================
function gui = initCollectorGUI(cfg, state, daqInfo)
    gui = struct();
    gui.isRunning              = true;
    gui.isPaused               = false;
    gui.manualTriggerRequested = false;

    % Palette Definitions (Modern Dark Theme)
    bgDark       = [0.07, 0.09, 0.13]; % #121722
    cardBg       = [0.11, 0.14, 0.20]; % #1c2433
    panelBorder  = [0.18, 0.23, 0.32];
    textLight    = [0.94, 0.96, 0.98];
    textMuted    = [0.55, 0.60, 0.70];
    accentCyan   = [0.05, 0.75, 0.90];
    statusGreen  = [0.10, 0.70, 0.35];

    % Main Figure Window
    fig = figure( ...
        'Name', 'MATLAB 6-Microphone Acoustic Dataset Collector', ...
        'NumberTitle', 'off', ...
        'Color', bgDark, ...
        'MenuBar', 'none', ...
        'ToolBar', 'none', ...
        'Position', [80, 80, 1320, 820], ...
        'CloseRequestFcn', @(src, evt) onQuitClick(fig));
    
    gui.fig = fig;

    % 1. Header Banner
    uicontrol(fig, 'Style', 'text', ...
        'String', 'MATLAB 6-CHANNEL ACOUSTIC DATASET COLLECTOR', ...
        'FontName', 'Segoe UI', 'FontSize', 16, 'FontWeight', 'bold', ...
        'ForegroundColor', textLight, 'BackgroundColor', bgDark, ...
        'HorizontalAlignment', 'left', ...
        'Position', [30, 770, 700, 35]);

    uicontrol(fig, 'Style', 'text', ...
        'String', sprintf('Hardware: %s | Fs: %d Hz | Array: 26 cm (6 Mics)', daqInfo, cfg.fs), ...
        'FontName', 'Segoe UI', 'FontSize', 10, ...
        'ForegroundColor', textMuted, 'BackgroundColor', bgDark, ...
        'HorizontalAlignment', 'left', ...
        'Position', [30, 745, 700, 22]);

    % 2. Status Badge Banner
    statusPanel = uipanel(fig, ...
        'BackgroundColor', cardBg, ...
        'BorderType', 'line', 'HighlightColor', panelBorder, ...
        'Units', 'pixels', 'Position', [30, 680, 820, 50]);
    
    gui.lblStatus = uicontrol(statusPanel, 'Style', 'text', ...
        'String', '🟢 ARMED & MONITORING (6 CHANNELS)', ...
        'FontName', 'Segoe UI', 'FontSize', 12, 'FontWeight', 'bold', ...
        'ForegroundColor', statusGreen, 'BackgroundColor', cardBg, ...
        'HorizontalAlignment', 'center', ...
        'Units', 'normalized', 'Position', [0.02, 0.1, 0.96, 0.8]);

    % 3. Multi-Channel Oscilloscope Area (6 Subplots)
    gui.axesChannels = gobjects(cfg.numMics, 1);
    gui.plotLines    = gobjects(cfg.numMics, 1);

    channelColors = [
        0.05, 0.75, 0.90;   % Ch 1 (Cyan)
        0.10, 0.80, 0.50;   % Ch 2 (Emerald)
        0.95, 0.65, 0.15;   % Ch 3 (Amber)
        0.65, 0.45, 0.95;   % Ch 4 (Purple)
        0.95, 0.30, 0.45;   % Ch 5 (Rose)
        0.20, 0.60, 1.00;   % Ch 6 (Sky Blue)
    ];

    axWidth  = 820;
    axHeight = 85;
    yBase    = 580;
    ySpacing = 95;

    timeMsVector = linspace(0, cfg.gui.waveformWindowSec * 1000, round(cfg.gui.waveformWindowSec * cfg.fs));
    dummyData = zeros(numel(timeMsVector), 1);

    for m = 1:cfg.numMics
        yPos = yBase - (m - 1) * ySpacing;
        ax = axes(fig, ...
            'Units', 'pixels', ...
            'Position', [30, yPos, axWidth, axHeight], ...
            'Color', [0.08, 0.10, 0.15], ...
            'XColor', textMuted, 'YColor', textMuted, ...
            'GridColor', [0.18, 0.22, 0.30], 'GridAlpha', 0.6, ...
            'FontName', 'Segoe UI', 'FontSize', 8);
        grid(ax, 'on');
        hold(ax, 'on');
        ylim(ax, [-2.5, 2.5]);
        xlim(ax, [0, cfg.gui.waveformWindowSec * 1000]);

        if m < cfg.numMics
            set(ax, 'XTickLabel', []);
        else
            xlabel(ax, 'Time (ms)', 'FontName', 'Segoe UI', 'FontSize', 9, 'Color', textMuted);
        end

        % Channel Label Indicator
        ylabel(ax, sprintf('M%d (AI%d)', m, cfg.channels(m)), ...
            'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', 'Color', channelColors(m, :));

        hLine = plot(ax, timeMsVector, dummyData, 'LineWidth', 1.2, 'Color', channelColors(m, :));
        gui.axesChannels(m) = ax;
        gui.plotLines(m)    = hLine;
    end

    % 4. Right Side Telemetry & Control Sidebar
    sidebarX = 875;
    sidebarWidth = 415;

    % Telemetry Card
    telemetryPanel = uipanel(fig, ...
        'Title', ' DATASET METRICS & COUNTER ', ...
        'FontName', 'Segoe UI', 'FontSize', 10, 'FontWeight', 'bold', ...
        'ForegroundColor', accentCyan, 'BackgroundColor', cardBg, ...
        'BorderType', 'line', 'HighlightColor', panelBorder, ...
        'Units', 'pixels', 'Position', [sidebarX, 420, sidebarWidth, 310]);

    % Next Event Counter
    uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', 'NEXT EVENT ID', ...
        'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
        'ForegroundColor', textMuted, 'BackgroundColor', cardBg, ...
        'Position', [20, 245, 180, 18], 'HorizontalAlignment', 'left');

    gui.lblNextEvent = uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', sprintf('event_%04d', state.nextEventId), ...
        'FontName', 'Segoe UI', 'FontSize', 22, 'FontWeight', 'bold', ...
        'ForegroundColor', [0.30, 0.85, 1.00], 'BackgroundColor', cardBg, ...
        'Position', [20, 210, 360, 35], 'HorizontalAlignment', 'left');

    % Total Events Saved
    uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', 'TOTAL RECORDED SAMPLES', ...
        'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
        'ForegroundColor', textMuted, 'BackgroundColor', cardBg, ...
        'Position', [20, 175, 200, 18], 'HorizontalAlignment', 'left');

    gui.lblTotalEvents = uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', sprintf('%d Events Recorded', state.totalEvents), ...
        'FontName', 'Segoe UI', 'FontSize', 14, 'FontWeight', 'bold', ...
        'ForegroundColor', textLight, 'BackgroundColor', cardBg, ...
        'Position', [20, 150, 360, 25], 'HorizontalAlignment', 'left');

    % Last Saved Event Box
    uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', 'LAST SAVED RECORDING', ...
        'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
        'ForegroundColor', textMuted, 'BackgroundColor', cardBg, ...
        'Position', [20, 115, 200, 18], 'HorizontalAlignment', 'left');

    gui.lblLastSaved = uicontrol(telemetryPanel, 'Style', 'text', ...
        'String', formatLastSavedString(state.lastSavedEvent), ...
        'FontName', 'Segoe UI', 'FontSize', 10, ...
        'ForegroundColor', [0.80, 0.85, 0.90], 'BackgroundColor', [0.08, 0.10, 0.15], ...
        'Position', [20, 20, 375, 90], 'HorizontalAlignment', 'left');

    % Control Action Buttons Panel
    controlPanel = uipanel(fig, ...
        'Title', ' SESSION CONTROLS ', ...
        'FontName', 'Segoe UI', 'FontSize', 10, 'FontWeight', 'bold', ...
        'ForegroundColor', accentCyan, 'BackgroundColor', cardBg, ...
        'BorderType', 'line', 'HighlightColor', panelBorder, ...
        'Units', 'pixels', 'Position', [sidebarX, 100, sidebarWidth, 305]);

    % Pause / Resume Button
    gui.btnPause = uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'String', '⏸  PAUSE MONITORING', ...
        'FontName', 'Segoe UI', 'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', textLight, 'BackgroundColor', [0.20, 0.26, 0.38], ...
        'Position', [20, 230, 375, 45], ...
        'Callback', @(src, evt) togglePause(fig));

    % Manual Trigger Button
    uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'String', '⚡  MANUAL TRIGGER (CAPTURE NOW)', ...
        'FontName', 'Segoe UI', 'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', textLight, 'BackgroundColor', [0.18, 0.45, 0.70], ...
        'Position', [20, 175, 375, 45], ...
        'Callback', @(src, evt) triggerManualCapture(fig));

    % Open Data Folder Button
    uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'String', '📁  OPEN DATASET FOLDER', ...
        'FontName', 'Segoe UI', 'FontSize', 10, ...
        'ForegroundColor', textLight, 'BackgroundColor', [0.16, 0.20, 0.28], ...
        'Position', [20, 120, 375, 42], ...
        'Callback', @(src, evt) openDatasetFolder(cfg));

    % Stop & Quit Button
    uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'String', '🛑  STOP ACQUISITION & QUIT', ...
        'FontName', 'Segoe UI', 'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', [1.0, 0.9, 0.9], 'BackgroundColor', [0.65, 0.15, 0.20], ...
        'Position', [20, 30, 375, 65], ...
        'Callback', @(src, evt) onQuitClick(fig));

    % Save GUI references inside figure UserData for fast handle access
    fig.UserData = gui;
end

%% ========================================================================
%% OSCILLOSCOPE AND TELEMETRY UPDATE FUNCTIONS
%% ========================================================================
function updateOscilloscope(gui, data, cfg)
    if isempty(data) || ~isgraphics(gui.fig)
        return;
    end
    
    % AC centering for display
    centered = data - median(data, 1);
    numSamples = size(data, 1);
    tMs = linspace(0, (numSamples / cfg.fs) * 1000, numSamples);

    for m = 1:cfg.numMics
        if isgraphics(gui.plotLines(m))
            set(gui.plotLines(m), 'XData', tMs, 'YData', centered(:, m));
        end
    end
end

function updateStatusBadge(gui, mode, textMsg, colorRGB)
    if ~isgraphics(gui.fig) || ~isfield(gui, 'lblStatus') || ~isgraphics(gui.lblStatus)
        return;
    end

    switch upper(mode)
        case "ARMED"
            prefix = "🟢 ";
        case "EVENT DETECTED"
            prefix = "🔴 ";
        case "SAVED"
            prefix = "✅ ";
        case "PAUSED"
            prefix = "⏸️ ";
        otherwise
            prefix = "ℹ️ ";
    end

    set(gui.lblStatus, ...
        'String', prefix + string(textMsg), ...
        'ForegroundColor', colorRGB);
end

function updateMetricsCards(gui, state)
    if ~isgraphics(gui.fig)
        return;
    end
    if isfield(gui, 'lblNextEvent') && isgraphics(gui.lblNextEvent)
        set(gui.lblNextEvent, 'String', sprintf('event_%04d', state.nextEventId));
    end
    if isfield(gui, 'lblTotalEvents') && isgraphics(gui.lblTotalEvents)
        set(gui.lblTotalEvents, 'String', sprintf('%d Events Recorded', state.totalEvents));
    end
    if isfield(gui, 'lblLastSaved') && isgraphics(gui.lblLastSaved)
        set(gui.lblLastSaved, 'String', formatLastSavedString(state.lastSavedEvent));
    end
end

function str = formatLastSavedString(lastEvt)
    if isempty(lastEvt) || ~isstruct(lastEvt) || ~isfield(lastEvt, 'name') || lastEvt.name == "None"
        str = sprintf("  No events saved in current session.\n  Waiting for first acoustic impulse...");
    else
        str = sprintf("  Event:     %s\n  Distance:  %.2f meters\n  Angle:     %.1f degrees\n  Timestamp: %s", ...
            lastEvt.name, lastEvt.distance, lastEvt.angle, lastEvt.timestamp);
    end
end

%% ========================================================================
%% USER LABEL PROMPT & INPUT VALIDATION
%% ========================================================================
function [ok, distVal, angVal, canceled] = promptUserLabels(parentFig, eventId, defaultDist, defaultAngle)
% Custom modal label entry dialog with robust validation and Cancel support
    ok = false;
    distVal = 0;
    angVal = 0;
    canceled = false;

    promptTitle = sprintf("Event %04d Detected - Enter Ground Truth Labels", eventId);
    promptQuestions = {
        'Enter Distance (meters):', ...
        'Enter Angle (degrees, 0-359):'
    };
    defaultAnswers = {char(defaultDist), char(defaultAngle)};

    while true
        answers = inputdlg(promptQuestions, promptTitle, [1 45], defaultAnswers);

        % User pressed Cancel
        if isempty(answers)
            canceled = true;
            return;
        end

        rawDist = strtrim(answers{1});
        rawAngle = strtrim(answers{2});

        % Validation: Distance
        dNum = str2double(rawDist);
        if isnan(dNum) || ~isreal(dNum) || dNum <= 0
            warndlg("Invalid Distance. Please enter a positive decimal number (e.g. 1.50).", ...
                "Input Validation Error", "modal");
            defaultAnswers = {rawDist, rawAngle};
            continue;
        end

        % Validation: Angle
        aNum = str2double(rawAngle);
        if isnan(aNum) || ~isreal(aNum) || aNum < 0 || aNum >= 360
            warndlg("Invalid Angle. Please enter a value between 0 and 359 degrees (e.g. 45.0).", ...
                "Input Validation Error", "modal");
            defaultAnswers = {rawDist, rawAngle};
            continue;
        end

        % Inputs validated successfully
        distVal = dNum;
        angVal  = aNum;
        ok      = true;
        return;
    end
end

%% ========================================================================
%% GUI EVENT CALLBACKS
%% ========================================================================
function togglePause(fig)
    if ~isgraphics(fig)
        return;
    end
    gui = fig.UserData;
    gui.isPaused = ~gui.isPaused;
    if gui.isPaused
        set(gui.btnPause, 'String', '▶  RESUME MONITORING', 'BackgroundColor', [0.15, 0.50, 0.30]);
    else
        set(gui.btnPause, 'String', '⏸  PAUSE MONITORING', 'BackgroundColor', [0.20, 0.26, 0.38]);
        updateStatusBadge(gui, "ARMED", "Armed & Monitoring (6 Channels)", [0.10, 0.70, 0.35]);
    end
    fig.UserData = gui;
end

function triggerManualCapture(fig)
    if ~isgraphics(fig)
        return;
    end
    gui = fig.UserData;
    gui.manualTriggerRequested = true;
    fig.UserData = gui;
end

function openDatasetFolder(cfg)
    try
        if ispc
            winopen(char(cfg.paths.dataDir));
        else
            system(sprintf('open "%s"', char(cfg.paths.dataDir)));
        end
    catch
        fprintf("[INFO] Dataset folder path: %s\n", cfg.paths.dataDir);
    end
end

function onQuitClick(fig)
    if isgraphics(fig)
        gui = fig.UserData;
        gui.isRunning = false;
        fig.UserData = gui;
        delete(fig);
    end
end

function appendLog(cfg, msg)
    try
        if ~isfolder(cfg.paths.logsDir)
            mkdir(cfg.paths.logsDir);
        end
        fid = fopen(cfg.paths.logFile, 'a');
        if fid ~= -1
            timeStr = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            fprintf(fid, "[%s] %s\n", timeStr, msg);
            fclose(fid);
        end
    catch
    end
end
