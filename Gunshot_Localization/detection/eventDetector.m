function [isTriggered, eventMeta] = eventDetector(data, cfg, lastTriggerTic)
% EVENTDETECTOR - Robust Impulsive Acoustic Gunshot Event Detector
%
% PURPOSE:
%   Detects sharp impulsive acoustic events (gunshots/playback impulses)
%   by evaluating baseline-corrected energy, robust statistical noise floor
%   (Median Absolute Deviation - MAD), peak-to-RMS ratio, minimum pulse
%   duration, and multi-channel coincidence voting across the circular array.
%
% INPUTS:
%   data           - [N x 6] recent audio samples from CircularBuffer
%   cfg            - Configuration structure (thresholds, timings, sample rate)
%   lastTriggerTic - uint64 tic timestamp of the previous trigger event (or -inf)
%
% OUTPUTS:
%   isTriggered - Boolean flag (true if valid acoustic impulse detected)
%   eventMeta   - Structure containing trigger diagnostics:
%                 .triggeredChannels : Number of channels meeting criteria (>= 3)
%                 .channelMask       : [6 x 1] logical vector of triggering channels
%                 .peakRatio         : Maximum Peak-to-RMS energy ratio across channels
%                 .snr_dB            : Estimated impulsive SNR in decibels
%                 .timestamp         : datetime string of detection
%                 .peakSampleIdx     : Index within data window of the impulse peak
%
% MATHEMATICAL / DSP ALGORITHM:
%   1. Baseline DC Zeroing:
%        x_k(t) = data_k(t) - median(data_k)
%   2. Robust Noise Floor Estimation (MAD):
%        sigma_k = 1.4826 * median(|x_k(t) - median(x_k)|)
%   3. Adaptive Energy Threshold:
%        T_k = median(|x_k|) + cfg.trigger.multiplier * sigma_k
%   4. Impulsive Ratio Test:
%        PeakRatio_k = max(|x_k|) / (rms(x_k) + eps) > cfg.trigger.peakRatio
%   5. Temporal Coincidence:
%        At least cfg.trigger.minChannels channels must exceed threshold T_k
%        within array propagation window (tau_max = D/c = 0.76 ms).
%   6. Cooldown Refractory Guard:
%        toc(lastTriggerTic) >= cfg.trigger.cooldownSec

    isTriggered = false;
    eventMeta   = struct( ...
        'triggeredChannels', 0, ...
        'channelMask',       false(cfg.numMics, 1), ...
        'peakRatio',         0.0, ...
        'snr_dB',            0.0, ...
        'timestamp',         "", ...
        'peakSampleIdx',     0);

    % Guard: ensure sufficient samples are available
    [numSamples, numChannels] = size(data);
    minReqSamples = cfg.trigger.preSamples + cfg.trigger.minDurationSamples;
    if numSamples < minReqSamples
        return;
    end

    % Guard: refractory cooldown period to ignore reflections and reverberation
    if ~isinf(lastTriggerTic) && ~isempty(lastTriggerTic)
        if toc(lastTriggerTic) < cfg.trigger.cooldownSec
            return;
        end
    end

    % 1. Channel-wise baseline DC removal
    centered = data - median(data, 1);

    % Focus analysis on recent buffer tail (e.g. latest 20 ms window)
    analysisLen = min(numSamples, round(0.025 * cfg.fs)); % 25 ms
    recentData = centered(end - analysisLen + 1 : end, :);

    channelTriggered = false(numChannels, 1);
    channelPeakRatios = zeros(numChannels, 1);
    channelSNRs       = zeros(numChannels, 1);
    channelPeakIdxs   = zeros(numChannels, 1);

    minDurationSamples = cfg.trigger.minDurationSamples;

    for ch = 1:numChannels
        chSig = recentData(:, ch);
        absSig = abs(chSig);

        % 2. Robust noise floor estimation via MAD (Normal distribution equivalent)
        medVal = median(absSig);
        madVal = median(abs(absSig - medVal));
        noiseFloor = 1.4826 * madVal + 1e-6; % Avoid division by zero

        % 3. Adaptive threshold
        threshold = medVal + cfg.trigger.multiplier * noiseFloor;

        % 4. Peak-to-RMS ratio
        chRMS = rms(chSig) + 1e-9;
        [chPeakVal, pkIdx] = max(absSig);
        pkRatio = chPeakVal / chRMS;
        channelPeakRatios(ch) = pkRatio;
        channelPeakIdxs(ch)   = pkIdx;

        % 5. Duration check: count consecutive samples exceeding threshold
        exceedMask = (absSig > threshold);
        % Find length of longest consecutive pulse
        pulseLengths = diff([0; find(~exceedMask); numel(exceedMask) + 1]) - 1;
        maxPulseLen = 0;
        if ~isempty(pulseLengths)
            maxPulseLen = max(pulseLengths(pulseLengths > 0));
        end

        % Channel triggers if threshold, peak ratio, and duration criteria are met
        if (chPeakVal > threshold) && (pkRatio >= cfg.trigger.peakRatio) && (maxPulseLen >= minDurationSamples)
            channelTriggered(ch) = true;
            channelSNRs(ch) = 20 * log10(chPeakVal / noiseFloor);
        end
    end

    activeChannelCount = sum(channelTriggered);

    % 6. Multi-channel coincidence voting
    if activeChannelCount >= cfg.trigger.minChannels
        % Verify temporal coincidence across triggering channels (within 1.5 * array transit time)
        activePeaks = channelPeakIdxs(channelTriggered);
        maxInterMicSampleSpread = max(activePeaks) - min(activePeaks);
        maxAllowedSpread = round(1.5 * (2 * cfg.arrayRadius / cfg.c) * cfg.fs) + 5;

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
