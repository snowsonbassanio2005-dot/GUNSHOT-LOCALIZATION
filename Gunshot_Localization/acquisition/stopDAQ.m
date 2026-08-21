function stopDAQ(dq)
% STOPDAQ - Safely Terminate NI DAQ Acquisition Session
%
% PURPOSE:
%   Stops active acquisition on the NI-DAQ device, flushes internal hardware
%   FIFOs, releases channel bindings, and cleans up memory resources.
%
% INPUT:
%   dq - NI DAQ session object or simulation state struct

    if isempty(dq)
        return;
    end

    if isstruct(dq) && isfield(dq, 'isSimulated') && dq.isSimulated
        fprintf("[DAQ] Simulation stream stopped gracefully.\n");
        return;
    end

    try
        if isa(dq, 'daq.interfaces.DataAcquisition') || isa(dq, 'daq.ni.Session')
            stop(dq);
            flush(dq);
            delete(dq);
            fprintf("[DAQ] NI-DAQ device released and stopped successfully.\n");
        end
    catch ME
        fprintf("[DAQ] Info during stopDAQ: %s\n", ME.message);
    end
end
