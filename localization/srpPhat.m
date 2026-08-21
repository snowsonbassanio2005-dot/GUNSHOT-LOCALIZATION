function [P_srp, azGridDeg, bestAngleDeg] = srpPhat(R_corrs, lags, cfg, geom, validMask, qualities)
% SRPPHAT - Steered Response Power with Phase Transform Spatial Beamformer
%
% PURPOSE:
%   Evaluates acoustic spatial energy across all azimuth angles (0° to 359°)
%   by coherently summing the Phase-Transformed cross-correlations steered
%   along the theoretical propagation delays for each microphone pair.
%   Features baseline-distance weighting (w_k = d_ij / D_max) to maximize
%   spatial sharpness and suppress room reflection sidelobes.
%
% INPUTS:
%   R_corrs   - [N_corr x 15] GCC-PHAT cross-correlation matrix
%   lags      - [N_corr x 1] Common time lag vector in seconds
%   cfg       - Configuration structure
%   geom      - Array geometry structure from computeGeometry(cfg)
%   validMask - (Optional) [15 x 1] logical vector of valid pairs
%   qualities - (Optional) [15 x 1] quality weighting vector
%
% OUTPUTS:
%   P_srp        - [360 x 1] Normalized Steered Response Power spatial profile
%   azGridDeg    - [360 x 1] Azimuth angles in degrees (0:1:359)
%   bestAngleDeg - Discrete azimuth angle corresponding to maximum SRP power

    if nargin < 4 || isempty(geom)
        geom = computeGeometry(cfg);
    end
    if nargin < 5 || isempty(validMask)
        validMask = true(geom.numPairs, 1);
    end
    if nargin < 6 || isempty(qualities)
        qualities = ones(geom.numPairs, 1);
    end

    azGridDeg = (0:359)';
    numAngles = numel(azGridDeg);
    P_srp = zeros(numAngles, 1);

    if isempty(R_corrs) || isempty(lags)
        bestAngleDeg = 0;
        return;
    end

    % Pre-computed theoretical delays: geom.tauLookups is [15 x 360]
    tauLookups = geom.tauLookups; % [15 x 360]
    validPairIndices = find(validMask);

    if isempty(validPairIndices)
        validPairIndices = 1:geom.numPairs;
    end

    lagMin = lags(1);
    dLag = lags(2) - lags(1);
    N_corr = numel(lags);
    maxD = max(geom.pairDistances); % e.g. 0.26 m

    % Vectorized accumulation across all valid pairs with distance & quality weighting
    for idx = 1:numel(validPairIndices)
        k = validPairIndices(idx);
        R_k = R_corrs(:, k);
        tau_grid = tauLookups(k, :)'; % [360 x 1]
        
        % Baseline-Distance Weight: diameter pairs (26 cm) provide 4x sharper resolution than 13 cm pairs
        distWeight = geom.pairDistances(k) / maxD;
        pairWeight = distWeight * max(0.1, qualities(k));

        % Fast linear interpolation of R_k at tau_grid
        floatIdx = (tau_grid - lagMin) / dLag + 1;
        floatIdx = max(1, min(N_corr - 1, floatIdx));
        baseIdx = floor(floatIdx);
        frac = floatIdx - baseIdx;

        interpVal = (1 - frac) .* R_k(baseIdx) + frac .* R_k(baseIdx + 1);
        P_srp = P_srp + pairWeight * interpVal;
    end

    % Min-Max normalization to [0, 1] range
    minVal = min(P_srp);
    maxVal = max(P_srp);
    if (maxVal - minVal) > 1e-12
        P_srp = (P_srp - minVal) / (maxVal - minVal);
    else
        P_srp = ones(numAngles, 1) / numAngles;
    end

    % Find peak coarse angle
    [~, maxIdx] = max(P_srp);
    bestAngleDeg = azGridDeg(maxIdx);
end
