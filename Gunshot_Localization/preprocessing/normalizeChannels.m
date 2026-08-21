function y = normalizeChannels(x, cfg)
% NORMALIZECHANNELS - Channel Gain Balancing and Amplitude Normalization
%
% PURPOSE:
%   Equalizes channel sensitivities using pre-calibrated gain factors and
%   normalizes signal amplitudes to [-1, +1] range. This prevents high-gain
%   channels from dominating GCC-PHAT cross-correlations or SRP power maps.
%
% INPUTS:
%   x   - [N x C] matrix of preprocessed audio signals
%   cfg - (Optional) Configuration structure containing calibration.gainOffsets
%
% OUTPUT:
%   y - [N x C] gain-balanced and peak-normalized audio signals
%
% MATHEMATICAL FORMULATION:
%   1. Gain compensation:
%        x_cal_c(t) = x_c(t) * gainOffset(c)
%   2. Robust peak normalization:
%        y_c(t) = x_cal_c(t) / (max(|x_cal|) + eps)

    if isempty(x)
        y = x;
        return;
    end

    [~, C] = size(x);

    % Apply channel gain calibration multipliers if provided
    if nargin >= 2 && isfield(cfg, 'calibration') && isfield(cfg.calibration, 'gainOffsets')
        gainVec = cfg.calibration.gainOffsets(:)';
        if numel(gainVec) == C
            x = x .* gainVec;
        end
    end

    % Normalize by overall peak amplitude across all channels
    globalPeak = max(abs(x(:)));
    if globalPeak > 1e-12
        y = x / globalPeak;
    else
        y = x;
    end
end
