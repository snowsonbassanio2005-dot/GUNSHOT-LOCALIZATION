function [success, msg, eventName, filePath] = save_event(rawWindow, eventId, distance_m, angle_deg, timestamp, cfg, eventMeta)
% SAVE_EVENT - Persist Synchronized 6-Channel Waveform and Labeled Metadata
%
% PURPOSE:
%   Persists the raw multi-channel acoustic waveform and ground-truth spatial
%   labels (distance, angle) to disk with full integrity validation.
%   Maintains both Excel (.xlsx) and CSV (.csv) metadata indexes for compatibility,
%   and logs all operations to the session audit log.
%
% INPUTS:
%   rawWindow   - [N x 6] Synchronized multi-channel voltage matrix (e.g., 2400 samples)
%   eventId     - Integer sequential event ID (e.g. 1, 37, 828)
%   distance_m  - Ground truth distance in meters (e.g. 1.50)
%   angle_deg   - Ground truth angle in degrees (0 <= angle < 360)
%   timestamp   - ISO formatted datetime string (e.g. "2026-09-01 14:45:10.123")
%   cfg         - Configuration structure from config.m
%   eventMeta   - (Optional) Diagnostic detection struct from detect_event.m
%
% OUTPUTS:
%   success   - Boolean flag indicating successful persistence
%   msg       - Informational or error description
%   eventName - Formatted event string (e.g. "event_0037")
%   filePath  - Full path to saved recording CSV file
%
% FILE STORAGE:
%   - Waveform File: data/recordings/event_XXXX.csv
%     Columns: Sample, M1, M2, M3, M4, M5, M6
%   - Metadata Excel: data/metadata.xlsx
%     Columns: Event, Distance_m, Angle_deg, Timestamp, Recording_File
%   - Metadata CSV:  data/metadata.csv
%     Columns: Event, Distance_m, Angle_deg, Timestamp, Recording_File
%   - Session Log:   logs/session_log.txt

    success   = false;
    msg       = "";
    eventName = sprintf("event_%04d", eventId);
    filePath  = "";

    if nargin < 6 || isempty(cfg)
        cfg = config();
    end

    if nargin < 5 || isempty(timestamp) || timestamp == ""
        timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    end

    %% 1. Input Integrity & Bounds Validation
    if isempty(rawWindow)
        msg = "Save aborted: Waveform data window is empty.";
        writeLog(cfg, sprintf("[ERROR] %s for %s", msg, eventName));
        return;
    end

    [numSamples, numChannels] = size(rawWindow);
    if numChannels ~= cfg.numMics
        msg = sprintf("Save aborted: Channel count mismatch. Expected %d, received %d.", cfg.numMics, numChannels);
        writeLog(cfg, sprintf("[ERROR] %s for %s", msg, eventName));
        return;
    end

    if numSamples < cfg.trigger.totalSamples
        warning("save_event:SampleCountWarning", ...
            "Sample count (%d) is less than configured total (%d). Saving available samples.", ...
            numSamples, cfg.trigger.totalSamples);
    end

    if ~isnumeric(distance_m) || ~isfinite(distance_m) || distance_m <= 0
        msg = sprintf("Save aborted: Invalid distance value (%.2f m). Must be a positive number.", distance_m);
        writeLog(cfg, sprintf("[ERROR] %s for %s", msg, eventName));
        return;
    end

    if ~isnumeric(angle_deg) || ~isfinite(angle_deg) || angle_deg < 0 || angle_deg >= 360
        msg = sprintf("Save aborted: Invalid angle value (%.2f deg). Must be in range [0, 359.99].", angle_deg);
        writeLog(cfg, sprintf("[ERROR] %s for %s", msg, eventName));
        return;
    end

    %% 2. Ensure Storage Folders Exist
    if ~isfolder(cfg.paths.recordingsDir)
        mkdir(cfg.paths.recordingsDir);
    end
    if ~isfolder(cfg.paths.logsDir)
        mkdir(cfg.paths.logsDir);
    end

    %% 3. Save Synchronized 6-Channel Waveform CSV
    recFileName    = eventName + ".csv";
    filePath       = fullfile(cfg.paths.recordingsDir, recFileName);
    relRecPath     = fullfile("recordings", recFileName);
    % Standardize path separators for cross-platform metadata consistency
    relRecPathStr  = strrep(char(relRecPath), '\', '/');

    try
        fid = fopen(filePath, 'w');
        if fid == -1
            error("Cannot open file for writing: %s", filePath);
        end

        % Header: Sample, M1, M2, M3, M4, M5, M6
        fprintf(fid, "Sample,M1,M2,M3,M4,M5,M6\n");

        % Write all sample rows
        sampleIndices = (1:numSamples)';
        writeMatrix = [sampleIndices, rawWindow];
        
        % Vectorized fast formatted write
        fprintf(fid, '%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', writeMatrix');
        fclose(fid);

        % Verify file on disk
        fileDetails = dir(filePath);
        if isempty(fileDetails) || fileDetails.bytes <= 0
            error("Verification failed: File was written but is empty on disk (%s)", filePath);
        end

    catch writeME
        if fid ~= -1
            fclose(fid);
        end
        msg = sprintf("Failed to write waveform CSV: %s", writeME.message);
        writeLog(cfg, sprintf("[ERROR] %s (%s)", msg, eventName));
        return;
    end

    %% 4. Append to Metadata CSV (Primary / Cross-Platform Fallback)
    csvHeader = "Event,Distance_m,Angle_deg,Timestamp,Recording_File";
    csvRow = sprintf("%s,%.3f,%.2f,%s,%s\n", ...
        eventName, distance_m, angle_deg, timestamp, relRecPathStr);

    try
        csvFileExists = isfile(cfg.paths.metadataCsv);
        fidCsv = fopen(cfg.paths.metadataCsv, 'a');
        if fidCsv ~= -1
            if ~csvFileExists || (csvFileExists && dir(cfg.paths.metadataCsv).bytes == 0)
                fprintf(fidCsv, "%s\n", csvHeader);
            end
            fprintf(fidCsv, "%s", csvRow);
            fclose(fidCsv);
        else
            warning("save_event:CsvWriteFailed", "Could not open %s for appending.", cfg.paths.metadataCsv);
        end
    catch csvME
        writeLog(cfg, sprintf("[WARNING] Failed to append to metadata.csv: %s", csvME.message));
    end

    %% 5. Append to Metadata Excel (.xlsx) with File Lock Protection
    try
        newRowTable = table( ...
            string(eventName), ...
            double(distance_m), ...
            double(angle_deg), ...
            string(timestamp), ...
            string(relRecPathStr), ...
            'VariableNames', {'Event', 'Distance_m', 'Angle_deg', 'Timestamp', 'Recording_File'});

        if ~isfile(cfg.paths.metadataXlsx)
            % Create new Excel spreadsheet
            writetable(newRowTable, cfg.paths.metadataXlsx, 'Sheet', 1);
        else
            % File exists: Read existing table and append (or write with append mode)
            try
                existingTable = readtable(cfg.paths.metadataXlsx, 'VariableNamingRule', 'preserve');
                % Verify if this event is already present to prevent duplicates
                if ismember('Event', existingTable.Properties.VariableNames)
                    if ~any(string(existingTable.Event) == string(eventName))
                        updatedTable = [existingTable; newRowTable];
                        writetable(updatedTable, cfg.paths.metadataXlsx, 'Sheet', 1);
                    end
                else
                    updatedTable = [existingTable; newRowTable];
                    writetable(updatedTable, cfg.paths.metadataXlsx, 'Sheet', 1);
                end
            catch readAppendME
                % If read/rewrite fails, attempt direct append mode
                writetable(newRowTable, cfg.paths.metadataXlsx, 'WriteMode', 'append', 'AutoFitWidth', false);
            end
        end
    catch xlsxME
        % Graceful handling if Excel file is open or locked by Microsoft Excel
        warning("save_event:ExcelLockWarning", ...
            "Metadata Excel file locked or write failed: %s\nRecording and metadata.csv saved safely.", xlsxME.message);
        writeLog(cfg, sprintf("[WARNING] metadata.xlsx write failed (locked): %s. Preserved in CSV.", xlsxME.message));
    end

    %% 6. Session Audit Log Entry
    logEntry = sprintf("[EVENT_SAVED] %s | Distance: %.3f m | Angle: %.2f deg | Samples: %d | Path: %s", ...
        eventName, distance_m, angle_deg, numSamples, relRecPathStr);
    writeLog(cfg, logEntry);

    success = true;
    msg = sprintf("%s saved successfully (Dist: %.2fm, Angle: %.1f°)", eventName, distance_m, angle_deg);
end

function writeLog(cfg, message)
% Helper to append a timestamped entry to the session log
    try
        if ~isfolder(cfg.paths.logsDir)
            mkdir(cfg.paths.logsDir);
        end
        fid = fopen(cfg.paths.logFile, 'a');
        if fid ~= -1
            timeStr = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            fprintf(fid, "[%s] %s\n", timeStr, message);
            fclose(fid);
        end
    catch
        % Non-blocking fallback
    end
end
