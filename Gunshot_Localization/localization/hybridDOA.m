function res = hybridDOA(data, cfg)
% HYBRIDDOA - Research-Grade Hybrid GCC-PHAT + SRP-PHAT Gunshot Direction Estimator
%
% PURPOSE:
%   Performs full 360-degree acoustic localization by isolating the direct-path
%   acoustic onset wavefront, computing Regularized Band-Limited GCC-PHAT across
%   all 15 microphone pairs, performing Steered Response Power (SRP-PHAT)
%   beamforming, fusing spatial likelihood distributions, and refining continuous
%   DOA via sub-degree quadratic peak interpolation.
%
% INPUTS:
%   data - [N x 6] Synchronized, preprocessed event audio matrix
%   cfg  - Configuration structure from config.m
%
% OUTPUT:
%   res - Complete localization results structure

    t_start = tic;

    if nargin < 2 || isempty(cfg)
        cfg = config();
    end

    % 1. Array Geometry & Pair Baseline Lookups
    geom = computeGeometry(cfg);

    % 2. Direct-Path Onset Windowing (Crucial for reverberant indoor environments)
    % Find global multi-channel energy peak
    energyProfile = sum(data.^2, 2);
    [~, pkIdx] = max(energyProfile);

    % Extract direct-path onset window: 4 ms pre-peak to 12 ms post-peak (16 ms total)
    N_total = size(data, 1);
    preSamples  = round(0.004 * cfg.fs); % 160 samples @ 40 kHz
    postSamples = round(0.012 * cfg.fs); % 480 samples @ 40 kHz

    startIdx = max(1, pkIdx - preSamples);
    endIdx   = min(N_total, pkIdx + postSamples);

    if (endIdx - startIdx + 1) >= round(0.008 * cfg.fs)
        onsetSignal = data(startIdx:endIdx, :);
    else
        onsetSignal = data;
    end

    % 3. 15-Pair Regularized GCC-PHAT TDOA Estimation
    [tdoa, qualities, R_corrs, lags] = estimateTDOA(onsetSignal, cfg, geom);

    % 4. Physical TDOA Constraint Validation
    [validMask, validCount, pairWeights, ~] = pairValidation(tdoa, qualities, cfg, geom);

    % 5. Steered Response Power (SRP-PHAT) Beamforming
    [P_srp, azGridDeg, ~] = srpPhat(R_corrs, lags, cfg, geom, validMask, qualities);

    % 6. GCC-PHAT Spatial Likelihood Distribution
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

    % 7. Hybrid Spatial Fusion (Default: 0.5 GCC + 0.5 SRP for optimal robustness)
    w_gcc = cfg.localization.weightGCC;
    w_srp = cfg.localization.weightSRP;
    P_fused = w_gcc * P_gcc + w_srp * P_srp;

    % Normalize fused distribution
    minFused = min(P_fused);
    maxFused = max(P_fused);
    if (maxFused - minFused) > 1e-12
        P_fused = (P_fused - minFused) / (maxFused - minFused);
    end

    % 8. Discrete Peak Search
    [~, bestIdx] = max(P_fused);
    coarseAngle = azGridDeg(bestIdx);

    % 9. Continuous Sub-Degree Quadratic Peak Interpolation
    if isfield(cfg.localization, 'enableContinuous') && cfg.localization.enableContinuous
        [estAngle, ~] = quadraticInterpolation(P_fused, bestIdx, azGridDeg);
    else
        estAngle = double(coarseAngle);
    end

    % 10. Normalized Confidence Scoring
    [confidence, ~] = confidenceScore(P_fused, bestIdx, validMask, qualities, cfg);

    % 11. Theoretical Delays and Residuals at Estimated Angle
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
