function gui = updateDashboard(gui, displayData, locRes, eventMeta, cfg)
% UPDATEDASHBOARD - Fast Real-Time GUI Display & Telemetry Refresh
%
% PURPOSE:
%   Updates the live oscilloscope waveforms (centered & auto-scaled),
%   polar radar compass, spatial spectrum plots, digital angle readouts,
%   and status badges.
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

    %% 1. Update Waveform Oscilloscope Traces (Centered AC & Auto-Scaled)
    if ~isempty(displayData) && isfield(gui, 'lineWaveforms')
        try
            displayData(~isfinite(displayData)) = 0.0;
            
            % Subtract DC baseline per channel so waveforms are centered at 0V
            centeredData = displayData - mean(displayData, 1);
            [N_samples, C] = size(centeredData);
            t_ms = (0 : N_samples - 1)' * (1000.0 / cfg.fs);
            
            for m = 1:min(C, numel(gui.lineWaveforms))
                if isgraphics(gui.lineWaveforms(m))
                    set(gui.lineWaveforms(m), 'XData', t_ms, 'YData', centeredData(:, m));
                end
            end
            
            % Dynamic Auto-Scaling (centered around 0V with 35% margin)
            maxAmp = max(abs(centeredData(:)));
            if isempty(maxAmp) || ~isfinite(maxAmp) || maxAmp < 0.02
                maxAmp = 0.20;
            end
            yLimVal = max(0.08, maxAmp * 1.35);
            
            if isgraphics(gui.axWaveforms)
                xlim(gui.axWaveforms, [0, max(1.0, max(t_ms))]);
                ylim(gui.axWaveforms, [-yLimVal, yLimVal]);
            end
        catch
        end
    end

    %% 2. Update Event Localization Visuals (If Event Triggered)
    if nargin >= 3 && ~isempty(locRes) && isfield(locRes, 'angle') && ~isnan(locRes.angle)
        try
            gui.eventCounter   = gui.eventCounter + 1;
            gui.lastAngle      = locRes.angle;
            gui.lastConfidence = locRes.confidence;

            % Add to history list (limited to radarHistorySize)
            newEvent = struct('angle', locRes.angle, 'conf', locRes.confidence);
            gui.historyList = [gui.historyList, newEvent];
            if numel(gui.historyList) > cfg.gui.radarHistorySize
                gui.historyList = gui.historyList(end - cfg.gui.radarHistorySize + 1 : end);
            end

            % Update 360° Polar Radar Compass with new heading & running-average arc
            if isgraphics(gui.axRadar)
                updateRadar(gui.axRadar, locRes.angle, locRes.confidence, cfg, gui.historyList);
            end

            % Update Spatial Likelihood Spectrum Plots
            if isfield(locRes, 'P_fused') && isgraphics(gui.lineFused)
                P_gcc_clean   = locRes.P_gcc;
                P_srp_clean   = locRes.P_srp;
                P_fused_clean = locRes.P_fused;
                P_gcc_clean(~isfinite(P_gcc_clean))     = 0;
                P_srp_clean(~isfinite(P_srp_clean))     = 0;
                P_fused_clean(~isfinite(P_fused_clean)) = 0;

                set(gui.lineGcc,   'YData', P_gcc_clean);
                set(gui.lineSrp,   'YData', P_srp_clean);
                set(gui.lineFused, 'YData', P_fused_clean);
                set(gui.linePeakMarker, 'XData', locRes.angle, 'YData', max(P_fused_clean));
            end

            % Update Telemetry HUD Readouts
            set(gui.txtDOA, 'String', sprintf('%0.2f°', locRes.angle));
            
            % Color-code confidence text
            if locRes.confidence >= 0.70
                confColor = [0.15, 0.95, 0.35]; % Green
            elseif locRes.confidence >= 0.40
                confColor = [1.00, 0.75, 0.10]; % Amber
            else
                confColor = [0.95, 0.30, 0.30]; % Red
            end
            set(gui.txtConf, 'String', sprintf('%0.1f%%', locRes.confidence * 100.0), ...
                             'ForegroundColor', confColor);

            snrVal = 0.0;
            if nargin >= 4 && isfield(eventMeta, 'snr_dB') && isfinite(eventMeta.snr_dB)
                snrVal = eventMeta.snr_dB;
            end
            detailStr = sprintf("Valid Pairs: %d/15  |  Latency: %0.1f ms  |  Events: %d  |  SNR: %0.1f dB", ...
                locRes.validPairs, locRes.processingTimeMs, gui.eventCounter, snrVal);
            set(gui.txtDetails, 'String', detailStr);

            % Flash Status Badge
            set(gui.statusLabel, ...
                'String', sprintf('★ EVENT #%d: DOA = %0.2f° (Conf: %0.1f%%, Latency: %0.1f ms)', ...
                                  gui.eventCounter, locRes.angle, locRes.confidence * 100, locRes.processingTimeMs), ...
                'BackgroundColor', [0.35, 0.15, 0.05], ...
                'ForegroundColor', [1.0, 0.85, 0.2]);
        catch
        end
    else
        % Reset status label to monitoring if no event in current cycle
        if ~gui.isPaused && isgraphics(gui.statusLabel)
            if isfield(cfg, 'simulationMode') && cfg.simulationMode
                set(gui.statusLabel, ...
                    'String', '⚡ MODE: SIMULATION STREAMER', ...
                    'BackgroundColor', [0.35, 0.22, 0.05], ...
                    'ForegroundColor', [1.0, 0.85, 0.2]);
            else
                set(gui.statusLabel, ...
                    'String', sprintf('● STATUS: ARMED & MONITORING (%s)', cfg.deviceName), ...
                    'BackgroundColor', [0.08, 0.14, 0.22], ...
                    'ForegroundColor', [0.2, 0.9, 0.4]);
            end
        end
    end

    % Update figure UserData and force render
    set(gui.fig, 'UserData', gui);
    drawnow limitrate;
end
