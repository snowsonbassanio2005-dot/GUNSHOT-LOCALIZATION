function gui = updateDashboard(gui, displayData, locRes, eventMeta, cfg)
% UPDATEDASHBOARD - Fast Real-Time GUI Display & Telemetry Refresh
%
% PURPOSE:
%   Updates the live oscilloscope waveforms, polar radar compass, spatial
%   spectrum plots, digital angle readouts, and status badges.
%
% INPUTS:
%   gui         - GUI handles structure from initGUI()
%   displayData - [M x 6] Recent multi-channel audio data to display on scope
%   locRes      - (Optional) Localization results struct from hybridDOA()
%   eventMeta   - (Optional) Event detector metadata from eventDetector()
%   cfg         - Configuration structure
%
% OUTPUT:
%   gui - Updated GUI state structure

    if isempty(gui) || ~isfield(gui, 'fig') || ~isgraphics(gui.fig)
        return;
    end

    % Retrieve latest state from figure UserData in case buttons were clicked
    latestUserData = get(gui.fig, 'UserData');
    if ~isempty(latestUserData)
        gui.isRunning      = latestUserData.isRunning;
        gui.isPaused       = latestUserData.isPaused;
        gui.historyList    = latestUserData.historyList;
        gui.lastAngle      = latestUserData.lastAngle;
        gui.lastConfidence = latestUserData.lastConfidence;
        gui.cfg            = latestUserData.cfg;
    end

    %% 1. Update Waveform Oscilloscope Traces
    if ~isempty(displayData) && isfield(gui, 'lineWaveforms')
        [N_samples, C] = size(displayData);
        t_ms = (0 : N_samples - 1)' * (1000.0 / cfg.fs);
        
        for m = 1:min(C, numel(gui.lineWaveforms))
            if isgraphics(gui.lineWaveforms(m))
                set(gui.lineWaveforms(m), 'XData', t_ms, 'YData', displayData(:, m));
            end
        end
        
        % Auto-scale waveform axes
        maxAmp = max(abs(displayData(:)));
        yLimVal = max(0.15, maxAmp * 1.20);
        if isgraphics(gui.axWaveforms)
            xlim(gui.axWaveforms, [0, max(t_ms)]);
            ylim(gui.axWaveforms, [-yLimVal, yLimVal]);
        end
    end

    %% 2. Update Event Localization Visuals (If Event Triggered)
    if nargin >= 3 && ~isempty(locRes) && isfield(locRes, 'angle') && ~isnan(locRes.angle)
        gui.eventCounter   = gui.eventCounter + 1;
        gui.lastAngle      = locRes.angle;
        gui.lastConfidence = locRes.confidence;

        % Add to history list (limited to radarHistorySize)
        newEvent = struct('angle', locRes.angle, 'conf', locRes.confidence);
        gui.historyList = [gui.historyList, newEvent];
        if numel(gui.historyList) > cfg.gui.radarHistorySize
            gui.historyList = gui.historyList(end - cfg.gui.radarHistorySize + 1 : end);
        end

        % Update 360° Polar Radar Compass with new heading
        updateRadar(gui.axRadar, locRes.angle, locRes.confidence, cfg, gui.historyList);

        % Update Spatial Likelihood Spectrum Plots
        if isfield(locRes, 'P_fused') && isgraphics(gui.lineFused)
            set(gui.lineGcc,   'YData', locRes.P_gcc);
            set(gui.lineSrp,   'YData', locRes.P_srp);
            set(gui.lineFused, 'YData', locRes.P_fused);
            set(gui.linePeakMarker, 'XData', locRes.angle, 'YData', max(locRes.P_fused));
        end

        % Update Telemetry HUD Readouts
        set(gui.txtDOA, 'String', sprintf('%0.2f°', locRes.angle));
        
        % Color-code confidence text
        if locRes.confidence >= 0.75
            confColor = [0.15, 0.95, 0.35]; % Green
        elseif locRes.confidence >= 0.45
            confColor = [1.00, 0.75, 0.10]; % Amber
        else
            confColor = [0.95, 0.30, 0.30]; % Red
        end
        set(gui.txtConf, 'String', sprintf('%0.1f%%', locRes.confidence * 100.0), ...
                         'ForegroundColor', confColor);

        detailStr = sprintf("Valid Pairs: %d/15  |  Latency: %0.1f ms  |  Events: %d  |  SNR: %0.1f dB", ...
            locRes.validPairs, locRes.processingTimeMs, gui.eventCounter, eventMeta.snr_dB);
        set(gui.txtDetails, 'String', detailStr);

        % Flash Status Badge
        set(gui.statusLabel, ...
            'String', sprintf('★ EVENT #%d: DOA = %0.2f° (Conf: %0.1f%%, Latency: %0.1f ms)', ...
                              gui.eventCounter, locRes.angle, locRes.confidence * 100, locRes.processingTimeMs), ...
            'BackgroundColor', [0.35, 0.15, 0.05], ...
            'ForegroundColor', [1.0, 0.85, 0.2]);
    else
        % Reset status label to monitoring if no event in current cycle
        if ~gui.isPaused && isgraphics(gui.statusLabel)
            set(gui.statusLabel, ...
                'String', sprintf('● STATUS: ARMED & MONITORING (40 kS/s) | Device: %s', cfg.deviceName), ...
                'BackgroundColor', [0.08, 0.14, 0.22], ...
                'ForegroundColor', [0.2, 0.9, 0.4]);
        end
    end

    % Update figure UserData and force render
    set(gui.fig, 'UserData', gui);
    drawnow limitrate;
end
