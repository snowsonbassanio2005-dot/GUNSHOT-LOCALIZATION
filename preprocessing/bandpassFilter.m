function y = bandpassFilter(x, cfg)
% BANDPASSFILTER - Zero-Phase Butterworth Bandpass Filtering
%
% PURPOSE:
%   Applies a 4th-order zero-phase Butterworth bandpass filter (200 Hz to 3800 Hz)
%   to isolate acoustic gunshot blast waves and suppress low-frequency environmental
%   rumble (<200 Hz) and high-frequency transducer noise (>3800 Hz).
%
% INPUTS:
%   x   - [N x C] matrix of audio samples
%   cfg - Configuration structure
%
% OUTPUT:
%   y - [N x C] filtered audio data with zero phase distortion

    if isempty(x) || size(x, 1) < 16
        y = x;
        return;
    end

    % Use pre-computed filter coefficients from config if available (fast path)
    if isfield(cfg, 'filter') && isfield(cfg.filter, 'b') && isfield(cfg.filter, 'a')
        b = cfg.filter.b;
        a = cfg.filter.a;
    else
        fs = cfg.fs;
        band = cfg.filter.band;
        order = cfg.filter.order;
        nyquist = fs / 2;
        Wn = [max(1e-4, band(1) / nyquist), min(0.9999, band(2) / nyquist)];
        [b, a] = butter(order, Wn, 'bandpass');
    end

    % Forward-backward zero-phase filtering across each column
    N = size(x, 1);
    minPad = 3 * (max(numel(b), numel(a)) - 1);

    if N > minPad
        try
            y = filtfilt(b, a, x);
        catch
            y = filter(b, a, x);
        end
    else
        y = filter(b, a, x);
    end
end
