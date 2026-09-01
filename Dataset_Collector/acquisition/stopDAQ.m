function stopDAQ(dq)
% STOPDAQ - Safely Teardown and Release NI DAQ Resources
%
% PURPOSE:
%   Stops active NI DAQ background acquisition, releases hardware handles,
%   and frees memory.
%
% INPUTS:
%   dq - Active DAQ session object or simulation state struct

    if isempty(dq)
        return;
    end

    if isstruct(dq) && isfield(dq, 'isSimulated') && dq.isSimulated
        % Nothing to release for simulation struct
        return;
    end

    try
        if isa(dq, 'daq.interfaces.DataAcquisition') || isa(dq, 'daq.DataAcquisition')
            stop(dq);
            flush(dq);
            delete(dq);
        end
    catch ME
        warning("stopDAQ:ReleaseWarning", "Non-fatal warning during DAQ shutdown: %s", ME.message);
    end
end
