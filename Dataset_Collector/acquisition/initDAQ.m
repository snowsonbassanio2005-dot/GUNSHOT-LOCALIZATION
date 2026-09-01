function [dq, info] = initDAQ(cfg)
% INITDAQ - Initialize NI DAQ USB-6221 or Synthetic Acquisition Session
%
% PURPOSE:
%   Initializes the National Instruments DAQ device (Dev1) using the MATLAB
%   Data Acquisition Toolbox for 6 analog input voltage channels (AI0:AI5).
%   Maintains continuous high-speed background streaming at 40 kS/s per channel.
%   If cfg.simulationMode is true or hardware is detached, initializes an offline
%   synthetic impulse streaming engine for full system testing.
%
% INPUTS:
%   cfg - Configuration structure from config.m:
%         .deviceName     : "Dev1" (NI DAQ device identifier)
%         .channels       : 0:5 (AI0 to AI5 analog voltage channels)
%         .fs             : 40000 (Sampling rate in Hz)
%         .simulationMode : Boolean flag (true = simulation, false = live NI DAQ)
%
% OUTPUTS:
%   dq   - Active DAQ session object or simulation state struct
%   info - Informational status string describing acquisition configuration
%
% HARDWARE DETAILS:
%   NI USB-6221 with 16-bit successive approximation (SAR) multiplexed ADC.
%   Acquires 6 channels simultaneously at 40 kHz (240 kS/s aggregate).

    if nargin < 1 || isempty(cfg)
        cfg = config();
    end

    if isfield(cfg, 'simulationMode') && cfg.simulationMode
        % Initialize Synthetic Simulation Streamer
        dq = struct();
        dq.isSimulated   = true;
        dq.Rate          = cfg.fs;
        dq.numChannels   = numel(cfg.channels);
        dq.sampleCounter = 0;
        dq.nextEventTime = 1.2; % First synthetic impulse at t = 1.2s
        dq.eventInterval = 3.5; % Next event every 3.5s
        dq.testAngles    = [45.0, 120.0, 215.0, 310.0, 90.0, 180.0];
        dq.testDistances = [1.5, 2.0, 1.0, 2.5, 3.0, 1.8];
        dq.testAngleIdx  = 1;
        dq.cfg           = cfg;
        
        info = sprintf("Simulation Mode: Synthetic 6-channel streamer active at %d Hz", cfg.fs);
        return;
    end

    try
        % Standard MATLAB Data Acquisition Toolbox (R2020a+ daq interface)
        dq = daq("ni");
        
        % Configure Analog Input Voltage Channels AI0:AI5
        for c = cfg.channels
            chName = "ai" + string(c);
            addinput(dq, string(cfg.deviceName), chName, "Voltage");
        end
        
        % Set Master Sampling Rate (40,000 Hz)
        dq.Rate = cfg.fs;
        
        info = sprintf("NI-DAQ [%s] connected at %d Hz (6 Channels: AI%d..AI%d)", ...
            cfg.deviceName, cfg.fs, min(cfg.channels), max(cfg.channels));
            
    catch ME
        warning("initDAQ:HardwareError", ...
            "Failed to initialize NI-DAQ [%s]: %s\nFalling back to Simulation Streamer for testing.", ...
            cfg.deviceName, ME.message);
            
        % Fallback to simulation mode for seamless operation without hardware
        dq = struct();
        dq.isSimulated   = true;
        dq.Rate          = cfg.fs;
        dq.numChannels   = numel(cfg.channels);
        dq.sampleCounter = 0;
        dq.nextEventTime = 1.2;
        dq.eventInterval = 3.5;
        dq.testAngles    = [45.0, 120.0, 215.0, 310.0, 90.0, 180.0];
        dq.testDistances = [1.5, 2.0, 1.0, 2.5, 3.0, 1.8];
        dq.testAngleIdx  = 1;
        dq.cfg           = cfg;
        
        info = sprintf("Hardware Unavailable - Simulation Fallback Active at %d Hz", cfg.fs);
    end
end
