function cfg = config()
% CONFIG - Centralized Configuration for Gunshot Localization System
%
% PURPOSE:
%   Defines all physical constants, DAQ settings, array geometry (configurable
%   Mic 1 @ 0° or Mic 6 @ 0°), DSP filtering parameters, pre-computed filter
%   coefficients, detection thresholds, and localization weights.

    %% 1. Hardware & DAQ Parameters
    cfg.deviceName          = "Dev1";               % NI-DAQ device identifier
    cfg.channels            = 0:5;                  % Analog input channels AI0:AI5 (6 channels)
    cfg.channelNames        = "ai" + string(cfg.channels);
    cfg.fs                  = 40000;                % Sampling rate in Hz (40 kS/s per channel)
    cfg.blockSize           = 512;                  % Acquisition buffer read block size (samples)
    cfg.simulationMode      = false;                % Set true for synthetic playback, false for live NI DAQ

    %% 2. Physical Constants & Array Geometry
    cfg.c                   = 343.0;                % Speed of sound in dry air at 20°C (m/s)
    cfg.arrayRadius         = 0.13;                 % Circular array radius in meters (13 cm = 26 cm diameter)
    cfg.numMics             = 6;                    % Number of microphone elements
    
    % Microphone Layout Selection:
    % Option A: "Mic1_at_0deg" -> AI0: 0°, AI1: 60°, AI2: 120°, AI3: 180°, AI4: 240°, AI5: 300°
    % Option B: "Mic6_at_0deg" -> AI0: 60°, AI1: 120°, AI2: 180°, AI3: 240°, AI4: 300°, AI5: 0°
    cfg.micLayout           = "Mic1_at_0deg";       % Default: Mic 1 (AI0) at 0° (+X / East)

    if cfg.micLayout == "Mic1_at_0deg"
        cfg.micAnglesDeg    = [0.0; 60.0; 120.0; 180.0; 240.0; 300.0];
    else
        cfg.micAnglesDeg    = [60.0; 120.0; 180.0; 240.0; 300.0; 0.0];
    end
    
    cfg.micAnglesRad        = deg2rad(cfg.micAnglesDeg);
    
    % Microphone 3D Cartesian coordinates [X, Y, Z] in meters
    cfg.micPos              = [cfg.arrayRadius * cos(cfg.micAnglesRad), ...
                               cfg.arrayRadius * sin(cfg.micAnglesRad), ...
                               zeros(cfg.numMics, 1)];

    %% 3. Signal Preprocessing & Pre-computed Bandpass Filter
    cfg.filter.band         = [200, 3800];          % Active impulse acoustic band [f_low, f_high] in Hz
    cfg.filter.order        = 4;                    % Butterworth filter order (zero-phase via filtfilt)
    cfg.filter.enableDC     = true;                 % Remove DC baseline offset
    cfg.filter.enableNorm   = true;                 % Channel gain balancing / normalization

    % Pre-compute Butterworth filter coefficients at startup (eliminates per-event design overhead)
    nyquist = cfg.fs / 2;
    Wn = [max(1e-4, cfg.filter.band(1) / nyquist), min(0.9999, cfg.filter.band(2) / nyquist)];
    try
        [cfg.filter.b, cfg.filter.a] = butter(cfg.filter.order, Wn, 'bandpass');
    catch
        % Fallback 4th-order Butterworth bandpass [200, 3800] Hz @ 40 kHz
        cfg.filter.b = [0.00336281512868239, 0, -0.01345126051472956, 0, 0.02017689077209434, 0, -0.01345126051472956, 0, 0.00336281512868239];
        cfg.filter.a = [1.0, -6.467998884146088, 18.393869706084267, -30.087944407993646, 31.001760636078178, -20.618913059361105, 8.645783486849169, -2.08936898577367, 0.222811572920135];
    end

    %% 4. Event Detection & Trigger Parameters
    cfg.trigger.multiplier         = 3.5;           % Noise floor multiplier (balanced for sensitive impulse detection)
    cfg.trigger.peakRatio          = 3.8;           % Peak-to-RMS impulsive ratio threshold
    cfg.trigger.minChannels        = 2;             % Require at least 2 channels to confirm acoustic wave
    cfg.trigger.minDurationSec     = 0.0001;        % 0.1 ms minimum duration
    cfg.trigger.preTriggerSec      = 0.010;         % Pre-trigger extraction window (10 ms = 400 samples)
    cfg.trigger.postTriggerSec     = 0.050;         % Post-trigger extraction window (50 ms = 2000 samples)
    cfg.trigger.cooldownSec        = 0.080;         % Base cooldown timer (80 ms)
    
    % Derived sample counts
    cfg.trigger.preSamples         = round(cfg.trigger.preTriggerSec * cfg.fs);
    cfg.trigger.postSamples        = round(cfg.trigger.postTriggerSec * cfg.fs);
    cfg.trigger.eventWindowSamples = cfg.trigger.preSamples + cfg.trigger.postSamples;
    cfg.trigger.minDurationSamples = max(1, round(cfg.trigger.minDurationSec * cfg.fs));

    %% 5. Channel Timing & Gain Calibration
    % NI USB-6221 multiplexed ADC inter-channel sampling skew compensation (4.167 µs per channel switch)
    muxIntervalSec = 1.0 / (cfg.fs * cfg.numMics);
    cfg.calibration.channelOffsets = (0 : cfg.numMics - 1)' * muxIntervalSec;
    cfg.calibration.gainOffsets    = ones(cfg.numMics, 1);

    %% 6. Localization & Beamforming (Regularized GCC-PHAT + Distance-Weighted SRP-PHAT)
    cfg.localization.weightGCC          = 0.4;      % Weight for GCC likelihood
    cfg.localization.weightSRP          = 0.6;      % Weight for SRP-PHAT beamformer
    cfg.localization.gridResolutionDeg  = 1.0;      % Spatial grid resolution (0:1:359 degrees)
    cfg.localization.enableContinuous   = true;     % Enable quadratic peak interpolation for sub-degree DOA
    cfg.localization.minValidPairs      = 3;        % Minimum valid pairs for confidence
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
