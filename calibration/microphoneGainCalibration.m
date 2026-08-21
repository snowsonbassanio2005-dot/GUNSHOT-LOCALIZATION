function [gainOffsets, calibReport] = microphoneGainCalibration(refData, cfg)
% MICROPHONEGAINCALIBRATION - Multi-Channel Microphone Sensitivity Equalization
%
% PURPOSE:
%   Calibrates the relative gain factors across the 6 MAX4466 microphone
%   preamplifiers using a recorded acoustic calibration tone or diffuse noise field.
%   Equalizes individual channel sensitivities to avoid bias in cross-correlation.
%
% INPUTS:
%   refData - [N x 6] Multi-channel calibration audio recording
%   cfg     - Configuration structure from config.m
%
% OUTPUTS:
%   gainOffsets - [6 x 1] Multiplicative gain scaling factors
%   calibReport - Diagnostic report structure containing channel RMS levels
%
% MATHEMATICAL FORMULATION:
%   RMS_c = sqrt( (1/N) * sum_{t=1}^N x_c(t)^2 )
%   targetRMS = median(RMS)
%   gainOffset_c = targetRMS / (RMS_c + eps)

    if nargin < 2 || isempty(cfg)
        cfg = config();
    end

    numMics = cfg.numMics;

    if nargin < 1 || isempty(refData)
        fprintf("[CALIBRATION] No reference audio supplied. Using default unity gain factors.\n");
        gainOffsets = ones(numMics, 1);
        calibReport = struct('gainOffsets', gainOffsets, 'channelRMS', ones(numMics, 1));
        return;
    end

    % Preprocess
    cleanData = removeDC(refData);
    filtData  = bandpassFilter(cleanData, cfg);

    % Compute RMS energy per channel
    channelRMS = rms(filtData, 1)';
    refRMS = median(channelRMS) + 1e-12;

    % Relative gain scale factor
    gainOffsets = refRMS ./ (channelRMS + 1e-12);

    % Normalize so mean gain = 1.0
    gainOffsets = gainOffsets / mean(gainOffsets);

    calibReport = struct();
    calibReport.gainOffsets = gainOffsets;
    calibReport.channelRMS  = channelRMS;
    calibReport.timestamp   = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    % Save calibration file
    calibDir = fileparts(mfilename('fullpath'));
    calibFile = fullfile(calibDir, 'microphone_gain_cal.mat');
    save(calibFile, 'gainOffsets', 'calibReport');

    fprintf("[CALIBRATION] Microphone gain calibration completed.\n");
    for c = 1:numMics
        fprintf("              Channel AI%d Gain Multiplier: %0.4f (RMS: %0.4f V)\n", ...
            cfg.channels(c), gainOffsets(c), channelRMS(c));
    end
end
