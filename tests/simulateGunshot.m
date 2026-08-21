function [simData, t, trueDelays, trueTDOA] = simulateGunshot(sourceAngleDeg, distanceMeters, snr_dB, cfg)
% SIMULATEGUNSHOT - Physics-Based Acoustic Impulse & Array Simulation Generator
%
% PURPOSE:
%   Generates high-fidelity 6-channel acoustic waveforms representing a gunshot
%   playback impulse arriving at the 26 cm circular array from an arbitrary
%   azimuth angle with sub-sample fractional delays, spherical propagation
%   attenuation, and calibrated Gaussian noise.
%
% INPUTS:
%   sourceAngleDeg - Azimuth bearing of the acoustic source in degrees (0..360)
%   distanceMeters - Distance from array center to source (e.g. 5.0 meters)
%   snr_dB         - Signal-to-Noise Ratio in dB (e.g. 25 dB)
%   cfg            - Configuration structure from config.m
%
% OUTPUTS:
%   simData    - [N x 6] Simulated multi-channel audio matrix
%   t          - [N x 1] Time vector in seconds
%   trueDelays - [6 x 1] True time of arrival relative to coordinate center (seconds)
%   trueTDOA   - [15 x 1] True 15-pair TDOAs (seconds)

    if nargin < 4 || isempty(cfg)
        cfg = config();
    end
    if nargin < 1 || isempty(sourceAngleDeg)
        sourceAngleDeg = 45.0;
    end
    if nargin < 2 || isempty(distanceMeters)
        distanceMeters = 5.0;
    end
    if nargin < 3 || isempty(snr_dB)
        snr_dB = 25.0;
    end

    fs = cfg.fs;
    c  = cfg.c;
    numMics = cfg.numMics;

    % Source 3D coordinates
    radAng = deg2rad(sourceAngleDeg);
    sourcePos = [distanceMeters * cos(radAng), distanceMeters * sin(radAng), 0];

    % Physical distance and propagation delay to each microphone
    distances = zeros(numMics, 1);
    trueDelays = zeros(numMics, 1);
    for m = 1:numMics
        distances(m) = norm(sourcePos - cfg.micPos(m, :));
        trueDelays(m) = distances(m) / c;
    end

    % Include multiplexed ADC hardware skew
    channelOffsets = zeros(numMics, 1);
    if isfield(cfg, 'calibration') && isfield(cfg.calibration, 'channelOffsets')
        channelOffsets = cfg.calibration.channelOffsets(:);
    end
    totalDelays = trueDelays + channelOffsets;

    % Relative delays aligned so earliest mic arrives at t_lead
    t_lead = 0.015;
    relDelays = totalDelays - min(totalDelays) + t_lead;

    % Total simulation duration
    totalDur = 0.080;
    N = round(totalDur * fs);
    t = (0 : N - 1)' / fs;

    % Generate Base Friedlander Blast Wave Pulse (2.5 ms duration)
    T_blast = 0.0025;
    alpha = 2.8;
    P0 = 2.0;
    
    tBlast = (0 : 1/fs : T_blast)';
    basePulse = P0 * (1 - tBlast / T_blast) .* exp(-alpha * tBlast / T_blast);

    % Bandpass acoustic pulse (200 - 3800 Hz)
    [b, a] = butter(2, [200, 3800] / (fs/2), 'bandpass');
    filteredPulse = filter(b, a, basePulse);

    % Frequency-domain exact fractional delay synthesis
    N_fft = 2^nextpow2(N + length(filteredPulse));
    freqs = (0 : N_fft - 1)' * (fs / N_fft);
    freqs(freqs > fs/2) = freqs(freqs > fs/2) - fs;

    P_fft = fft(filteredPulse, N_fft);
    simDataClean = zeros(N, numMics);

    for m = 1:numMics
        phaseShift = exp(-1j * 2 * pi * freqs * relDelays(m));
        delayedSig = real(ifft(P_fft .* phaseShift, N_fft));
        attenuation = (distanceMeters / distances(m));
        simDataClean(:, m) = attenuation * delayedSig(1:N);
    end

    % Add Calibrated Ambient Noise Floor based on target SNR
    sigPower = mean(simDataClean(:).^2);
    noisePower = sigPower / (10^(snr_dB / 10));
    noise = sqrt(noisePower) * randn(N, numMics);

    % Add DC Bias (typical 1.65V electret preamplifier level)
    dcBias = [1.65, 1.64, 1.66, 1.65, 1.63, 1.65];
    simData = dcBias + simDataClean + noise;

    % True 15-pair TDOAs
    geom = computeGeometry(cfg);
    trueTDOA = zeros(geom.numPairs, 1);
    for k = 1:geom.numPairs
        i = geom.pairs(k, 1);
        j = geom.pairs(k, 2);
        trueTDOA(k) = trueDelays(i) - trueDelays(j);
    end
end
