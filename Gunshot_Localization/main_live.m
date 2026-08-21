% MAIN_LIVE - Master Entry Point for MATLAB Live Gunshot Localization System
%
% SYSTEM ROLE:
%   Principal Embedded Systems Engineer, Digital Signal Processing Researcher,
%   and NI DAQ Expert.
%
% PURPOSE:
%   Continuously acquires 6-channel synchronized audio from the NI DAQ-6221
%   (or high-fidelity simulation engine) connected to a 26 cm circular array
%   of 6 MAX4466 microphones. Upon detecting an acoustic impulse (gunshot playback),
%   the system extracts the synchronized pre/post-trigger window, executes
%   15-pair GCC-PHAT, enforces physical propagation constraints, performs
%   Steered Response Power (SRP-PHAT) beamforming, computes hybrid spatial fusion,
%   refines the continuous 0–360° DOA, renders live polar radar and oscilloscope
%   visualizations, and logs all telemetry and waveforms to disk.
%
% HARDWARE SETUP:
%   DAQ Card:     National Instruments NI USB-6221 (Dev1)
%   Channels:     AI0, AI1, AI2, AI3, AI4, AI5 (Single-ended / Differential)
%   Sample Rate:  40,000 Hz per channel (40 kS/s)
%   Microphones:  6 x MAX4466 Electret Microphone Amplifiers
%   Array:        Circular, 26 cm diameter (13 cm radius), 60° angular spacing:
%                 M6: 0° (+X), M1: 60°, M2: 120°, M3: 180° (-X), M4: 240°, M5: 300°

clear;
clc;
close all;

fprintf("======================================================================\n");
fprintf("     MATLAB LIVE GUNSHOT LOCALIZATION & DIRECTION TRACKING SYSTEM     \n");
fprintf("======================================================================\n\n");

%% 1. Add Submodules to Search Path
projectRoot = fileparts(mfilename('fullpath'));
if isempty(projectRoot)
    projectRoot = pwd;
end
addpath(projectRoot);
addpath(fullfile(projectRoot, 'acquisition'));
addpath(fullfile(projectRoot, 'detection'));
addpath(fullfile(projectRoot, 'preprocessing'));
addpath(fullfile(projectRoot, 'localization'));
addpath(fullfile(projectRoot, 'visualization'));
addpath(fullfile(projectRoot, 'calibration'));
addpath(fullfile(projectRoot, 'events'));
addpath(fullfile(projectRoot, 'tests'));

%% 2. Load Configuration
cfg = config();
fprintf("[CONFIG] Loaded configuration. Array Radius = %0.2f m, Fs = %d Hz\n", ...
    cfg.arrayRadius, cfg.fs);

%% 3. Initialize Acquisition (NI-DAQ or Simulation)
[dq, daqInfo] = initDAQ(cfg);
fprintf("[DAQ] %s\n", daqInfo);

%% 4. Initialize Synchronized Circular Ring Buffer
% Buffer holds 2 seconds of 6-channel audio (80,000 samples)
bufCapacity = round(2.0 * cfg.fs);
buf = CircularBuffer(bufCapacity, cfg.numMics);
fprintf("[BUFFER] Initialized 6-channel circular ring buffer (Capacity: %d samples)\n", bufCapacity);

%% 5. Initialize Live GUI Dashboard
gui = initGUI(cfg);
fprintf("[GUI] Interactive dashboard initialized. Press 'STOP & QUIT' in GUI to exit.\n\n");

%% 6. Master Acquisition & Real-Time Processing Loop
lastTriggerTic = -inf;
lastGuiRefreshTic = tic;
guiRefreshIntervalSec = 1.0 / cfg.gui.refreshRateHz; % 20 Hz = 50 ms

disp("[SYSTEM READY] Continuous acoustic monitoring armed...");

try
    while isgraphics(gui.fig) && gui.isRunning
        % Check if user paused acquisition from GUI
        if gui.isPaused
            pause(0.05);
            drawnow limitrate;
            continue;
        end

        % A. Acquire next audio block (e.g. 512 samples across 6 channels)
        [dataBlock, dq] = readBlock(dq, cfg.blockSize);

        % B. Write block to synchronized circular ring buffer
        buf.write(dataBlock);

        % C. Evaluate recent audio window for impulsive gunshot transients
        analysisWindow = buf.read(round(0.040 * cfg.fs)); % Recent 40 ms
        [isTriggered, eventMeta] = eventDetector(analysisWindow, cfg, lastTriggerTic);

        % D. Handle Detected Acoustic Event
        if isTriggered
            lastTriggerTic = tic;
            
            % 1. Extract exact synchronized event window (10 ms pre + 50 ms post = 60 ms)
            [rawWindow, isComplete] = buf.extractEventWindow(cfg.trigger.preSamples, cfg.trigger.postSamples);
            
            if isComplete && size(rawWindow, 1) >= cfg.trigger.eventWindowSamples
                % 2. Research-Grade Preprocessing Pipeline
                cleanWindow = removeDC(rawWindow);
                filtWindow  = bandpassFilter(cleanWindow, cfg);
                normWindow  = normalizeChannels(filtWindow, cfg);

                % 3. Execute Hybrid GCC-PHAT + SRP-PHAT Localization
                locRes = hybridDOA(normWindow, cfg);

                % 4. Update GUI Dashboard with Detection Telemetry
                scopeSamples = round(cfg.gui.waveformWindowSec * cfg.fs);
                gui = updateDashboard(gui, rawWindow(end - scopeSamples + 1 : end, :), locRes, eventMeta, cfg);

                % 5. Persist Event to Disk (raw, filtered, TDOA, spatial spectra, JSON, PNG)
                [eventDir, eventID] = logEvent(rawWindow, filtWindow, locRes, eventMeta, cfg, gui.fig);

                % Reset GUI refresh timer
                lastGuiRefreshTic = tic;
            end
        else
            % E. Regular Periodic Scope & Telemetry Refresh (at 20 Hz)
            if toc(lastGuiRefreshTic) >= guiRefreshIntervalSec
                scopeSamples = round(cfg.gui.waveformWindowSec * cfg.fs);
                recentScopeData = buf.read(scopeSamples);
                gui = updateDashboard(gui, recentScopeData, [], [], cfg);
                lastGuiRefreshTic = tic;
            end
        end

        % Minimal pause to yield thread execution to MATLAB GUI event queue
        drawnow limitrate;
    end

catch ME
    if isgraphics(gui.fig)
        warning("main_live:RuntimeError", "Acquisition loop encountered an exception: %s", ME.message);
    end
end

%% 7. Clean Shutdown
fprintf("\n[SHUTDOWN] Terminating system and releasing resources...\n");
stopDAQ(dq);
if isgraphics(gui.fig)
    close(gui.fig);
end
fprintf("[SHUTDOWN] System terminated successfully.\n");
