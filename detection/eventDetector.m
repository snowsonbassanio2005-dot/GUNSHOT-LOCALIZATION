function [isTriggered, eventMeta] = eventDetector(data, cfg, lastTriggerTic)
% EVENTDETECTOR - Robust & Sensitive Impulsive Acoustic Event Detector
%
% PURPOSE:
%   Detects sharp acoustic impulse events (gunshot playbacks, claps, taps)
%   by comparing recent transient energy against background noise floor
%   using Median Absolute Deviation (MAD), Peak-to-RMS ratio, and multi-channel
%   coincidence voting.
%
% INPUTS:
%   data           - [N x 6] Recent audio samples from CircularBuffer
%   cfg            - Configuration structure from config.m
%   lastTriggerTic - uint64 tic timestamp of the previous trigger event (or -inf)
%
% OUTPUTS:
%   isTriggered - Boolean flag (true if valid acoustic impulse detected)
%   eventMeta   - Diagnostic structure containing trigger metadata

    isTriggered = false;
    eventMeta   = struct( ...
        'triggeredChannels', 0, ...
        'channelMask',       false(cfg.numMics, 1), ...
        'peakRatio',         0.0, ...
        'snr_dB',            0.0, ...
        'timestamp',         "", ...
        'peakSampleIdx',     0);

    % Ensure sufficient samples
    [numSamples, numChannels] = size(data);
    minReqSamples = cfg.trigger.preSamples + cfg.trigger.minDurationSamples;
    if numSamples < minReqSamples
        return;
    end

    % Refractory cooldown timer
    if ~isinf(lastTriggerTic) && ~isempty(lastTriggerTic)
        if toc(lastTriggerTic) < cfg.trigger.cooldownSec
            return;
        end
    end

    % Baseline DC centering
    centered = data - median(data, 1);

    % Analysis window: evaluate recent 25 ms
    analysisLen = min(numSamples, round(0.025 * cfg.fs)); % 25 ms = 1000 samples
    recentData  = centered(end - analysisLen + 1 : end, :);

    channelTriggered  = false(numChannels, 1);
    channelPeakRatios = zeros(numChannels, 1);
    channelSNRs       = zeros(numChannels, 1);
    channelPeakIdxs   = zeros(numChannels, 1);

    for ch = 1:numChannels
        fullCh = centered(:, ch);
        recentCh = recentData(:, ch);
        absRecent = abs(recentCh);

        % Background noise floor estimation from broader buffer history
        absFull = abs(fullCh);
        medVal = median(absFull);
        madVal = median(abs(absFull - medVal));
        noiseFloor = 1.4826 * madVal + 1e-5; % Robust scale estimator

        % Adaptive threshold: T = median + multiplier * sigma
        threshold = medVal + cfg.trigger.multiplier * noiseFloor;

        % Peak-to-RMS impulsive ratio
        chRMS = rms(recentCh) + 1e-8;
        [chPeakVal, pkIdx] = max(absRecent);
        pkRatio = chPeakVal / chRMS;

        channelPeakRatios(ch) = pkRatio;
        channelPeakIdxs(ch)   = pkIdx;

        % Check if threshold & peak ratio are satisfied
        if (chPeakVal > threshold) && (pkRatio >= cfg.trigger.peakRatio)
            channelTriggered(ch) = true;
            channelSNRs(ch) = 20 * log10(max(1.0, chPeakVal / noiseFloor));
        end
    end

    activeChannelCount = sum(channelTriggered);

    % Multi-channel coincidence voting
    if activeChannelCount >= cfg.trigger.minChannels
        activePeaks = channelPeakIdxs(channelTriggered);
        maxInterMicSampleSpread = max(activePeaks) - min(activePeaks);
        maxAllowedSpread = round(2.0 * (2 * cfg.arrayRadius / cfg.c) * cfg.fs) + 10;

        if maxInterMicSampleSpread <= maxAllowedSpread
            isTriggered = true;
            eventMeta.triggeredChannels = activeChannelCount;
            eventMeta.channelMask       = channelTriggered;
            eventMeta.peakRatio         = max(channelPeakRatios(channelTriggered));
            eventMeta.snr_dB            = mean(channelSNRs(channelTriggered));
            eventMeta.timestamp         = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            eventMeta.peakSampleIdx     = numSamples - analysisLen + round(median(activePeaks));
        end
    end
end
