function [tdoa, qualities, R_corrs, lags] = estimateTDOA(data, cfg, geom)
% ESTIMATETDOA - Estimate 15 Inter-Microphone TDOAs using GCC-PHAT
%
% PURPOSE:
%   Iterates over all 15 unique microphone pairs in the 6-microphone circular array,
%   computes the sub-sample GCC-PHAT time difference of arrival (TDOA), applies
%   multiplexed ADC channel timing compensation, and computes individual pair qualities.
%
% INPUTS:
%   data - [N x 6] Synchronized, filtered audio matrix for the event window
%   cfg  - Configuration structure
%   geom - (Optional) Array geometry structure from computeGeometry(cfg)
%
% OUTPUTS:
%   tdoa      - [15 x 1] Measured TDOAs in seconds (tau_ij = t_i - t_j)
%   qualities - [15 x 1] Correlation peak quality scores [0, 1]
%   R_corrs   - [N_corr x 15] GCC-PHAT cross-correlation functions
%   lags      - [N_corr x 1] Common time lag vector in seconds
%
% MATHEMATICAL / HARDWARE COMPENSATION:
%   NI-6221 Channel Multiplexing Offset:
%     tau_corrected(k) = tau_gcc(i, j) - (Offset_i - Offset_j)

    if nargin < 3 || isempty(geom)
        geom = computeGeometry(cfg);
    end

    numPairs = geom.numPairs; % 15
    tdoa = zeros(numPairs, 1);
    qualities = zeros(numPairs, 1);

    % Channel timing calibration offsets (in seconds)
    channelOffsets = zeros(cfg.numMics, 1);
    if isfield(cfg, 'calibration') && isfield(cfg.calibration, 'channelOffsets')
        channelOffsets = cfg.calibration.channelOffsets(:);
    end

    % Pre-allocate correlation storage on first pair run
    R_corrs = [];
    lags = [];

    for k = 1:numPairs
        i = geom.pairs(k, 1);
        j = geom.pairs(k, 2);

        sig_i = data(:, i);
        sig_j = data(:, j);
        maxD = geom.maxDelays(k);

        [tau_raw, q, R_k, lags_k] = gccPhat(sig_i, sig_j, cfg.fs, maxD);

        % Apply channel timing skew compensation: tau_ij = (t_i - t_j) - (skew_i - skew_j)
        skew_ij = channelOffsets(i) - channelOffsets(j);
        tdoa(k) = tau_raw - skew_ij;
        qualities(k) = q;

        % Store correlation vectors
        if k == 1
            N_corr = numel(R_k);
            R_corrs = zeros(N_corr, numPairs);
            lags = lags_k;
        end
        if ~isempty(R_k) && numel(R_k) == size(R_corrs, 1)
            R_corrs(:, k) = R_k;
        end
    end
end
