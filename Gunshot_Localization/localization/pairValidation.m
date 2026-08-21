function [validMask, validCount, weights, diagnostics] = pairValidation(tdoa, qualities, cfg, geom)
% PAIRVALIDATION - Physical TDOA Constraint and Triplet Consistency Validation
%
% PURPOSE:
%   Evaluates physical feasibility of the 15 measured TDOAs by enforcing:
%   1. Speed-of-Sound Physical Limit: |tau_ij| <= d_ij / c + margin
%   2. Quality Score Thresholding: quality_ij >= minQuality
%   3. Cyclic Triplet Consistency: tau_ij + tau_jk - tau_ik approx 0
%
% INPUTS:
%   tdoa      - [15 x 1] Measured TDOAs in seconds
%   qualities - [15 x 1] GCC-PHAT peak quality scores [0, 1]
%   cfg       - Configuration structure
%   geom      - Array geometry structure from computeGeometry(cfg)
%
% OUTPUTS:
%   validMask   - [15 x 1] Logical vector (true = valid, false = rejected)
%   validCount  - Number of valid pairs (0 to 15)
%   weights     - [15 x 1] Quality-weighted reliability vector for valid pairs
%   diagnostics - Structure containing detailed pair validation stats

    if nargin < 4 || isempty(geom)
        geom = computeGeometry(cfg);
    end

    numPairs = geom.numPairs; % 15
    validMask = true(numPairs, 1);
    
    % Margin to allow for finite SNR, acoustic wave distortion, and sampling jitter
    marginSec = cfg.localization.tdoaMarginSec; % e.g. 0.15 ms (~5 cm)

    % 1. Physical Delay Boundary Test: |tau| <= maxDelay + margin
    for k = 1:numPairs
        maxAllowable = geom.maxDelays(k) + marginSec;
        if abs(tdoa(k)) > maxAllowable
            validMask(k) = false;
        end
    end

    % 2. Quality Score Test
    minQualityThresh = 0.15;
    for k = 1:numPairs
        if qualities(k) < minQualityThresh
            validMask(k) = false;
        end
    end

    % 3. Cyclic Triplet Consistency Check: tau_12 + tau_23 = tau_13
    % Build a quick pair-index lookup table for (i, j)
    pairIndexMap = zeros(geom.numMics, geom.numMics);
    for k = 1:numPairs
        i = geom.pairs(k, 1);
        j = geom.pairs(k, 2);
        pairIndexMap(i, j) = k;   % tau_ij
        pairIndexMap(j, i) = -k;  % tau_ji = -tau_ij
    end

    % Check all triplets
    tripletErrors = zeros(numPairs, 1);
    tripletCounts = zeros(numPairs, 1);
    allTriplets = nchoosek(1:geom.numMics, 3);
    
    for t = 1:size(allTriplets, 1)
        m1 = allTriplets(t, 1);
        m2 = allTriplets(t, 2);
        m3 = allTriplets(t, 3);

        k12 = pairIndexMap(m1, m2);
        k23 = pairIndexMap(m2, m3);
        k13 = pairIndexMap(m1, m3);

        t12 = sign(k12) * tdoa(abs(k12));
        t23 = sign(k23) * tdoa(abs(k23));
        t13 = sign(k13) * tdoa(abs(k13));

        % Cyclic residual: tau_12 + tau_23 - tau_13 should be near zero
        closureError = abs((t12 + t23) - t13);

        % Accumulate errors for each participating pair
        tripletErrors(abs(k12)) = tripletErrors(abs(k12)) + closureError;
        tripletCounts(abs(k12)) = tripletCounts(abs(k12)) + 1;
        
        tripletErrors(abs(k23)) = tripletErrors(abs(k23)) + closureError;
        tripletCounts(abs(k23)) = tripletCounts(abs(k23)) + 1;
        
        tripletErrors(abs(k13)) = tripletErrors(abs(k13)) + closureError;
        tripletCounts(abs(k13)) = tripletCounts(abs(k13)) + 1;
    end

    meanTripletErr = tripletErrors ./ max(1, tripletCounts);
    maxAllowedClosure = 2 * marginSec;

    for k = 1:numPairs
        if validMask(k) && meanTripletErr(k) > maxAllowedClosure
            % Downweight or invalidate if triplet loop closure fails heavily
            if meanTripletErr(k) > 3 * maxAllowedClosure
                validMask(k) = false;
            end
        end
    end

    validCount = sum(validMask);

    % Compute pair weights combining GCC peak quality and triplet consistency
    weights = zeros(numPairs, 1);
    for k = 1:numPairs
        if validMask(k)
            consistencyFactor = exp(- (meanTripletErr(k) / (marginSec + 1e-6))^2);
            weights(k) = max(0.01, qualities(k) * consistencyFactor);
        end
    end

    % Normalize weights
    if sum(weights) > 0
        weights = weights / sum(weights);
    end

    diagnostics = struct();
    diagnostics.validMask = validMask;
    diagnostics.validCount = validCount;
    diagnostics.qualities = qualities;
    diagnostics.meanTripletErr = meanTripletErr;
    diagnostics.weights = weights;
end
