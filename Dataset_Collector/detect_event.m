function [isTriggered, eventMeta] = detect_event(data, cfg, lastTriggerTic)
% DETECT_EVENT - Robust 7-Stage Impulsive Acoustic Event Detector
%
% PURPOSE:
%   Evaluates multi-channel acoustic signals for sharp, impulsive acoustic
%   events (e.g., gunshot playbacks, acoustic claps, spark discharges, slates)
%   using a multi-stage DSP pipeline:
%     1. DC Baseline Removal (Median Subtraction)
%     2. Bandpass Frequency Shaping (200 - 4000 Hz)
%     3. Short-Time RMS Calculation
%     4. Median Absolute Deviation (MAD) Noise Floor Estimation
%     5. Adaptive Thresholding (Multiplier = 6.0)
%     6. Peak-to-RMS Impulsive Ratio Check (Ratio >= 8.0)
%     7. Multi-Microphone Coincidence & Wavefront Travel Time Validation (>= 3 Mics)
%     8. Refractory Cooldown Enforcement (100 ms)
%
% INPUTS:
%   data           - [N x 6] Recent multi-channel audio matrix from CircularBuffer
%   cfg            - Configuration structure from config.m
%   lastTriggerTic - uint64 tic timestamp of previous trigger event (or -inf)
%
% OUTPUTS:
%   isTriggered - Boolean flag (true if authentic impulse event detected)
%   eventMeta   - Diagnostic structure containing trigger telemetry:
%                   .triggeredChannels : Number of coincident channels (>= 3)
%                   .channelMask       : [6x1] Boolean trigger status per mic
%                   .peakRatio         : Maximum Peak-to-RMS ratio observed
%                   .snr_dB            : Estimated mean SNR across triggered channels
%                   .timestamp         : Formatted string timestamp
%                   .peakSampleIdx     : Global index of impulse peak
%                   .peakAmplitudes    : [6x1] Maximum absolute voltage per mic
%                   .noiseFloors       : [6x1] Estimated noise floor per mic
%
% MATHEMATICAL / DSP FOUNDATION:
%   - Impulsive ratio: R_pk = max(|x[n]|) / RMS(x)
%     Continuous speech/music exhibits R_pk in [2.5, 4.5], whereas blast impulses
%     exhibit R_pk in [8.0, 25.0+].
%   - Scale estimation: sigma_MAD = 1.4826 * median(|x - median(x)|)
%     Yields outlier-resistant estimate of Gaussian noise standard deviation.
%   - Acoustic Travel Limit: Max delta_t between any mic pair in a circular
%     array of radius r is delta_t_max = 2*r/c (for r=0.13m, c=343m/s -> 0.758 ms = ~30 samples).

    isTriggered = false;
    eventMeta = struct( ...
        'triggeredChannels', 0, ...
        'channelMask',       false(cfg.numMics, 1), ...
        'peakRatio',         0.0, ...
        'snr_dB',            0.0, ...
        'timestamp',         "", ...
        'peakSampleIdx',     0, ...
        'peakAmplitudes',    zeros(cfg.numMics, 1), ...
        'noiseFloors',       zeros(cfg.numMics, 1));

    % 1. Verification of Input Dimensions & Minimum Sample Requirements
    if isempty(data)
        return;
    end
    [numSamples, numChannels] = size(data);
    if numChannels ~= cfg.numMics
        return;
    end

    minReqSamples = cfg.trigger.preSamples + cfg.trigger.minDurationSamples;
    if numSamples < minReqSamples
        return;
    end

    % 2. Refractory Cooldown Protection (100 ms)
    if ~isinf(lastTriggerTic) && ~isempty(lastTriggerTic)
        if toc(lastTriggerTic) < cfg.trigger.cooldownSec
            return;
        end
    end

    % 3. Stage 1: DC Baseline Removal
    centeredData = data - median(data, 1);

    % 4. Stage 2: Bandpass Filtering (200 - 4000 Hz)
    % Pre-computed filter from cfg; use pure zero-phase or standard causal filter
    filteredData = zeros(size(centeredData));
    for ch = 1:numChannels
        try
            if isfield(cfg.filter, 'b') && isfield(cfg.filter, 'a')
                % Use filtfilt if signal is long enough, otherwise filter
                if numSamples > 3 * max(numel(cfg.filter.b), numel(cfg.filter.a))
                    filteredData(:, ch) = filtfilt(cfg.filter.b, cfg.filter.a, centeredData(:, ch));
                else
                    filteredData(:, ch) = filter(cfg.filter.b, cfg.filter.a, centeredData(:, ch));
                end
            else
                filteredData(:, ch) = centeredData(:, ch);
            end
        catch
            filteredData(:, ch) = centeredData(:, ch);
        end
    end

    % 5. Stage 3: Analysis Window Extraction (Recent 25 ms = 1000 samples @ 40 kHz)
    analysisLen = min(numSamples, round(0.025 * cfg.fs));
    recentData  = filteredData(end - analysisLen + 1 : end, :);

    channelTriggered  = false(numChannels, 1);
    channelPeakRatios = zeros(numChannels, 1);
    channelSNRs       = zeros(numChannels, 1);
    channelPeakIdxs   = zeros(numChannels, 1);
    channelPeakAmps   = zeros(numChannels, 1);
    channelNoiseFloors= zeros(numChannels, 1);

    % 6. Stage 4, 5, 6: Per-Channel Statistical Noise Floor, Threshold, and Peak-to-RMS
    for ch = 1:numChannels
        fullCh     = filteredData(:, ch);
        recentCh   = recentData(:, ch);
        absRecent  = abs(recentCh);
        absFull    = abs(fullCh);

        % Stage 4: Robust MAD noise floor estimation from rolling history
        medVal = median(absFull);
        madVal = median(abs(absFull - medVal));
        noiseFloor = 1.4826 * madVal + 1e-5; % Scale factor for normal distribution
        channelNoiseFloors(ch) = noiseFloor;

        % Stage 5: Adaptive threshold calculation
        threshold = medVal + cfg.trigger.multiplier * noiseFloor;

        % Stage 6: Short-time RMS and Peak-to-RMS Impulsive Ratio
        chRMS = sqrt(mean(recentCh.^2)) + 1e-8;
        [chPeakVal, pkIdx] = max(absRecent);
        pkRatio = chPeakVal / chRMS;

        channelPeakAmps(ch)   = chPeakVal;
        channelPeakRatios(ch) = pkRatio;
        channelPeakIdxs(ch)   = pkIdx;

        % Stage 6b: Event duration verification
        % Check that transient pulse has duration >= minDurationSamples
        aboveThreshCount = sum(absRecent >= (threshold * 0.5));
        isDurationValid  = aboveThreshCount >= cfg.trigger.minDurationSamples;

        % Per-channel trigger condition
        if (chPeakVal > threshold) && (pkRatio >= cfg.trigger.peakRatio) && isDurationValid
            channelTriggered(ch) = true;
            channelSNRs(ch) = 20 * log10(max(1.0, chPeakVal / noiseFloor));
        end
    end

    activeChannelCount = sum(channelTriggered);

    % 7. Stage 7: Multi-Microphone Coincidence Voting & Wavefront Travel Time Check
    if activeChannelCount >= cfg.trigger.minChannels
        activePeaks = channelPeakIdxs(channelTriggered);
        interMicSpreadSamples = max(activePeaks) - min(activePeaks);

        % Theoretical maximum acoustic travel time across 26 cm array:
        % maxSpread = 2 * r / c = 0.26 / 343 = ~0.76 ms = ~30.3 samples @ 40 kHz
        % Add generous safety margin (2.0x + 15 samples = ~75 samples = 1.87 ms)
        maxAllowedSpread = round(2.0 * (2 * cfg.arrayRadius / cfg.c) * cfg.fs) + 15;

        if interMicSpreadSamples <= maxAllowedSpread
            isTriggered = true;
            eventMeta.triggeredChannels = activeChannelCount;
            eventMeta.channelMask       = channelTriggered;
            eventMeta.peakRatio         = max(channelPeakRatios(channelTriggered));
            eventMeta.snr_dB            = mean(channelSNRs(channelTriggered));
            eventMeta.timestamp         = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            eventMeta.peakSampleIdx     = numSamples - analysisLen + round(median(activePeaks));
            eventMeta.peakAmplitudes    = channelPeakAmps;
            eventMeta.noiseFloors       = channelNoiseFloors;
        end
    end
end
