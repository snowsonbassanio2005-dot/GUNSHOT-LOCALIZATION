function geom = computeGeometry(cfg)
% COMPUTEGEOMETRY - Compute Circular Microphone Array Geometry and Pair Baselines
%
% PURPOSE:
%   Computes physical positions, baseline vectors, inter-microphone distances,
%   maximum theoretical acoustic travel delays (tau_max = d / c), and the 15
%   unique sensor pairs for the 6-microphone circular array.
%
% INPUT:
%   cfg - Configuration structure from config.m:
%         .numMics     : 6
%         .arrayRadius : 0.13 m (13 cm radius, 26 cm diameter)
%         .c           : 343.0 m/s
%         .micPos      : [6 x 3] matrix of coordinates [x, y, z] in meters
%
% OUTPUT:
%   geom - Structure containing:
%          .pairs           : [15 x 2] unique microphone index pairs (nchoosek(1:6, 2))
%          .numPairs        : 15
%          .micPos          : [6 x 3] microphone coordinates
%          .baselineVectors : [15 x 3] baseline vectors (p_i - p_j)
%          .pairDistances   : [15 x 1] euclidean baseline distances d_ij (meters)
%          .maxDelays       : [15 x 1] maximum theoretical time delays d_ij / c (seconds)
%          .tauLookups      : [15 x 360] theoretical TDOA matrix for all azimuths 0:1:359°
%
% ARRAY LAYOUT:
%   Diameter = 26 cm, Radius = 13 cm. Microphones face outwards:
%     Mic 6: 0°   (+X axis) -> [0.130,  0.000, 0]
%     Mic 1: 60°  (Quad 1)  -> [0.065,  0.113, 0]
%     Mic 2: 120° (Quad 2)  -> [-0.065, 0.113, 0]
%     Mic 3: 180° (-X axis) -> [-0.130, 0.000, 0]
%     Mic 4: 240° (Quad 3)  -> [-0.065,-0.113, 0]
%     Mic 5: 300° (Quad 4)  -> [0.065, -0.113, 0]

    if nargin < 1 || isempty(cfg)
        cfg = config();
    end

    geom = struct();
    geom.numMics  = cfg.numMics;
    geom.micPos   = cfg.micPos;
    geom.c        = cfg.c;
    
    % Generate all 15 unique microphone pairs: nchoosek(1:6, 2)
    geom.pairs    = nchoosek(1:geom.numMics, 2);
    geom.numPairs = size(geom.pairs, 1); % 15 pairs

    geom.baselineVectors = zeros(geom.numPairs, 3);
    geom.pairDistances   = zeros(geom.numPairs, 1);
    geom.maxDelays       = zeros(geom.numPairs, 1);

    for k = 1:geom.numPairs
        i = geom.pairs(k, 1);
        j = geom.pairs(k, 2);
        
        % Vector pointing from Mic j to Mic i: p_i - p_j
        d_vec = geom.micPos(i, :) - geom.micPos(j, :);
        d_norm = norm(d_vec);
        
        geom.baselineVectors(k, :) = d_vec;
        geom.pairDistances(k)      = d_norm;
        geom.maxDelays(k)          = d_norm / geom.c;
    end

    % Pre-compute theoretical TDOA grid for all integer azimuth angles 0°..359°
    azGridDeg = 0:359;
    azGridRad = deg2rad(azGridDeg);
    % Unit direction vectors pointing toward acoustic source: u = [cos(theta), sin(theta), 0]
    uGrid = [cos(azGridRad); sin(azGridRad); zeros(1, 360)]; % [3 x 360]
    
    % Theoretical TDOA: tau_ij(theta) = - ( (p_i - p_j) . u(theta) ) / c
    % geom.baselineVectors is [15 x 3], uGrid is [3 x 360] -> result is [15 x 360]
    geom.tauLookups = -(geom.baselineVectors * uGrid) / geom.c;
    geom.azGridDeg  = azGridDeg;
end
