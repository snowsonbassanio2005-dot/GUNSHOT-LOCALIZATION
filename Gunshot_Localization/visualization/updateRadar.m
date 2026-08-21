function updateRadar(radarAx, estAngleDeg, confidence, cfg, historyList)
% UPDATERADAR - Render 360° Real-Time Polar Acoustic Radar Compass
%
% PURPOSE:
%   Draws an intuitive, real-time polar radar display showing:
%   1. 360° circular grid with cardinal & intercardinal bearings
%   2. Physical 6-microphone circular array positions (M1..M6)
%   3. Dynamic Direction of Arrival (DOA) heading beam/arrow
%   4. Color-coded confidence indicator ring (Green, Amber, Red)
%   5. Faded historical gunshot event bearing blips
%
% INPUTS:
%   radarAx     - PolarAxes or standard Axes handle for radar display
%   estAngleDeg - Continuous estimated DOA in degrees (0..360)
%   confidence  - Normalized confidence score [0.0, 1.0]
%   cfg         - Configuration structure
%   historyList - (Optional) Array of past event structures: [struct('angle', a, 'conf', c), ...]

    if isempty(radarAx) || ~isgraphics(radarAx)
        return;
    end

    cla(radarAx);
    hold(radarAx, 'on');

    % Set dark radar background
    set(radarAx, 'Color', [0.07, 0.09, 0.13]);
    axis(radarAx, 'equal');
    xlim(radarAx, [-1.5, 1.5]);
    ylim(radarAx, [-1.5, 1.5]);
    radarAx.XTick = [];
    radarAx.YTick = [];
    radarAx.Box = 'off';

    % 1. Draw Range Rings & Compass Graticule
    thetaGrid = linspace(0, 2*pi, 360);
    plot(radarAx, cos(thetaGrid), sin(thetaGrid), 'Color', [0.2, 0.3, 0.45], 'LineWidth', 1.5);
    plot(radarAx, 0.5 * cos(thetaGrid), 0.5 * sin(thetaGrid), 'Color', [0.15, 0.22, 0.35], 'LineStyle', ':', 'LineWidth', 1.0);
    plot(radarAx, 1.25 * cos(thetaGrid), 1.25 * sin(thetaGrid), 'Color', [0.12, 0.18, 0.28], 'LineWidth', 1.0);

    % Draw Crosshairs (0°-180°, 90°-270°, 60°-240°, 120°-300°)
    plot(radarAx, [-1.3, 1.3], [0, 0], 'Color', [0.18, 0.25, 0.38], 'LineWidth', 1.0);
    plot(radarAx, [0, 0], [-1.3, 1.3], 'Color', [0.18, 0.25, 0.38], 'LineWidth', 1.0);
    
    % Cardinal Labels
    text(radarAx, 1.40, 0.0, "0° (+X)", 'Color', [0.7, 0.85, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, 0.0, 1.40, "90° (+Y)", 'Color', [0.7, 0.85, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, -1.40, 0.0, "180° (-X)", 'Color', [0.7, 0.85, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, 0.0, -1.40, "270° (-Y)", 'Color', [0.7, 0.85, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % 2. Draw Microphone Positions (R = 1.0 normalized)
    micAngles = cfg.micAnglesDeg;
    for m = 1:cfg.numMics
        ang = micAngles(m);
        mx = cosd(ang);
        my = sind(ang);
        plot(radarAx, mx, my, 'o', 'MarkerSize', 10, 'MarkerFaceColor', [0.2, 0.7, 1.0], 'MarkerEdgeColor', [1, 1, 1], 'LineWidth', 1.5);
        
        labelOffset = 1.15;
        text(radarAx, labelOffset * mx, labelOffset * my, sprintf("M%d (%d°)", m, ang), ...
            'Color', [0.8, 0.95, 1.0], 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end

    % 3. Draw Past Event History (Fading Blips)
    if nargin >= 5 && ~isempty(historyList)
        N_hist = numel(historyList);
        for h = 1:N_hist
            hAngle = historyList(h).angle;
            hConf  = historyList(h).conf;
            alpha = (h / N_hist) * 0.6; % Most recent is brightest
            hx = cosd(hAngle);
            hy = sind(hAngle);
            
            plot(radarAx, [0, 1.05 * hx], [0, 1.05 * hy], 'LineStyle', '--', ...
                'Color', [0.4, 0.5, 0.6, alpha], 'LineWidth', 1.2);
            plot(radarAx, 1.05 * hx, 1.05 * hy, 's', 'MarkerSize', 7, ...
                'MarkerFaceColor', [0.5, 0.6, 0.7], 'MarkerEdgeColor', 'none');
        end
    end

    % 4. Draw Current Estimated DOA Beam & Confidence Arc
    if ~isnan(estAngleDeg) && confidence > 0
        % Choose color based on confidence level
        if confidence >= 0.80
            beamColor = [0.1, 0.9, 0.3];   % Vibrant Green
            statusStr = "HIGH CONFIDENCE";
        elseif confidence >= 0.50
            beamColor = [1.0, 0.75, 0.1];  % Bright Amber
            statusStr = "MEDIUM CONFIDENCE";
        else
            beamColor = [0.95, 0.25, 0.2]; % Crimson Red
            statusStr = "LOW CONFIDENCE";
        end

        radAng = deg2rad(estAngleDeg);
        bx = cos(radAng);
        by = sin(radAng);

        % Main DOA Arrow Line
        plot(radarAx, [0, 1.15 * bx], [0, 1.15 * by], 'Color', beamColor, 'LineWidth', 3.0);
        
        % Arrowhead Cone
        arrowTip = [1.25 * bx, 1.25 * by];
        leftWing  = [1.12 * cos(radAng + deg2rad(6)), 1.12 * sin(radAng + deg2rad(6))];
        rightWing = [1.12 * cos(radAng - deg2rad(6)), 1.12 * sin(radAng - deg2rad(6))];
        patch(radarAx, [arrowTip(1), leftWing(1), rightWing(1)], ...
                       [arrowTip(2), leftWing(2), rightWing(2)], ...
                       beamColor, 'EdgeColor', [1 1 1], 'LineWidth', 1.0);

        % Uncertainty / Confidence Sector Arc (+/- 15 * (1 - confidence) degrees)
        arcSpan = max(2.0, 25.0 * (1.0 - confidence));
        arcAngles = linspace(radAng - deg2rad(arcSpan), radAng + deg2rad(arcSpan), 40);
        arcX = [0, 1.15 * cos(arcAngles), 0];
        arcY = [0, 1.15 * sin(arcAngles), 0];
        patch(radarAx, arcX, arcY, beamColor, 'FaceAlpha', 0.25, 'EdgeColor', 'none');

        % Center Radar Origin Blip
        plot(radarAx, 0, 0, 'o', 'MarkerSize', 6, 'MarkerFaceColor', beamColor, 'MarkerEdgeColor', [1 1 1]);

        % Target Text Readout Inside Radar
        text(radarAx, 0.0, -0.25, sprintf("%0.2f°", estAngleDeg), ...
            'Color', [1 1 1], 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        text(radarAx, 0.0, -0.42, sprintf("%0.1f%% Conf (%s)", confidence * 100, statusStr), ...
            'Color', beamColor, 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    else
        % Idle Scanning Radar Sweep line
        text(radarAx, 0.0, 0.0, "MONITORING", 'Color', [0.4, 0.6, 0.8], ...
            'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end

    hold(radarAx, 'off');
end
