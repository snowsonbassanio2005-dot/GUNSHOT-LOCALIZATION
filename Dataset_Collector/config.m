function cfg = config()
% CONFIG - Central Configuration for MATLAB 6-Microphone Dataset Collector
%
% PURPOSE:
%   Defines hardware DAQ parameters, physical circular array geometry,
%   pre-computed DSP filter coefficients, circular buffer sizing,
%   impulsive detection thresholds, and storage file paths for collecting
%   labeled acoustic event datasets for Direction of Arrival (DOA) research.
%
% HARDWARE:
%   - NI DAQ-6221 (PCI/USB, Device: "Dev1")
%   - 6 Analog Input Voltage Channels: AI0, AI1, AI2, AI3, AI4, AI5
%   - 6 MAX4466 Electret Microphones with Adjustable Gain
%   - Circular Array: Radius = 13 cm (Diameter = 26 cm), 60° spacing
%
% MATLAB COMPATIBILITY:
%   Compatible with MATLAB R2020a through R2023b+ (Data Acquisition Toolbox)

    %% 1. Base Project Paths
    baseDir = fileparts(mfilename('fullpath'));
    if isempty(baseDir)
        baseDir = pwd;
    end

    cfg.paths.baseDir       = string(baseDir);
    cfg.paths.dataDir       = fullfile(cfg.paths.baseDir, "data");
    cfg.paths.recordingsDir = fullfile(cfg.paths.dataDir, "recordings");
    cfg.paths.metadataXlsx  = fullfile(cfg.paths.dataDir, "metadata.xlsx");
    cfg.paths.metadataCsv   = fullfile(cfg.paths.dataDir, "metadata.csv");
    cfg.paths.logsDir       = fullfile(cfg.paths.baseDir, "logs");
    cfg.paths.logFile       = fullfile(cfg.paths.logsDir, "session_log.txt");

    %% 2. NI DAQ & Acquisition Parameters
    cfg.deviceName          = "Dev1";         % NI-DAQ hardware device identifier (Dev1)
    cfg.channels            = 0:5;            % Analog input channels AI0:AI5 (6 synchronized channels)
    cfg.channelNames        = "ai" + string(cfg.channels);
    cfg.fs                  = 40000;          % Master sampling rate in Hz (40 kS/s per channel)
    cfg.blockSize           = 512;            % Number of samples acquired per polling cycle (~12.8 ms)
    cfg.simulationMode      = false;          % Set true for synthetic impulse simulation, false for live NI DAQ

    %% 3. Physical Array Geometry (26 cm Circular Array, 6 MAX4466 Mics)
    cfg.c                   = 343.0;          % Speed of sound in dry air at 20°C (m/s)
    cfg.arrayRadius         = 0.13;           % Circular array radius in meters (13 cm = 26 cm diameter)
    cfg.numMics             = 6;              % Number of microphone elements in circular array
    
    % Angular positions of microphones (Mic 1 at 0° East, counter-clockwise 60° increments)
    % M1: 0°, M2: 60°, M3: 120°, M4: 180°, M5: 240°, M6: 300°
    cfg.micAnglesDeg        = [0.0; 60.0; 120.0; 180.0; 240.0; 300.0];
    cfg.micAnglesRad        = deg2rad(cfg.micAnglesDeg);
    
    % 3D Cartesian coordinates [X, Y, Z] in meters relative to array center
    cfg.micPos              = [cfg.arrayRadius * cos(cfg.micAnglesRad), ...
                               cfg.arrayRadius * sin(cfg.micAnglesRad), ...
                               zeros(cfg.numMics, 1)];

    %% 4. Digital Signal Preprocessing & Bandpass Filter
    cfg.filter.band         = [200, 4000];    % Acoustic impulse frequency passband [f_low, f_high] in Hz
    cfg.filter.order        = 4;              % Butterworth bandpass filter order
    cfg.filter.enableDC     = true;           % Baseline DC bias removal via median subtraction

    % Pre-compute Butterworth filter coefficients (zero-phase filtering via filtfilt)
    nyquist = cfg.fs / 2;
    Wn = [max(1e-4, cfg.filter.band(1) / nyquist), min(0.9999, cfg.filter.band(2) / nyquist)];
    try
        [cfg.filter.b, cfg.filter.a] = butter(cfg.filter.order, Wn, 'bandpass');
    catch
        % Analytical fallback 4th-order Butterworth bandpass [200, 4000] Hz @ 40 kHz
        cfg.filter.b = [0.0039234, 0, -0.0156938, 0, 0.0235407, 0, -0.0156938, 0, 0.0039234];
        cfg.filter.a = [1.0, -6.3146, 17.5142, -27.8732, 27.8694, -17.9628, 7.2991, -1.7169, 0.1848];
    end

    %% 5. Circular Buffer Configuration
    % Buffer holds rolling multi-channel audio to allow pre-trigger retrospective capture
    cfg.buffer.durationSec  = 2.5;            % Rolling buffer capacity in seconds (2.5 s = 100,000 samples)
    cfg.buffer.capacity     = round(cfg.buffer.durationSec * cfg.fs);

    %% 6. Event Detection & Trigger Parameters (Detailed Documentation)
    %
    % PARAMETER EXPLANATIONS:
    % -------------------------------------------------------------------------
    % 1. cfg.trigger.multiplier (Default: 6.0)
    %    Controls sensitivity relative to background noise floor.
    %    Threshold = Median + Multiplier * (1.4826 * MAD).
    %    A multiplier of 6.0 ensures high immunity to ambient classroom/lab noise.
    %
    % 2. cfg.trigger.peakRatio (Default: 8.0)
    %    Impulsive ratio = Peak / ShortTimeRMS.
    %    Continuous noise (fans, speech) has low peak-to-RMS (~2-4), whereas sharp
    %    acoustic shockwaves (gunshots, slates, pops) exhibit peak-to-RMS >= 8.0.
    %
    % 3. cfg.trigger.minChannels (Default: 3)
    %    Minimum number of distinct microphones that must simultaneously detect
    %    an impulse within the physical acoustic travel window across the array.
    %    Prevents electrical noise or mechanical bumps on a single mic from triggering.
    %
    % 4. cfg.trigger.minDurationSec (Default: 0.0005 s = 0.5 ms)
    %    Ensures impulse has sufficient duration to be an authentic acoustic event
    %    rather than an instantaneous single-sample digital glitch.
    %
    % 5. cfg.trigger.preTriggerSec (Default: 0.010 s = 10 ms = 400 samples)
    %    Audio window captured BEFORE the detected peak to capture early wavefront
    %    onset, baseline silence, and initial sound pressure arrival.
    %
    % 6. cfg.trigger.postTriggerSec (Default: 0.050 s = 50 ms = 2000 samples)
    %    Audio window captured AFTER the detected peak to capture the full blast wave,
    %    decay envelope, and early room reflections for comprehensive DOA modeling.
    %
    % 7. cfg.trigger.cooldownSec (Default: 0.100 s = 100 ms)
    %    Refractory period immediately following an event where detector is blind,
    %    preventing late room reverberations from registering as duplicate triggers.
    % -------------------------------------------------------------------------
    
    cfg.trigger.multiplier         = 6.0;     % Threshold multiplier over MAD noise floor
    cfg.trigger.peakRatio          = 8.0;     % Peak-to-RMS impulsive ratio threshold
    cfg.trigger.minChannels        = 3;       % Require >= 3 coincident microphone triggers
    cfg.trigger.minDurationSec     = 0.0005;  % 0.5 ms minimum duration (20 samples @ 40 kHz)
    cfg.trigger.preTriggerSec      = 0.010;   % 10 ms pre-trigger extraction window (400 samples)
    cfg.trigger.postTriggerSec     = 0.050;   % 50 ms post-trigger extraction window (2000 samples)
    cfg.trigger.cooldownSec        = 0.100;   % 100 ms refractory cooldown period

    % Derived sample counts
    cfg.trigger.preSamples         = round(cfg.trigger.preTriggerSec * cfg.fs);  % 400 samples
    cfg.trigger.postSamples        = round(cfg.trigger.postTriggerSec * cfg.fs); % 2000 samples
    cfg.trigger.totalSamples       = cfg.trigger.preSamples + cfg.trigger.postSamples; % 2400 samples (60 ms)
    cfg.trigger.minDurationSamples = max(1, round(cfg.trigger.minDurationSec * cfg.fs)); % 20 samples

    %% 7. GUI & Visualization Settings
    cfg.gui.refreshRateHz          = 25;      % GUI oscilloscope display refresh rate (25 Hz = 40 ms)
    cfg.gui.waveformWindowSec      = 0.060;   % Oscilloscope time span (60 ms = 2400 samples)
    cfg.gui.saveToastDurationSec   = 2.0;     % Duration to show "Saved Successfully" notification (2.0 s)
end
