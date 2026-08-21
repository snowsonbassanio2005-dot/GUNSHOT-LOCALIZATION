function updateRadar(radarAx, estAngleDeg, confidence, cfg, historyList)
% UPDATERADAR - Render 360° Real-Time Polar Acoustic Radar Compass
%
% PURPOSE:
%   Renders the real-time polar radar display showing:
%   1. 360° circular grid with cardinal & intercardinal bearings
%   2. Physical 6-microphone circular array positions (M1..M6 based on cfg.micAnglesDeg)
%   3. Dynamic Direction of Arrival (DOA) heading beam and directional arrow
%   4. Color-coded confidence indicator (Green = High, Amber = Medium, Red = Low)
%   5. Historical gunshot event bearing blips and running-average cluster arc
%
% INPUTS:
%   radarAx     - Standard Axes handle for radar display
%   estAngleDeg - Continuous estimated DOA in degrees (0..360, or NaN for idle)
%   confidence  - Normalized confidence score [0.0, 1.0]
%   cfg         - Configuration structure from config.m
%   historyList - (Optional) Array of past event structures: [struct('angle', a, 'conf', c), ...]

    if isempty(radarAx) || ~isgraphics(radarAx)
        return;
    end

    cla(radarAx);
    hold(radarAx, 'on');

    % Dark radar display background
    set(radarAx, 'Color', [0.06, 0.08, 0.12]);
    axis(radarAx, 'equal');
    xlim(radarAx, [-1.55, 1.55]);
    ylim(radarAx, [-1.55, 1.55]);
    radarAx.XTick = [];
    radarAx.YTick = [];
    radarAx.Box = 'off';

    % 1. Draw Range Rings & Circular Graticules
    thetaGrid = linspace(0, 2*pi, 360);
    plot(radarAx, cos(thetaGrid), sin(thetaGrid), 'Color', [0.20, 0.35, 0.50], 'LineWidth', 1.8);
    plot(radarAx, 0.5 * cos(thetaGrid), 0.5 * sin(thetaGrid), 'Color', [0.15, 0.25, 0.38], 'LineStyle', ':', 'LineWidth', 1.0);
    plot(radarAx, 1.25 * cos(thetaGrid), 1.25 * sin(thetaGrid), 'Color', [0.12, 0.20, 0.30], 'LineWidth', 1.0);

    % Draw Crosshairs (0°-180°, 90°-270°)
    plot(radarAx, [-1.35, 1.35], [0, 0], 'Color', [0.18, 0.28, 0.40], 'LineWidth', 1.0);
    plot(radarAx, [0, 0], [-1.35, 1.35], 'Color', [0.18, 0.28, 0.40], 'LineWidth', 1.0);
    
    % Cardinal Labels (0° = +X / East, 90° = +Y / North, 180° = -X / West, 270° = -Y / South)
    text(radarAx, 1.42, 0.0, "0° (+X)", 'Color', [0.75, 0.88, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, 0.0, 1.42, "90° (+Y)", 'Color', [0.75, 0.88, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, -1.42, 0.0, "180° (-X)", 'Color', [0.75, 0.88, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(radarAx, 0.0, -1.42, "270° (-Y)", 'Color', [0.75, 0.88, 1.0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % 2. Draw Physical Microphone Positions (Dynamically from cfg.micAnglesDeg)
    micAngles = cfg.micAnglesDeg;
    for m = 1:cfg.numMics
        ang = micAngles(m);
        mx = cosd(ang);
        my = sind(ang);
        plot(radarAx, mx, my, 'o', 'MarkerSize', 10, 'MarkerFaceColor', [0.2, 0.75, 1.0], ...
            'MarkerEdgeColor', [1.0, 1.0, 1.0], 'LineWidth', 1.5);
        
        labelOffset = 1.15;
        text(radarAx, labelOffset * mx, labelOffset * my, sprintf("M%d (%d°)", m, round(ang)), ...
            'Color', [0.85, 0.95, 1.0], 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end

    % 3. Draw Past Event History Blips & Running Average Arc
    if nargin >= 5 && ~isempty(historyList)
        N_hist = numel(historyList);
        recentAngles = zeros(N_hist, 1);
        for h = 1:N_hist
            hAngle = historyList(h).angle;
            recentAngles(h) = hAngle;
            hx = cosd(hAngle);
            hy = sind(hAngle);
            
            histColor = [0.45, 0.55, 0.65];
            plot(radarAx, [0, 1.05 * hx], [0, 1.05 * hy], 'LineStyle', '--', ...
                'Color', histColor, 'LineWidth', 1.2);
            plot(radarAx, 1.05 * hx, 1.05 * hy, 's', 'MarkerSize', 6, ...
                'MarkerFaceColor', histColor, 'MarkerEdgeColor', 'none');
        end

        % If 3+ consecutive events occurred in close proximity (+/- 15 deg), draw running average cluster arc
        if N_hist >= 3
            last3 = recentAngles(max(1, N_hist - 2) : N_hist);
            % Circular mean for last 3
            meanSin = mean(sind(last3));
            meanCos = mean(cosd(last3));
            avgBearing = mod(atan2d(meanSin, meanCos), 360.0);
            circStd = sqrt(-2 * log(max(1e-4, sqrt(meanSin^2 + meanCos^2)))) * (180/pi);
            
            if circStd <= 15.0
                clusterArc = linspace(deg2rad(avgBearing - circStd), deg2rad(avgBearing + circStd), 25);
                plot(radarAx, 1.25 * cos(clusterArc), 1.25 * sin(clusterArc), ...
                    'Color', [0.2, 0.95, 0.4], 'LineWidth', 3.0);
            end
        end
    end

    % 4. Draw Current Estimated Direction (DOA Beam & Directional Needle)
    if ~isnan(estAngleDeg)
        if nargin < 3 || isempty(confidence) || isnan(confidence)
            confidence = 0.50;
        end
        confidence = max(0.05, min(1.0, confidence));

        % Confidence-based color scheme
        if confidence >= 0.70
            beamColor = [0.15, 0.95, 0.35]; % Bright Green (High confidence)
            statusStr = "HIGH";
        elseif confidence >= 0.40
            beamColor = [1.00, 0.75, 0.10]; % Amber (Medium confidence)
            statusStr = "MEDIUM";
        else
            beamColor = [0.95, 0.25, 0.25]; % Red (Low confidence)
            statusStr = "LOW";
        end

        radAng = deg2rad(estAngleDeg);
        bx = cos(radAng);
        by = sin(radAng);

        % Main DOA Heading Line
        plot(radarAx, [0, 1.18 * bx], [0, 1.18 * by], 'Color', beamColor, 'LineWidth', 3.5);
        
        % Arrowhead Cone
        arrowTip  = [1.28 * bx, 1.28 * by];
        leftWing  = [1.12 * cos(radAng + deg2rad(8)), 1.12 * sin(radAng + deg2rad(8))];
        rightWing = [1.12 * cos(radAng - deg2rad(8)), 1.12 * sin(radAng - deg2rad(8))];
        patch(radarAx, [arrowTip(1), leftWing(1), rightWing(1)], ...
                       [arrowTip(2), leftWing(2), rightWing(2)], ...
                       beamColor, 'EdgeColor', [1 1 1], 'LineWidth', 1.2);

        % Uncertainty / Confidence Sector Arc
        arcSpan = max(3.0, 30.0 * (1.0 - confidence));
        arcAngles = linspace(radAng - deg2rad(arcSpan), radAng + deg2rad(arcSpan), 40);
        arcX = [0, 1.15 * cos(arcAngles), 0];
        arcY = [0, 1.15 * sin(arcAngles), 0];
        patch(radarAx, arcX, arcY, beamColor, 'FaceAlpha', 0.25, 'EdgeColor', 'none');

        % Center Origin Node
        plot(radarAx, 0, 0, 'o', 'MarkerSize', 7, 'MarkerFaceColor', beamColor, 'MarkerEdgeColor', [1 1 1]);

        % Prominent Digital Readouts inside Radar Display
        text(radarAx, 0.0, -0.22, sprintf("%0.2f°", estAngleDeg), ...
            'Color', [1.0, 1.0, 1.0], 'FontSize', 15, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        text(radarAx, 0.0, -0.40, sprintf("CONF: %0.1f%% (%s)", confidence * 100, statusStr), ...
            'Color', beamColor, 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    else
        % Idle Armed State
        text(radarAx, 0.0, 0.0, "MONITORING", 'Color', [0.4, 0.65, 0.85], ...
            'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end

    hold(radarAx, 'off');
end
