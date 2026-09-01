function [data, dq] = readBlock(dq, n)
% READBLOCK - Acquire a Contiguous Block of 6-Channel Audio Samples
%
% PURPOSE:
%   Acquires exactly n samples across all 6 analog channels from the active
%   NI-DAQ session (or simulation streamer). Returns an [n x 6] double matrix.
%
% INPUTS:
%   dq - Active DAQ session object or simulation state struct
%   n  - Number of samples per channel to read (e.g., cfg.blockSize = 512)
%
% OUTPUTS:
%   data - [n x 6] Matrix of acquired voltages in Volts
%   dq   - Updated DAQ / simulation state struct
%
% ZERO OVERHEAD:
%   Optimized for low-latency real-time acquisition loops.

    if isstruct(dq) && isfield(dq, 'isSimulated') && dq.isSimulated
        % Synthetic multi-channel audio stream generator
        fs = dq.Rate;
        tBlockStart = dq.sampleCounter / fs;
        tBlockEnd   = (dq.sampleCounter + n - 1) / fs;
        tVector     = (dq.sampleCounter : dq.sampleCounter + n - 1)' / fs;
        
        % 1. Ambient baseline acoustic noise floor (~15 mV RMS with pink-like spectrum)
        rawNoise = randn(n, dq.numChannels) * 0.015;
        % MAX4466 DC bias (~1.65V from 3.3V supply) + slight 50Hz mains hum
        dcBias   = [1.65, 1.63, 1.67, 1.64, 1.66, 1.65];
        mainsHum = 0.005 * sin(2 * pi * 50 * tVector) * ones(1, dq.numChannels);
        data     = dcBias + mainsHum + rawNoise;
        
        % 2. Check if a synthetic acoustic impulse occurs in this block
        if (dq.nextEventTime >= tBlockStart) && (dq.nextEventTime < tBlockEnd)
            targetAngleDeg = dq.testAngles(dq.testAngleIdx);
            dq.testAngleIdx = mod(dq.testAngleIdx, numel(dq.testAngles)) + 1;
            
            % Generate acoustic impulse across array with spatial propagation delays
            offsetInBlock = round((dq.nextEventTime - tBlockStart) * fs);
            eventSig = generateSimulatedImpulse(dq.cfg, targetAngleDeg);
            
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
        if ~isa(data, 'double')
            data = double(data);
        end
    catch ME
        warning("readBlock:DAQReadError", "DAQ read error: %s. Returning zeros.", ME.message);
        data = zeros(n, 6);
    end
end

function eventSig = generateSimulatedImpulse(cfg, sourceAngleDeg)
% Helper to generate a realistic acoustic transient (N-wave Friedlander impulse)
    fs = cfg.fs;
    c  = cfg.c;
    
    % Source unit direction vector
    theta = deg2rad(sourceAngleDeg);
    u_source = [cos(theta), sin(theta), 0];
    
    % Theoretical propagation delays relative to origin: tau_m = -(p_m . u) / c
    micPos = cfg.micPos;
    delays = -(micPos * u_source') / c;
    relDelays = delays - min(delays);
    
    % Friedlander pulse: p(t) = P0 * (1 - t/T) * exp(-alpha * t/T)
    T_dur = 0.0025; % 2.5 ms duration
    tImp = (0 : 1/fs : T_dur)';
    alpha = 2.8;
    P0 = 2.2; % 2.2V peak impulse amplitude
    basePulse = P0 * (1 - tImp / T_dur) .* exp(-alpha * tImp / T_dur);
    
    % Bandpass shaping (200 - 4000 Hz)
    try
        [b, a] = butter(2, [200, 4000] / (fs/2), 'bandpass');
    catch
        b = [0.0564, 0, -0.1129, 0, 0.0564];
        a = [1.0, -3.1936, 3.8485, -2.1051, 0.4504];
    end
    shapedPulse = filter(b, a, basePulse);
    
    % Total signal duration
    totalLen = round((T_dur + max(relDelays) + 0.004) * fs);
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
        
        startIdx = intDelay + 1;
        endIdx = startIdx + numel(delayedMicPulse) - 1;
        if endIdx <= totalLen
            eventSig(startIdx:endIdx, m) = delayedMicPulse;
        end
    end
end

function s = localSinc(t)
    s = ones(size(t));
    idx = (t ~= 0);
    s(idx) = sin(pi * t(idx)) ./ (pi * t(idx));
end
