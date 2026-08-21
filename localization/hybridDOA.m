function res = hybridDOA(data, cfg, geom)
% HYBRIDDOA - Research-Grade Hybrid GCC-PHAT + SRP-PHAT Gunshot Direction Estimator
%
% PURPOSE:
%   Performs full 360-degree acoustic localization by isolating the direct-path
%   acoustic onset wavefront via earliest-arrival thresholding, computing
%   Regularized Band-Limited GCC-PHAT across all 15 microphone pairs, performing
%   Distance-Weighted SRP-PHAT beamforming, fusing spatial likelihood distributions,
%   and refining continuous DOA via sub-degree quadratic peak interpolation.
%
% INPUTS:
%   data - [N x 6] Synchronized, preprocessed event audio matrix
%   cfg  - Configuration structure from config.m
%   geom - (Optional) Pre-computed array geometry structure from computeGeometry(cfg)
%
% OUTPUT:
%   res - Complete localization results structure

    t_start = tic;

    if nargin < 2 || isempty(cfg)
        cfg = config();
    end
    if nargin < 3 || isempty(geom)
        geom = computeGeometry(cfg);
    end

    % 1. Earliest-Arrival Direct-Path Onset Windowing
    % Find first channel that crosses the impulsive threshold (direct line-of-sight wavefront)
    N_total = size(data, 1);
    numChannels = size(data, 2);
    
    firstOnsetIdx = N_total;
    foundOnset = false;
    
    for ch = 1:numChannels
        chData = abs(data(:, ch));
        chFloor = median(chData(1 : min(N_total, round(0.010 * cfg.fs)))) + 1e-5;
        chThresh = 4.0 * chFloor;
        crossings = find(chData > chThresh, 1, 'first');
        if ~isempty(crossings)
            firstOnsetIdx = min(firstOnsetIdx, crossings);
            foundOnset = true;
        end
    end

    % Fallback to energy peak if no single channel crossed early
    if ~foundOnset || firstOnsetIdx >= N_total - round(0.005 * cfg.fs)
        energyProfile = sum(data.^2, 2);
        [~, firstOnsetIdx] = max(energyProfile);
    end

    % Extract direct-path onset window: 2 ms (80 samples) before onset to 8 ms (320 samples) after onset
    preSamples  = round(0.002 * cfg.fs); % 2 ms pre-onset
    postSamples = round(0.008 * cfg.fs); % 8 ms post-onset
    startIdx = max(1, firstOnsetIdx - preSamples);
    endIdx   = min(N_total, firstOnsetIdx + postSamples);

    if (endIdx - startIdx + 1) >= round(0.006 * cfg.fs)
        onsetSignal = data(startIdx:endIdx, :);
    else
        onsetSignal = data;
    end

    % 2. 15-Pair Regularized GCC-PHAT TDOA Estimation
    [tdoa, qualities, R_corrs, lags] = estimateTDOA(onsetSignal, cfg, geom);

    % 3. Physical TDOA Constraint Validation
    [validMask, validCount, pairWeights, ~] = pairValidation(tdoa, qualities, cfg, geom);

    % 4. Distance-Weighted Steered Response Power (SRP-PHAT) Beamforming
    [P_srp, azGridDeg, ~] = srpPhat(R_corrs, lags, cfg, geom, validMask, qualities);

    % 5. GCC-PHAT Spatial Likelihood Distribution
    numAngles = numel(azGridDeg);
    P_gcc = zeros(numAngles, 1);
    sigma = cfg.localization.gaussianSigmaSec; % Gaussian kernel width (~100 µs)
    twoSigmaSq = 2 * (sigma^2);

    validIndices = find(validMask);
    if isempty(validIndices)
        validIndices = 1:geom.numPairs;
        pairWeights = ones(geom.numPairs, 1) / geom.numPairs;
    end

    tauLookups = geom.tauLookups; % [15 x 360]
    
    for idx = 1:numel(validIndices)
        k = validIndices(idx);
        tau_diff = tdoa(k) - tauLookups(k, :)'; % [360 x 1]
        gaussLikelihood = exp(- (tau_diff.^2) / twoSigmaSq);
        P_gcc = P_gcc + pairWeights(k) * gaussLikelihood;
    end

    % Min-max normalize GCC spectrum
    minGcc = min(P_gcc);
    maxGcc = max(P_gcc);
    if (maxGcc - minGcc) > 1e-12
        P_gcc = (P_gcc - minGcc) / (maxGcc - minGcc);
    else
        P_gcc = ones(numAngles, 1) / numAngles;
    end

    % 6. Hybrid Spatial Fusion (0.4 GCC + 0.6 SRP)
    w_gcc = cfg.localization.weightGCC;
    w_srp = cfg.localization.weightSRP;
    P_fused = w_gcc * P_gcc + w_srp * P_srp;

    % Normalize fused distribution
    minFused = min(P_fused);
    maxFused = max(P_fused);
    if (maxFused - minFused) > 1e-12
        P_fused = (P_fused - minFused) / (maxFused - minFused);
    end

    % 7. Discrete Peak Search
    [~, bestIdx] = max(P_fused);
    coarseAngle = azGridDeg(bestIdx);

    % 8. Continuous Sub-Degree Quadratic Peak Interpolation
    if isfield(cfg.localization, 'enableContinuous') && cfg.localization.enableContinuous
        [estAngle, ~] = quadraticInterpolation(P_fused, bestIdx, azGridDeg);
    else
        estAngle = double(coarseAngle);
    end

    % 9. Normalized Confidence Scoring
    [confidence, ~] = confidenceScore(P_fused, bestIdx, validMask, qualities, cfg);

    % 10. Theoretical Delays and Residuals at Estimated Angle
    u_est = [cosd(estAngle); sind(estAngle); 0];
    tauTheor = -(geom.baselineVectors * u_est) / cfg.c;
    tdoaResiduals = tdoa - tauTheor;

    procTimeMs = toc(t_start) * 1000.0;

    % Package Output Structure
    res = struct();
    res.angle            = estAngle;
    res.coarseAngle      = coarseAngle;
    res.confidence       = confidence;
    res.validPairs       = validCount;
    res.validMask        = validMask;
    res.processingTimeMs = procTimeMs;
    res.P_fused          = P_fused;
    res.P_gcc            = P_gcc;
    res.P_srp            = P_srp;
    res.azGridDeg        = azGridDeg;
    res.tdoa             = tdoa;
    res.tauTheor         = tauTheor;
    res.tdoaResiduals    = tdoaResiduals;
    res.qualities        = qualities;
end
