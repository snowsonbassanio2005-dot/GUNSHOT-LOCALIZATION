function state = initialize_dataset(cfg)
% INITIALIZE_DATASET - Folder Structure, Metadata Scanner & State Recovery
%
% PURPOSE:
%   1. Automatically creates required storage folders (data, recordings, logs).
%   2. Scans existing recordings and metadata spreadsheets to determine the
%      highest existing event number across previous sessions.
%   3. Guarantees persistence across MATLAB restarts, crashes, or power cycles
%      so event numbering seamlessly continues without duplicate IDs or overwrites.
%   4. Initializes CSV/Excel headers if starting a brand new dataset.
%   5. Logs session startup and state diagnostics.
%
% INPUTS:
%   cfg - Configuration structure from config.m
%
% OUTPUTS:
%   state - Runtime dataset state structure:
%             .nextEventId    : Integer index for the next event to be saved (e.g. 1 or 828)
%             .totalEvents    : Total count of successfully saved events in dataset
%             .lastSavedEvent : Struct with details of most recent saved event
%             .paths          : Verified directory and file paths
%             .statusMsg      : Informational startup banner string

    if nargin < 1 || isempty(cfg)
        cfg = config();
    end

    state = struct();
    state.nextEventId    = 1;
    state.totalEvents    = 0;
    state.lastSavedEvent = struct('name', "None", 'distance', 0, 'angle', 0, 'timestamp', "N/A");
    state.paths          = cfg.paths;
    state.statusMsg      = "";

    %% 1. Auto-Create Required Directories
    dirsToCreate = [cfg.paths.dataDir, cfg.paths.recordingsDir, cfg.paths.logsDir];
    for d = dirsToCreate
        if ~isfolder(d)
            mkdir(d);
        end
    end

    %% 2. Scan Existing Recording Files in data/recordings/
    maxFileId = 0;
    fileCount = 0;
    recordingFiles = dir(fullfile(cfg.paths.recordingsDir, "event_*.csv"));

    for k = 1:numel(recordingFiles)
        fn = recordingFiles(k).name;
        token = regexp(fn, '^event_(\d+)\.csv$', 'tokens', 'once');
        if ~isempty(token)
            idVal = str2double(token{1});
            if ~isnan(idVal)
                fileCount = fileCount + 1;
                if idVal > maxFileId
                    maxFileId = idVal;
                end
            end
        end
    end

    %% 3. Scan Existing Metadata CSV
    maxCsvId = 0;
    csvRowCount = 0;
    csvLastEvent = [];

    if isfile(cfg.paths.metadataCsv)
        try
            fid = fopen(cfg.paths.metadataCsv, 'r');
            if fid ~= -1
                % Read line by line
                headerLine = fgetl(fid); % Skip header
                while ~feof(fid)
                    line = strtrim(fgetl(fid));
                    if isempty(line) || ~ischar(line)
                        continue;
                    end
                    parts = strsplit(line, ',');
                    if numel(parts) >= 5
                        token = regexp(parts{1}, '^event_(\d+)$', 'tokens', 'once');
                        if ~isempty(token)
                            idVal = str2double(token{1});
                            if ~isnan(idVal)
                                csvRowCount = csvRowCount + 1;
                                if idVal > maxCsvId
                                    maxCsvId = idVal;
                                    csvLastEvent.name = string(parts{1});
                                    csvLastEvent.distance = str2double(parts{2});
                                    csvLastEvent.angle = str2double(parts{3});
                                    csvLastEvent.timestamp = string(parts{4});
                                end
                            end
                        end
                    end
                end
                fclose(fid);
            end
        catch csvReadME
            warning("initialize_dataset:CsvReadError", "Error parsing metadata.csv: %s", csvReadME.message);
        end
    else
        % Initialize empty metadata.csv with headers
        try
            fid = fopen(cfg.paths.metadataCsv, 'w');
            if fid ~= -1
                fprintf(fid, "Event,Distance_m,Angle_deg,Timestamp,Recording_File\n");
                fclose(fid);
            end
        catch
        end
    end

    %% 4. Scan Existing Metadata XLSX
    maxXlsxId = 0;
    if isfile(cfg.paths.metadataXlsx)
        try
            t = readtable(cfg.paths.metadataXlsx, 'VariableNamingRule', 'preserve');
            if ismember('Event', t.Properties.VariableNames)
                eventStrs = string(t.Event);
                for k = 1:numel(eventStrs)
                    token = regexp(eventStrs(k), '^event_(\d+)$', 'tokens', 'once');
                    if ~isempty(token)
                        idVal = str2double(token{1});
                        if ~isnan(idVal) && idVal > maxXlsxId
                            maxXlsxId = idVal;
                        end
                    end
                end
            end
        catch
            % Non-fatal: XLSX might be in use or format varied
        end
    else
        % Initialize empty metadata.xlsx with headers
        try
            emptyTable = table( ...
                strings(0,1), zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
                'VariableNames', {'Event', 'Distance_m', 'Angle_deg', 'Timestamp', 'Recording_File'});
            writetable(emptyTable, cfg.paths.metadataXlsx, 'Sheet', 1);
        catch
        end
    end

    %% 5. Determine Resumed Next Event ID and Total Event Count
    highestId = max([maxFileId, maxCsvId, maxXlsxId]);
    state.totalEvents = max([fileCount, csvRowCount]);
    state.nextEventId = highestId + 1;

    if ~isempty(csvLastEvent)
        state.lastSavedEvent = csvLastEvent;
    elseif highestId > 0
        state.lastSavedEvent.name = sprintf("event_%04d", highestId);
    end

    %% 6. Append Startup Entry to Session Log
    timeStr = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    startLogMsg = sprintf("[%s] [SESSION_START] Dataset Collector initialized. Resuming at event_%04d (Total existing: %d).", ...
        timeStr, state.nextEventId, state.totalEvents);
    
    try
        fidLog = fopen(cfg.paths.logFile, 'a');
        if fidLog ~= -1
            fprintf(fidLog, "%s\n", startLogMsg);
            fclose(fidLog);
        end
    catch
    end

    state.statusMsg = sprintf("Dataset Initialized: Resuming at event_%04d (%d existing events)", ...
        state.nextEventId, state.totalEvents);
end
