function [tau, quality, R_corr, lags] = gccPhat(x, y, fs, maxDelaySec)
% GCCPHAT - Regularized Band-Limited Generalized Cross-Correlation with PHAT
%
% PURPOSE:
%   Estimates Time Difference of Arrival (TDOA) between two microphone channels
%   using Regularized Band-Limited Phase Transform (Modified GCC-PHAT) and 3-point
%   parabolic sub-sample peak refinement.
%
% WHY REGULARIZED PHAT IS CRITICAL:
%   Standard unregularized PHAT divides by (|G| + 1e-10) across all frequencies
%   up to Nyquist (20 kHz). For MAX4466 microphones, frequencies outside the
%   acoustic passband (e.g. >3500 Hz) contain only noise, which unregularized
%   PHAT amplifies by 10^10, creating random spurious correlation spikes.
%   Regularized Band-Limited PHAT restricts cross-correlation to the active
%   acoustic band (200 - 3800 Hz) and uses adaptive regularization:
%     Psi(f) = G_xy(f) / (|G_xy(f)| + gamma * mean(|G_xy|))
%   This suppresses out-of-band noise amplification and yields a sharp,
%   reliable direct-path correlation peak.
%
% INPUTS:
%   x           - [L x 1] Audio vector from microphone i
%   y           - [L x 1] Audio vector from microphone j
%   fs          - Sampling rate in Hz (e.g. 40000)
%   maxDelaySec - (Optional) Physical delay limit for peak search (seconds)
%
% OUTPUTS:
%   tau     - Continuous sub-sample TDOA in seconds (tau = t_x - t_y)
%   quality - Peak correlation quality score [0, 1]
%   R_corr  - [N x 1] GCC-PHAT cross-correlation function
%   lags    - [N x 1] Common time lag vector in seconds

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

    % Remove baseline DC
    x = x - mean(x);
    y = y - mean(y);

    % Apply smooth Tukey/Hann window to suppress FFT edge spectral leakage (zero toolbox dependency)
    Lx = numel(x);
    w = localTukeyWin(Lx, 0.15);
    x_w = x .* w;
    y_w = y .* w;

    % Zero-pad for high-resolution linear cross-correlation
    N = 2^nextpow2(2 * L - 1);
    if N < 2048
        N = 2048;
    end

    % FFTs
    X = fft(x_w, N);
    Y = fft(y_w, N);
    G_xy = X .* conj(Y);

    % Frequency vector
    freqs = (0 : N - 1)' * (fs / N);
    freqs(freqs > fs/2) = freqs(freqs > fs/2) - fs;
    absFreqs = abs(freqs);

    % In-band acoustic mask (200 Hz to 3800 Hz)
    bandMask = (absFreqs >= 200) & (absFreqs <= 3800);

    % Adaptive regularization factor (8% of mean in-band cross-spectrum)
    inBandMag = abs(G_xy(bandMask));
    if isempty(inBandMag) || all(inBandMag == 0)
        gamma = 1e-6;
    else
        gamma = 0.08 * mean(inBandMag) + 1e-10;
    end

    % Regularized PHAT weighting function (zero outside active band)
    weight = zeros(N, 1);
    weight(bandMask) = 1.0 ./ (abs(G_xy(bandMask)) + gamma);

    % Smooth band-edge roll-off (cosine taper)
    taperLow  = (absFreqs >= 200) & (absFreqs <= 400);
    taperHigh = (absFreqs >= 3200) & (absFreqs <= 3800);
    weight(taperLow)  = weight(taperLow)  .* (0.5 * (1 - cos(pi * (absFreqs(taperLow) - 200) / 200)));
    weight(taperHigh) = weight(taperHigh) .* (0.5 * (1 + cos(pi * (absFreqs(taperHigh) - 3200) / 600)));

    Psi = G_xy .* weight;

    % Inverse FFT with fftshift
    R_raw = real(ifft(Psi, N));
    R_corr = fftshift(R_raw);

    % Time lag vector in seconds
    lags = ((-N/2 : N/2 - 1)') / fs;

    % Constrain peak search to physical acoustic delay window
    if nargin >= 4 && ~isempty(maxDelaySec) && maxDelaySec > 0
        searchMargin = maxDelaySec + 0.00020; % 0.20 ms margin
        searchMask = abs(lags) <= searchMargin;
    else
        searchMask = true(N, 1);
    end

    R_search = R_corr;
    R_search(~searchMask) = -inf;
    [peakVal, peakIdx] = max(R_search);

    if isempty(peakIdx) || isinf(peakVal) || peakIdx <= 1 || peakIdx >= N
        tau = 0.0;
        quality = 0.0;
        return;
    end

    % 3-Point Sub-Sample Parabolic Interpolation
    y_m1 = R_corr(peakIdx - 1);
    y_0  = R_corr(peakIdx);
    y_p1 = R_corr(peakIdx + 1);

    denom = 2 * (y_m1 - 2 * y_0 + y_p1);
    if abs(denom) > 1e-12
        delta = (y_m1 - y_p1) / denom;
        delta = max(-0.5, min(0.5, delta));
    else
        delta = 0.0;
    end

    % Continuous delay in seconds
    tau = lags(peakIdx) + delta / fs;

    % Quality Scoring: Peak-to-Sidelobe Ratio in physical window
    searchVals = R_corr(searchMask);
    exclMask = searchMask;
    exclStart = max(1, peakIdx - 4);
    exclEnd   = min(N, peakIdx + 4);
    exclMask(exclStart:exclEnd) = false;

    if any(exclMask)
        secVal = max(R_corr(exclMask));
        pspr = max(0.0, (peakVal - secVal) / (peakVal + 1e-6));
    else
        pspr = 1.0;
    end

    medFloor = median(abs(searchVals));
    madFloor = median(abs(abs(searchVals) - medFloor)) + 1e-6;
    zScore = (peakVal - medFloor) / (1.4826 * madFloor);

    quality = min(1.0, max(0.0, 0.6 * pspr + 0.4 * min(1.0, zScore / 8.0)));
end

function w = localTukeyWin(N, r)
% Native pure-MATLAB Tukey window generator (no Signal Processing Toolbox required)
    if N <= 1
        w = ones(N, 1);
        return;
    end
    if nargin < 2 || isempty(r)
        r = 0.15;
    end
    t = (0 : N - 1)' / (N - 1);
    w = ones(N, 1);
    per = r / 2;
    tl = (t < per);
    tr = (t > (1 - per));
    if any(tl)
        w(tl) = 0.5 * (1 + cos(pi * (2 * t(tl) / r - 1)));
    end
    if any(tr)
        w(tr) = 0.5 * (1 + cos(pi * (2 * (t(tr) - 1) / r + 1)));
    end
end
