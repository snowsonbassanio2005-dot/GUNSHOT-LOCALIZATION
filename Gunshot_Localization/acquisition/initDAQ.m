function [dq, info] = initDAQ(cfg)
% INITDAQ - Initialize NI DAQ USB-6221 or Synthetic Acquisition Session
%
% PURPOSE:
%   Initializes the National Instruments DAQ device (Dev1) using the MATLAB
%   Data Acquisition Toolbox for 6 analog input voltage channels (AI0:AI5).
%   If cfg.simulationMode is true, initializes a high-fidelity synthetic
%   impulse streaming generator for offline testing and verification.
%
% INPUTS:
%   cfg - Configuration structure from config.m:
%         .deviceName     : "Dev1" (or specified NI device string)
%         .channels       : Array of channel indices (e.g. 0:5)
%         .fs             : Sampling rate in Hz (e.g. 40000)
%         .simulationMode : Boolean flag (true = simulation, false = live DAQ)
%
% OUTPUTS:
%   dq   - DAQ session object or simulation state structure
%   info - Informational status string describing acquisition configuration
%
% MATHEMATICAL / HARDWARE DETAILS:
%   The NI USB-6221 DAQ card provides a 16-bit successive approximation (SAR)
%   multiplexed ADC with an aggregate sampling rate up to 250 kS/s.
%   Acquiring 6 channels at 40 kS/s uses an aggregate rate of 240 kS/s,
%   introducing an inter-channel multiplexing phase delay of approximately
%   4.17 µs per consecutive channel switch, which is compensated in calibration.

    if isfield(cfg, 'simulationMode') && cfg.simulationMode
        % Initialize Synthetic Simulation Streamer
        dq = struct();
        dq.isSimulated   = true;
        dq.Rate          = cfg.fs;
        dq.numChannels   = numel(cfg.channels);
        dq.sampleCounter = 0;
        dq.nextEventTime = 1.0; % First synthetic gunshot at t = 1.0s
        dq.eventInterval = 2.5; % Periodic test events every 2.5s
        dq.testAngles    = [42.37, 120.0, 215.5, 330.0, 90.0, 180.0];
        dq.testAngleIdx  = 1;
        dq.cfg           = cfg;
        
        info = sprintf("Simulation Mode Active: Synthetic 6-channel streamer initialized at %d Hz", cfg.fs);
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
        
        % Set Master Sampling Rate
        dq.Rate = cfg.fs;
        
        info = sprintf("NI-DAQ [%s] successfully initialized at %d Hz (%d channels: AI%d..AI%d)", ...
            cfg.deviceName, cfg.fs, numel(cfg.channels), min(cfg.channels), max(cfg.channels));
            
    catch ME
        warning("initDAQ:HardwareError", ...
            "Failed to initialize NI-DAQ [%s]: %s\nFalling back to Simulation Mode for offline operation.", ...
            cfg.deviceName, ME.message);
            
        % Safe fallback to simulation mode so GUI and pipeline remain operational
        dq = struct();
        dq.isSimulated   = true;
        dq.Rate          = cfg.fs;
        dq.numChannels   = numel(cfg.channels);
        dq.sampleCounter = 0;
        dq.nextEventTime = 1.0;
        dq.eventInterval = 2.5;
        dq.testAngles    = [42.37, 120.0, 215.5, 330.0, 90.0, 180.0];
        dq.testAngleIdx  = 1;
        dq.cfg           = cfg;
        
        info = sprintf("Hardware Unavailable - Simulation Fallback Active at %d Hz", cfg.fs);
    end
end
