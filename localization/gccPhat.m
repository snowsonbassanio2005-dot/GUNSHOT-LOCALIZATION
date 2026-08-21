function [tau, quality, R_corr, lags] = gccPhat(x, y, fs, maxDelaySec)
% GCCPHAT - Generalized Cross-Correlation with Phase Transform & Parabolic Refinement
%
% PURPOSE:
%   Estimates the Time Difference of Arrival (TDOA) between two microphone
%   signals using Generalized Cross-Correlation with Phase Transform (GCC-PHAT)
%   and 3-point parabolic sub-sample peak interpolation.
%
% INPUTS:
%   x           - [L x 1] Audio vector from microphone 1
%   y           - [L x 1] Audio vector from microphone 2
%   fs          - Sampling rate in Hz (e.g. 40000)
%   maxDelaySec - (Optional) Maximum physical acoustic delay constraint (seconds)
%
% OUTPUTS:
%   tau     - Continuous sub-sample TDOA estimate in seconds (tau = t_x - t_y)
%   quality - Peak correlation quality score [0, 1] based on peak sharpness
%   R_corr  - [N x 1] GCC-PHAT cross-correlation function vector
%   lags    - [N x 1] Time lag vector in seconds corresponding to R_corr
%
% MATHEMATICAL FORMULATION:
%   1. Cross-Power Spectral Density:
%        X(f) = FFT(x, N),  Y(f) = FFT(y, N)
%        G_xy(f) = X(f) .* conj(Y(f))
%   2. Phase Transform (PHAT) Weighting:
%        Psi(f) = G_xy(f) ./ (|G_xy(f)| + eps)
%   3. Cross-Correlation Function:
%        R_xy(tau) = real(ifftshift(ifft(Psi(f))))
%   4. Sub-Sample Parabolic Interpolation:
%        delta = (R(k-1) - R(k+1)) / (2 * (R(k-1) - 2*R(k) + R(k+1) + eps))
%        tau = lags(k) + delta / fs

    % Ensure column vectors
    x = x(:);
    y = y(:);
    L = max(numel(x), numel(y));

    if L < 16
        tau = 0.0;
        quality = 0.0;
        R_corr = [];
        lags = [];
        return;
    end

    % Zero-pad to next power of 2 for linear convolution without circular wrap
    N = 2^nextpow2(2 * L - 1);
    if N < 2048
        N = 2048; % Minimum FFT length for high frequency resolution
    end

    % Compute FFTs and PHAT Cross-Spectrum
    X = fft(x, N);
    Y = fft(y, N);
    G_xy = X .* conj(Y);
    
    % PHAT normalization (whitening filter)
    eps_reg = 1e-10;
    Psi = G_xy ./ (abs(G_xy) + eps_reg);

    % Inverse FFT to obtain cross-correlation
    R_raw = real(ifft(Psi, N));
    R_corr = fftshift(R_raw);

    % Lag vector in seconds
    lags = ((-N/2 : N/2 - 1)') / fs;

    % Limit search to physical delay window if specified
    if nargin >= 4 && ~isempty(maxDelaySec) && maxDelaySec > 0
        searchMask = abs(lags) <= (maxDelaySec * 1.25 + 2/fs); % 25% safety margin
    else
        searchMask = true(N, 1);
    end

    % Find discrete correlation peak within search region
    R_search = R_corr;
    R_search(~searchMask) = -inf;
    [peakVal, peakIdx] = max(R_search);

    if isempty(peakIdx) || isinf(peakVal) || peakIdx <= 1 || peakIdx >= N
        tau = 0.0;
        quality = 0.0;
        return;
    end

    % 3-Point Sub-Sample Parabolic Interpolation
    % Fitting y(delta) = a*delta^2 + b*delta + c through (-1, y_m1), (0, y_0), (+1, y_p1)
    y_m1 = R_corr(peakIdx - 1);
    y_0  = R_corr(peakIdx);
    y_p1 = R_corr(peakIdx + 1);

    denom = 2 * (y_m1 - 2 * y_0 + y_p1);
    if abs(denom) > 1e-12
        delta = (y_m1 - y_p1) / denom;
        % Constrain interpolation to [-0.5, +0.5] samples
        delta = max(-0.5, min(0.5, delta));
    else
        delta = 0.0;
    end

    % Continuous delay in seconds
    tau = lags(peakIdx) + delta / fs;

    % Compute Peak Sharpness & Quality Metric
    % 1. Peak-to-Median Floor Ratio
    validR = R_corr(searchMask);
    medFloor = median(abs(validR));
    madFloor = median(abs(abs(validR) - medFloor)) + 1e-6;
    peakZScore = (peakVal - medFloor) / (1.4826 * madFloor);

    % 2. Peak-to-Secondary Peak Ratio (PSPR)
    % Exclude main peak neighborhood (+/- 3 samples)
    secondaryMask = searchMask;
    exclStart = max(1, peakIdx - 3);
    exclEnd   = min(N, peakIdx + 3);
    secondaryMask(exclStart:exclEnd) = false;
    
    if any(secondaryMask)
        secPeakVal = max(R_corr(secondaryMask));
        pspr = max(0, (peakVal - secPeakVal) / (peakVal + 1e-6));
    else
        pspr = 1.0;
    end

    % Normalized composite quality score [0, 1]
    quality = min(1.0, max(0.0, 0.5 * pspr + 0.5 * min(1.0, peakZScore / 10.0)));
end
