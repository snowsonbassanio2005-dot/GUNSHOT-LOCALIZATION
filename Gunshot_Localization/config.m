function cfg = config()
% CONFIG - Centralized Configuration for Gunshot Localization System
%
% PURPOSE:
%   Defines all physical constants, DAQ settings, array geometry, DSP
%   filtering parameters, detection thresholds, localization weights,
%   calibration offsets, and logging configurations.
%
% OUTPUT:
%   cfg - Structure containing complete configuration settings

    %% 1. Hardware & DAQ Parameters
    cfg.deviceName          = "Dev1";               % NI-DAQ device identifier
    cfg.channels            = 0:5;                  % Analog input channels AI0:AI5 (6 channels)
    cfg.channelNames        = "ai" + string(cfg.channels);
    cfg.fs                  = 40000;                % Sampling rate in Hz (40 kS/s per channel)
    cfg.blockSize           = 512;                  % Acquisition buffer read block size (samples)
    cfg.simulationMode      = false;                % Set true for synthetic playback, false for live NI DAQ

    %% 2. Physical Constants & Array Geometry
    cfg.c                   = 343.0;                % Speed of sound in dry air at 20°C (m/s)
    cfg.arrayRadius         = 0.13;                 % Circular array radius in meters (13 cm)
    cfg.numMics             = 6;                    % Number of microphone elements
    
    % Microphone angular layout in degrees (0° = +X, 90° = +Y, 180° = -X, 270° = -Y)
    % M6: 0°, M1: 60°, M2: 120°, M3: 180°, M4: 240°, M5: 300°
    cfg.micAnglesDeg        = [60.0; 120.0; 180.0; 240.0; 300.0; 0.0];
    cfg.micAnglesRad        = deg2rad(cfg.micAnglesDeg);
    
    % Microphone 3D Cartesian coordinates [X, Y, Z] in meters
    cfg.micPos              = [cfg.arrayRadius * cos(cfg.micAnglesRad), ...
                               cfg.arrayRadius * sin(cfg.micAnglesRad), ...
                               zeros(cfg.numMics, 1)];

    %% 3. Signal Preprocessing & Bandpass Filter
    cfg.filter.band         = [200, 4000];          % Bandpass passband [f_low, f_high] in Hz
    cfg.filter.order        = 4;                    % Butterworth filter order (zero-phase via filtfilt)
    cfg.filter.enableDC     = true;                 % Remove DC baseline offset
    cfg.filter.enableNorm   = true;                 % Channel gain balancing / normalization

    %% 4. Event Detection & Trigger Parameters (Sensitive for Easy Identification & Testing)
    cfg.trigger.multiplier         = 3.0;           % Lowered to 3.0 for sensitive detection of test impulses/claps
    cfg.trigger.peakRatio          = 3.5;           % Lowered to 3.5 for easy triggering on playback/taps
    cfg.trigger.minChannels        = 2;             % Require at least 2 channels to trigger
    cfg.trigger.minDurationSec     = 0.0001;        % 0.1 ms minimum duration
    cfg.trigger.preTriggerSec      = 0.010;         % Pre-trigger extraction window (10 ms = 400 samples)
    cfg.trigger.postTriggerSec     = 0.050;         % Post-trigger extraction window (50 ms = 2000 samples)
    cfg.trigger.cooldownSec        = 0.080;         % Cooldown timer (80 ms)
    
    % Derived sample counts
    cfg.trigger.preSamples         = round(cfg.trigger.preTriggerSec * cfg.fs);
    cfg.trigger.postSamples        = round(cfg.trigger.postTriggerSec * cfg.fs);
    cfg.trigger.eventWindowSamples = cfg.trigger.preSamples + cfg.trigger.postSamples;
    cfg.trigger.minDurationSamples = max(1, round(cfg.trigger.minDurationSec * cfg.fs));

    %% 5. Channel Timing & Gain Calibration
    cfg.calibration.channelOffsets = zeros(cfg.numMics, 1); % Calibrated timing offsets (seconds)
    cfg.calibration.gainOffsets    = ones(cfg.numMics, 1);  % Channel gain multipliers

    %% 6. Localization & Beamforming (GCC-PHAT + SRP-PHAT)
    cfg.localization.weightGCC          = 0.6;      % Weight for GCC-PHAT spatial likelihood
    cfg.localization.weightSRP          = 0.4;      % Weight for Steered Response Power (SRP-PHAT)
    cfg.localization.gridResolutionDeg  = 1.0;      % Spatial grid resolution (0:1:359 degrees)
    cfg.localization.enableContinuous   = true;     % Enable quadratic peak interpolation for sub-degree DOA
    cfg.localization.minValidPairs      = 3;        % Relaxed to 3 for robust display during testing
    cfg.localization.tdoaMarginSec      = 0.00025;  % Physical delay tolerance margin (~8.5 cm margin)
    cfg.localization.gaussianSigmaSec   = 0.00010;  % Gaussian kernel width for GCC likelihood (100 µs)

    %% 7. Visualization & GUI Settings
    cfg.gui.refreshRateHz    = 20;                  % GUI display refresh rate
    cfg.gui.waveformWindowSec= 0.100;               % Waveform display time span (100 ms)
    cfg.gui.theme            = "dark";              % Dashboard visual theme
    cfg.gui.radarHistorySize = 10;                  % Number of historical event bearings to display

    %% 8. Event Logging & Archival
    cfg.logging.baseDir      = fullfile(pwd, "events");
    cfg.logging.saveRawCsv   = true;
    cfg.logging.saveFiltCsv  = true;
    cfg.logging.saveTdoaCsv  = true;
    cfg.logging.saveSrpCsv   = true;
    cfg.logging.saveMetaJson = true;
    cfg.logging.saveImagePng = true;
end
