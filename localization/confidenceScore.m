function [confidence, metrics] = confidenceScore(P_fused, bestIdx, validMask, qualities, cfg)
% CONFIDENCESCORE - Multi-Factor Normalized Confidence Metric for DOA Estimation
%
% PURPOSE:
%   Computes a robust, normalized confidence score in the range [0.0, 1.0]
%   (0% to 100%) for the estimated Direction of Arrival. Fuses spatial
%   spectrum peak sharpness (PSLR), secondary mode ambiguity rejection,
%   valid microphone pair ratio, and mean GCC-PHAT correlation quality.
%
% INPUTS:
%   P_fused   - [360 x 1] Normalized fused spatial likelihood spectrum
%   bestIdx   - Integer index of the dominant spatial peak (1..360)
%   validMask - [15 x 1] Logical vector of physically valid microphone pairs
%   qualities - [15 x 1] GCC-PHAT correlation quality scores
%   cfg       - Configuration structure
%
% OUTPUTS:
%   confidence - Normalized confidence value in range [0.0, 1.0]
%   metrics    - Structure containing individual diagnostic metrics

    if nargin < 5
        cfg = config();
    end

    numPairs = numel(validMask);
    validCount = sum(validMask);
    validRatio = validCount / max(1, numPairs);

    if validCount == 0 || isempty(P_fused)
        confidence = 0.0;
        metrics = struct('peakToSidelobeRatio', 0, 'peakToMeanRatio', 0, ...
                         'validPairRatio', 0, 'meanGccQuality', 0, 'secondaryPeakAngle', 0);
        return;
    end

    % 1. Peak value and Mean of Spatial Spectrum
    peakVal = P_fused(bestIdx);
    meanVal = mean(P_fused) + 1e-12;
    peakToMean = peakVal / meanVal;

    % 2. Secondary Peak Search (outside +/- 20 degree neighborhood of primary peak)
    N = numel(P_fused);
    azGrid = (0:N-1)';
    
    neighborhoodDeg = 20;
    distFromPeak = min(abs(azGrid - (bestIdx - 1)), 360 - abs(azGrid - (bestIdx - 1)));
    sidelobeMask = distFromPeak > neighborhoodDeg;

    if any(sidelobeMask)
        [secPeakVal, secIdxLocal] = max(P_fused(sidelobeMask));
        sidelobeIndices = find(sidelobeMask);
        secIdx = sidelobeIndices(secIdxLocal);
        secAngle = secIdx - 1;
        pslr = max(0.0, (peakVal - secPeakVal) / (peakVal + 1e-6));
    else
        pslr = 1.0;
        secAngle = mod(bestIdx - 1 + 180, 360);
    end

    % 3. Mean GCC Quality of physically valid pairs
    validQualities = qualities(validMask);
    if ~isempty(validQualities)
        meanGccQual = mean(validQualities);
    else
        meanGccQual = 0.0;
    end

    % 4. Weighted Composite Confidence Score (PSLR given dominant 40% weight)
    w_pslr      = 0.40;
    w_valid     = 0.20;
    w_qual      = 0.25;
    w_peak_mean = 0.15;

    normPeakToMean = min(1.0, max(0.0, (peakToMean - 1.0) / 3.5));

    rawScore = w_pslr * pslr + ...
               w_valid * validRatio + ...
               w_qual * meanGccQual + ...
               w_peak_mean * normPeakToMean;

    % Penalty if valid pairs are below minimum threshold
    if validCount < cfg.localization.minValidPairs
        penalty = validCount / cfg.localization.minValidPairs;
        rawScore = rawScore * penalty;
    end

    confidence = min(1.0, max(0.0, rawScore));

    metrics = struct();
    metrics.peakToSidelobeRatio = pslr;
    metrics.peakToMeanRatio     = peakToMean;
    metrics.validPairRatio      = validRatio;
    metrics.meanGccQuality      = meanGccQual;
    metrics.secondaryPeakAngle  = secAngle;
end
