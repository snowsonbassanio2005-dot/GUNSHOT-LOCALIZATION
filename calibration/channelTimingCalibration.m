function [channelOffsets, calibReport] = channelTimingCalibration(refData, knownAngleDeg, cfg)
% CHANNELTIMINGCALIBRATION - Multiplexed ADC Inter-Channel Delay Calibration
%
% PURPOSE:
%   Calibrates the inter-channel timing skews introduced by the NI-6221
%   multiplexed ADC architecture and cable/sensor propagation delays.
%   Uses an acoustic impulse played at a known angle (default: 0° or array center)
%   to compute optimal per-channel timing offsets via constrained least-squares.
%
% INPUTS:
%   refData       - [N x 6] Matrix of recorded calibration impulse audio
%   knownAngleDeg - Known physical bearing of the calibration impulse (degrees)
%   cfg           - Configuration structure from config.m
%
% OUTPUTS:
%   channelOffsets - [6 x 1] Vector of calibrated channel timing delays (seconds)
%   calibReport    - Structure containing calibration residuals and diagnostics
%
% MATHEMATICAL LEAST-SQUARES FORMULATION:
%   For each pair k = (i, j):
%     tau_measured(k) = tau_theor(k, theta_known) + (offset_i - offset_j) + e_k
%   Let A be the [15 x 6] difference incidence matrix: A(k, i) = +1, A(k, j) = -1.
%   Residual vector: b = tau_measured - tau_theor.
%   Solve: [A; ones(1, 6)] * offsets = [b; 0] (enforcing zero-mean baseline).
%   Solution: offsets = pinv([A; ones(1, 6)]) * [b; 0]

    if nargin < 3 || isempty(cfg)
        cfg = config();
    end
    if nargin < 2 || isempty(knownAngleDeg)
        knownAngleDeg = 0.0; % Default: source placed at 0° (+X axis)
    end

    geom = computeGeometry(cfg);
    numMics = cfg.numMics;   % 6
    numPairs = geom.numPairs; % 15

    % If no data provided, generate synthetic calibration baseline
    if nargin < 1 || isempty(refData)
        fprintf("[CALIBRATION] No reference audio supplied. Generating synthetic test impulse at %0.1f°...\n", knownAngleDeg);
        [dqSim, ~] = initDAQ(struct('simulationMode', true, 'fs', cfg.fs, 'channels', 0:5));
        % Temporarily override test angles
        dqSim.testAngles = knownAngleDeg;
        dqSim.testAngleIdx = 1;
        dqSim.nextEventTime = 0.02;
        [refData, ~] = readBlock(dqSim, round(0.08 * cfg.fs));
    end

    % Preprocess reference audio
    cleanData = removeDC(refData);
    filtData  = bandpassFilter(cleanData, cfg);

    % Measure raw TDOAs without offset compensation
    rawCfg = cfg;
    rawCfg.calibration.channelOffsets = zeros(numMics, 1);
    [tau_meas, qualities, ~, ~] = estimateTDOA(filtData, rawCfg, geom);

    % Theoretical delays for known calibration source position
    u_known = [cosd(knownAngleDeg); sind(knownAngleDeg); 0];
    tau_theor = -(geom.baselineVectors * u_known) / cfg.c;

    % Delay error vector b = tau_meas - tau_theor
    b = tau_meas - tau_theor;

    % Build [15 x 6] incidence matrix A
    A = zeros(numPairs, numMics);
    for k = 1:numPairs
        i = geom.pairs(k, 1);
        j = geom.pairs(k, 2);
        A(k, i) =  1.0;
        A(k, j) = -1.0;
    end

    % Add zero-mean constraint: sum(offsets) = 0
    A_aug = [A; ones(1, numMics)];
    b_aug = [b; 0.0];

    % Solve constrained least squares
    channelOffsets = pinv(A_aug) * b_aug;

    % Residual timing error after compensation
    tau_comp = tau_meas - A * channelOffsets;
    residualErrors = tau_comp - tau_theor;
    rmsResidualSec = sqrt(mean(residualErrors.^2));

    calibReport = struct();
    calibReport.channelOffsets = channelOffsets;
    calibReport.offsetMicroseconds = channelOffsets * 1e6;
    calibReport.rmsResidualSec = rmsResidualSec;
    calibReport.rmsResidualMicroseconds = rmsResidualSec * 1e6;
    calibReport.qualities = qualities;
    calibReport.timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    % Save calibration file to calibration directory
    calibDir = fileparts(mfilename('fullpath'));
    calibFile = fullfile(calibDir, 'channel_timing_cal.mat');
    save(calibFile, 'channelOffsets', 'calibReport');

    fprintf("[CALIBRATION] Channel timing calibration completed.\n");
    fprintf("              RMS Delay Error: %0.2f µs\n", rmsResidualSec * 1e6);
    for c = 1:numMics
        fprintf("              Channel AI%d Offset: %+0.2f µs\n", cfg.channels(c), channelOffsets(c) * 1e6);
    end
end
