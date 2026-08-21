function [thetaContDeg, peakValInterp] = quadraticInterpolation(P, bestIdx, azGridDeg)
% QUADRATICINTERPOLATION - Sub-Degree Continuous Direction of Arrival Estimation
%
% PURPOSE:
%   Performs continuous quadratic (parabolic) interpolation on the 360-degree
%   spatial spectrum around the discrete peak index, accounting for circular
%   wrap-around at the 0° / 360° boundary.
%
% INPUTS:
%   P          - [360 x 1] Spatial power distribution vector
%   bestIdx    - (1-based) Integer index corresponding to maximum spectrum value
%   azGridDeg  - [360 x 1] Azimuth grid angles (0:1:359)
%
% OUTPUTS:
%   thetaContDeg   - Continuous Direction of Arrival (DOA) in degrees: 0.0 <= theta < 360.0
%   peakValInterp  - Estimated peak height at the continuous maximum
%
% MATHEMATICAL DERIVATION:
%   Given 3 consecutive points: (x_0 - 1, y_m1), (x_0, y_0), (x_0 + 1, y_p1)
%   Fitting parabola y(dx) = a*dx^2 + b*dx + c:
%     a = (y_m1 - 2*y_0 + y_p1) / 2
%     b = (y_p1 - y_m1) / 2
%     c = y_0
%   Setting dy/dx = 2*a*dx + b = 0 gives peak offset:
%     dx = -b / (2*a) = (y_m1 - y_p1) / (2 * (y_m1 - 2*y_0 + y_p1))
%   Continuous Angle:
%     theta_cont = mod(x_0 + dx, 360.0)

    N = numel(P);
    if N < 3 || isempty(bestIdx)
        thetaContDeg = 0.0;
        peakValInterp = 0.0;
        return;
    end

    % Handle circular boundary wrap-around indices (1-based MATLAB indices)
    idx_m1 = mod(bestIdx - 2, N) + 1; % Left neighbor (e.g. idx 1 -> 360)
    idx_0  = bestIdx;                 % Peak
    idx_p1 = mod(bestIdx, N) + 1;     % Right neighbor (e.g. idx 360 -> 1)

    y_m1 = P(idx_m1);
    y_0  = P(idx_0);
    y_p1 = P(idx_p1);

    % Parabola curvature denominator: 2 * (y_m1 - 2*y_0 + y_p1)
    denom = 2 * (y_m1 - 2 * y_0 + y_p1);

    if abs(denom) > 1e-12
        dx = (y_m1 - y_p1) / denom;
        % Constrain interpolation to within [-0.5, +0.5] degrees
        dx = max(-0.5, min(0.5, dx));
    else
        dx = 0.0;
    end

    % Base angle at bestIdx
    if nargin >= 3 && numel(azGridDeg) == N
        baseAngle = azGridDeg(bestIdx);
    else
        baseAngle = bestIdx - 1;
    end

    % Continuous angle wrapped to [0, 360)
    thetaContDeg = mod(baseAngle + dx, 360.0);

    % Interpolated peak value
    a = (y_m1 - 2 * y_0 + y_p1) / 2;
    b = (y_p1 - y_m1) / 2;
    c = y_0;
    peakValInterp = a * (dx^2) + b * dx + c;
end
