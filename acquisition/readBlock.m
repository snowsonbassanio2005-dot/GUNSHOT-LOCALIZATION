function [data, dq] = readBlock(dq, n)
% READBLOCK - Acquire a Contiguous Block of 6-Channel Audio Samples
%
% PURPOSE:
%   Reads exactly n samples across all 6 channels from the active NI-DAQ session
%   or the simulation streamer. Returns an [n x 6] double precision matrix.
%
% INPUTS:
%   dq - NI DAQ session object or simulation state struct
%   n  - Number of samples per channel to read (e.g. cfg.blockSize = 512)
%
% OUTPUTS:
%   data - [n x 6] matrix of acquired voltages in Volts
%   dq   - Updated DAQ/simulation state object
%
% PERFORMANCE:
%   Zero-copy where possible; non-blocking memory allocation for real-time DSP.

    if isstruct(dq) && isfield(dq, 'isSimulated') && dq.isSimulated
        % Synthetic audio stream generation
        fs = dq.Rate;
        tBlockStart = dq.sampleCounter / fs;
        tBlockEnd   = (dq.sampleCounter + n - 1) / fs;
        tVector     = (dq.sampleCounter : dq.sampleCounter + n - 1)' / fs;
        
        % 1. Ambient baseline acoustic noise floor (~15 mV RMS with pink-like spectrum)
        rawNoise = randn(n, dq.numChannels) * 0.015;
        % Add subtle 50/60 Hz mains hum and MAX4466 DC bias
        dcBias   = [1.65, 1.63, 1.67, 1.64, 1.66, 1.65]; % Typical 3.3V / 2 MAX4466 DC level
        mainsHum = 0.005 * sin(2 * pi * 50 * tVector) * ones(1, dq.numChannels);
        data     = dcBias + mainsHum + rawNoise;
        
        % 2. Check if a synthetic gunshot impulse occurs in this block
        if (dq.nextEventTime >= tBlockStart) && (dq.nextEventTime < tBlockEnd)
            % Target angle for this event
            targetAngleDeg = dq.testAngles(dq.testAngleIdx);
            dq.testAngleIdx = mod(dq.testAngleIdx, numel(dq.testAngles)) + 1;
            
            % Generate acoustic gunshot impulse at array
            offsetInBlock = round((dq.nextEventTime - tBlockStart) * fs);
            [eventSig, ~] = generateSyntheticImpulse(dq.cfg, targetAngleDeg);
            
            sigLen = size(eventSig, 1);
            startIdx = offsetInBlock + 1;
            endIdx   = min(n, startIdx + sigLen - 1);
            eventSubLen = endIdx - startIdx + 1;
            
            if eventSubLen > 0
                data(startIdx:endIdx, :) = data(startIdx:endIdx, :) + eventSig(1:eventSubLen, :);
            end
            
            % Schedule next event
            dq.nextEventTime = dq.nextEventTime + dq.eventInterval;
        end
        
        dq.sampleCounter = dq.sampleCounter + n;
        return;
    end

    % Live Hardware NI DAQ-6221 read
    try
        data = read(dq, n, "OutputFormat", "Matrix");
        % Ensure data is double precision
        if ~isa(data, 'double')
            data = double(data);
        end
    catch ME
        warning("readBlock:DAQReadError", "DAQ read error: %s. Returning zeros.", ME.message);
        data = zeros(n, 6);
    end
end

function [eventSig, delays] = generateSyntheticImpulse(cfg, sourceAngleDeg)
% Helper to generate a realistic acoustic gunshot transient (N-wave / Friedlander pulse)
    fs = cfg.fs;
    c  = cfg.c;
    
    % Source unit direction vector (pointing to source)
    theta = deg2rad(sourceAngleDeg);
    u_source = [cos(theta), sin(theta), 0];
    
    % Theoretical propagation delays relative to coordinate origin
    % tau_m = - (p_m . u_source) / c
    micPos = cfg.micPos;
    delays = -(micPos * u_source') / c;
    
    % Shift delays so first arriving microphone has delay = 0
    relDelays = delays - min(delays);
    
    % Base Friedlander gunshot wave: p(t) = P0 * (1 - t/T) * exp(-alpha * t/T)
    T_dur = 0.003; % 3 ms blast wave
    tImp = (0 : 1/fs : T_dur)';
    alpha = 2.5;
    P0 = 2.0; % Peak amplitude in Volts
    basePulse = P0 * (1 - tImp / T_dur) .* exp(-alpha * tImp / T_dur);
    
    % Bandpass shaping (200 - 4000 Hz)
    try
        [b, a] = butter(2, [200, 4000] / (fs/2), 'bandpass');
    catch
        b = [0.05644846226073642, 0, -0.11289692452147285, 0, 0.05644846226073642];
        a = [1.0, -3.193633306817034, 3.8485320133979526, -2.1050966172593095, 0.45044543005604093];
    end
    shapedPulse = filter(b, a, basePulse);
    
    % Total signal duration with delays + padding
    totalLen = round((T_dur + max(relDelays) + 0.005) * fs);
    eventSig = zeros(totalLen, cfg.numMics);
    
    for m = 1:cfg.numMics
        delaySamples = relDelays(m) * fs;
        intDelay = floor(delaySamples);
        fracDelay = delaySamples - intDelay;
        
        % Sinc fractional delay filter
        N_sinc = 31;
        t_sinc = (-floor(N_sinc/2) : floor(N_sinc/2))' - fracDelay;
        sincFilter = localSinc(t_sinc);
        
        delayedMicPulse = conv(shapedPulse, sincFilter, 'same');
        
        % Insert with integer delay
        startIdx = intDelay + 1;
        endIdx = startIdx + numel(delayedMicPulse) - 1;
        if endIdx <= totalLen
            eventSig(startIdx:endIdx, m) = delayedMicPulse;
        end
    end
end

function s = localSinc(t)
% Native pure-MATLAB normalized sinc function
    s = ones(size(t));
    idx = (t ~= 0);
    s(idx) = sin(pi * t(idx)) ./ (pi * t(idx));
end
