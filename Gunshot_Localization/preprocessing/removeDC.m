function y = removeDC(x)
% REMOVEDC - Channel-Wise Baseline Offset and DC Drift Removal
%
% PURPOSE:
%   Subtracts the DC bias voltage from each audio channel. MAX4466 electret
%   microphone modules operate with a quiescent DC bias (~Vcc/2 = 1.65V).
%   Removing this bias centers the acoustic waveforms at zero volts.
%
% INPUT:
%   x - [N x C] matrix of multi-channel audio data
%
% OUTPUT:
%   y - [N x C] zero-mean / zero-median centered audio matrix
%
% MATHEMATICAL FORMULATION:
%   y_c(t) = x_c(t) - (1/N) * sum_{t=1}^N x_c(t)

    if isempty(x)
        y = x;
        return;
    end

    % Subtract arithmetic mean along the time dimension (dimension 1)
    y = x - mean(x, 1);
end
