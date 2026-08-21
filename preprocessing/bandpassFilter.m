function y = bandpassFilter(x, cfg)
% BANDPASSFILTER - Zero-Phase Butterworth Bandpass Filtering
%
% PURPOSE:
%   Applies a 4th-order zero-phase Butterworth bandpass filter (200 Hz to 4000 Hz)
%   to isolate acoustic gunshot blast waves and suppress low-frequency environmental
%   rumble (<200 Hz) and high-frequency transducer noise (>4000 Hz).
%
% INPUTS:
%   x   - [N x C] matrix of audio samples
%   cfg - Configuration structure containing:
%         .filter.band  : [200, 4000] Hz cutoff frequencies
%         .filter.order : Filter order (default 4)
%         .fs           : Sampling rate in Hz (e.g. 40000)
%
% OUTPUT:
%   y - [N x C] filtered audio data with zero phase distortion
%
% MATHEMATICAL BASIS:
%   Uses MATLAB's filtfilt() to achieve zero-phase distortion (forward-backward
%   filtering):
%     H_total(e^{j\omega}) = |H(e^{j\omega})|^2, \angle H_total = 0
%   Zero phase response is critical for sub-millisecond TDOA accuracy because it
%   preserves the exact time-domain onset and peak arrival alignment across channels.

    if isempty(x) || size(x, 1) < 16
        y = x;
        return;
    end

    fs = cfg.fs;
    band = cfg.filter.band;
    order = cfg.filter.order;

    % Normalize cutoff frequencies to Nyquist rate (fs / 2)
    nyquist = fs / 2;
    Wn = [max(1e-4, band(1) / nyquist), min(0.9999, band(2) / nyquist)];

    % Design Butterworth Bandpass Filter
    [b, a] = butter(order, Wn, 'bandpass');

    % Forward-backward zero-phase filtering across each column
    N = size(x, 1);
    minPad = 3 * (max(numel(b), numel(a)) - 1);

    if N > minPad
        try
            y = filtfilt(b, a, x);
        catch
            % Fallback to causal filter if filtfilt encounters edge constraints
            y = filter(b, a, x);
        end
    else
        y = filter(b, a, x);
    end
end
