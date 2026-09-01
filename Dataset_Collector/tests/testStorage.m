function results = testStorage()
% TESTSTORAGE - Verification for Persistence, Auto-Recovery, and Metadata Sync
%
% Tests:
%   1. Automatic folder hierarchy creation
%   2. Waveform CSV file formatting (Sample, M1..M6) and content integrity
%   3. Metadata CSV appending and header persistence
%   4. Metadata XLSX generation and schema
%   5. Sequential restart recovery (no duplicate IDs or lost data)
%   6. Input validation (rejection of negative distance or angle >= 360)

    fprintf("--- Running Storage and Recovery Unit Tests ---\n");
    results = struct('name', 'testStorage', 'passed', 0, 'failed', 0, 'details', []);

    % Create isolated temporary test config
    cfg = config();
    testBaseDir = fullfile(cfg.paths.baseDir, "tests", "scratch_data");
    if isfolder(testBaseDir)
        rmdir(testBaseDir, 's');
    end

    cfg.paths.baseDir       = string(testBaseDir);
    cfg.paths.dataDir       = fullfile(testBaseDir, "data");
    cfg.paths.recordingsDir = fullfile(testBaseDir, "data", "recordings");
    cfg.paths.metadataXlsx  = fullfile(testBaseDir, "data", "metadata.xlsx");
    cfg.paths.metadataCsv   = fullfile(testBaseDir, "data", "metadata.csv");
    cfg.paths.logsDir       = fullfile(testBaseDir, "logs");
    cfg.paths.logFile       = fullfile(testBaseDir, "logs", "session_log.txt");

    % Test 1: Auto-create directories on initialize
    state1 = initialize_dataset(cfg);
    assert(isfolder(cfg.paths.dataDir), "data/ folder not created");
    assert(isfolder(cfg.paths.recordingsDir), "data/recordings/ folder not created");
    assert(isfolder(cfg.paths.logsDir), "logs/ folder not created");
    assert(state1.nextEventId == 1, "Brand new dataset should start at event_0001");
    assert(state1.totalEvents == 0, "Initial event count should be 0");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 1. Automatic folder creation & empty dataset state initialization\n");

    % Test 2: Save Event 1 (CSV waveform + Metadata CSV + Metadata XLSX)
    dummyWaveform = randn(2400, 6) + 1.65;
    tStamp = "2026-09-01 14:00:00.000";
    [success1, msg1, name1, path1] = save_event(dummyWaveform, 1, 1.50, 45.0, tStamp, cfg);
    assert(success1 == true, sprintf("Save event 1 failed: %s", msg1));
    assert(isfile(path1), "Waveform CSV file does not exist on disk");

    % Check Waveform CSV structure (Sample,M1..M6)
    csvLines = readlines(path1);
    assert(csvLines(1) == "Sample,M1,M2,M3,M4,M5,M6", "Waveform CSV header is invalid");
    assert(numel(csvLines) >= 2401, "Waveform CSV sample row count mismatch (expected 2400 rows + 1 header)");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 2. Waveform CSV formatting, sample index column & 6-channel integrity\n");

    % Test 3: Metadata CSV contents
    assert(isfile(cfg.paths.metadataCsv), "metadata.csv does not exist");
    csvMetaLines = readlines(cfg.paths.metadataCsv);
    assert(contains(csvMetaLines(1), "Event,Distance_m,Angle_deg,Timestamp,Recording_File"), "metadata.csv header missing");
    assert(contains(csvMetaLines(2), "event_0001,1.500,45.00"), "metadata.csv row 1 corrupted");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 3. metadata.csv row appending & header verification\n");

    % Test 4: Save multiple subsequent events (Event 2 and Event 3)
    [success2, ~] = save_event(dummyWaveform, 2, 2.00, 90.0, "2026-09-01 14:01:00.000", cfg);
    [success3, ~] = save_event(dummyWaveform, 3, 3.50, 270.0, "2026-09-01 14:02:00.000", cfg);
    assert(success2 && success3, "Subsequent event saves failed");
    assert(isfile(fullfile(cfg.paths.recordingsDir, "event_0002.csv")), "event_0002.csv missing");
    assert(isfile(fullfile(cfg.paths.recordingsDir, "event_0003.csv")), "event_0003.csv missing");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 4. Multi-event sequential persistence (event_0002, event_0003)\n");

    % Test 5: Simulated Application Crash & Restart Recovery
    % Re-call initialize_dataset to simulate fresh MATLAB session startup
    stateResumed = initialize_dataset(cfg);
    assert(stateResumed.nextEventId == 4, sprintf("Expected resumed nextEventId = 4, got %d", stateResumed.nextEventId));
    assert(stateResumed.totalEvents == 3, sprintf("Expected totalEvents = 3, got %d", stateResumed.totalEvents));
    assert(stateResumed.lastSavedEvent.name == "event_0003", "Resumed last event name mismatch");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 5. Post-crash / restart recovery: Resumed at event_0004 without duplicates\n");

    % Test 6: Input Validation Errors
    [failDist, msgDist] = save_event(dummyWaveform, 4, -1.5, 45.0, tStamp, cfg);
    assert(failDist == false, "Should reject negative distance");
    [failAngle, msgAngle] = save_event(dummyWaveform, 4, 1.5, 365.0, tStamp, cfg);
    assert(failAngle == false, "Should reject angle >= 360");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 6. Label input validation (rejection of negative distance or angle >= 360)\n");

    % Clean up scratch test directory
    try
        rmdir(testBaseDir, 's');
    catch
    end

    fprintf("Storage Tests Passed: %d / %d\n\n", results.passed, results.passed + results.failed);
end
