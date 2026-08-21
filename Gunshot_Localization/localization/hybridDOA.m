function res = hybridDOA(data, cfg)
% HYBRIDDOA - Research-Grade Hybrid GCC-PHAT + SRP-PHAT Gunshot Direction Estimator
%
% PURPOSE:
%   Performs full 360-degree acoustic localization by fusing multi-pair
%   GCC-PHAT TDOA likelihood with Steered Response Power (SRP-PHAT) beamforming,
%   enforcing physical propagation delay constraints, and refining the azimuth
%   estimate via continuous sub-degree quadratic peak interpolation.
%
% INPUTS:
%   data - [N x 6] Synchronized, preprocessed event audio matrix (60 ms window)
%   cfg  - Configuration structure from config.m
%
% OUTPUT:
%   res - Complete localization results structure:
%         .angle            : Continuous estimated Direction of Arrival in degrees (0.0 <= theta < 360.0)
%         .coarseAngle      : Integer grid angle in degrees (0..359)
%         .confidence       : Normalized confidence score in range [0.0, 1.0]
%         .validPairs       : Number of physically validated microphone pairs (0..15)
%         .validMask        : [15 x 1] Logical validity vector
%         .processingTimeMs : Total processing latency in milliseconds (< 50 ms budget)
%         .P_fused          : [360 x 1] Fused spatial likelihood distribution
%         .P_gcc            : [360 x 1] GCC-PHAT TDOA likelihood distribution
%         .P_srp            : [360 x 1] SRP-PHAT beamformed power distribution
%         .azGridDeg        : [360 x 1] Azimuth grid (0:1:359)
%         .tdoa             : [15 x 1] Estimated TDOAs in seconds
%         .tauTheor         : [15 x 1] Theoretical TDOAs at estimated angle
%         .tdoaResiduals    : [15 x 1] Residual TDOA errors in seconds
%         .qualities        : [15 x 1] Pair correlation quality scores
%
% MATHEMATICAL FUSION:
%   P(theta) = w_GCC * P_GCC(theta) + w_SRP * P_SRP(theta)
%   where:
%     P_GCC(theta) = sum_{k in valid} w_k * exp( - (tau_k - tau_k(theta))^2 / (2 * sigma_tau^2) )
%     P_SRP(theta) = sum_{k in valid} R_k( tau_k(theta) )

    t_start = tic;

    if nargin < 2 || isempty(cfg)
        cfg = config();
    end

    % 1. Array Geometry & Pair Baseline Lookups
    geom = computeGeometry(cfg);

    % 2. 15-Pair GCC-PHAT TDOA Estimation
    [tdoa, qualities, R_corrs, lags] = estimateTDOA(data, cfg, geom);

    % 3. Physical TDOA Constraint Validation
    [validMask, validCount, pairWeights, ~] = pairValidation(tdoa, qualities, cfg, geom);

    % 4. Steered Response Power (SRP-PHAT) Beamforming
    [P_srp, azGridDeg, ~] = srpPhat(R_corrs, lags, cfg, geom, validMask);

    % 5. GCC-PHAT Spatial Likelihood Distribution
    % P_gcc(theta) = sum_{k in valid} w_k * exp(- (tau_meas(k) - tau_theor(k, theta))^2 / (2 * sigma^2))
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

    % 6. Hybrid Spatial Fusion
    w_gcc = cfg.localization.weightGCC; % e.g. 0.6
    w_srp = cfg.localization.weightSRP; % e.g. 0.4
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
