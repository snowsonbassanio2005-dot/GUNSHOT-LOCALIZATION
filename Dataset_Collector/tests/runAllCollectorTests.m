function overallSuccess = runAllCollectorTests()
% RUNALLCOLLECTORTESTS - Master Automated Test Runner for Dataset Collector
%
% PURPOSE:
%   Executes unit and integration test suites for the 6-microphone dataset
%   collector system, validating circular buffering, impulsive transient detection,
%   data persistence, metadata synchronization, and crash recovery.
%
% USAGE:
%   results = runAllCollectorTests();

    clc;
    fprintf("======================================================================\n");
    fprintf("    MATLAB 6-MICROPHONE DATASET COLLECTOR: TEST SUITE RUNNER         \n");
    fprintf("======================================================================\n\n");

    testsDir = fileparts(mfilename('fullpath'));
    projectDir = fileparts(testsDir);
    addpath(projectDir);
    addpath(fullfile(projectDir, 'acquisition'));
    addpath(testsDir);

    totalPassed = 0;
    totalFailed = 0;
    suiteResults = {};

    % Suite 1: CircularBuffer Tests
    try
        res1 = testCircularBuffer();
        totalPassed = totalPassed + res1.passed;
        totalFailed = totalFailed + res1.failed;
        suiteResults{end+1} = res1;
    catch ME
        fprintf("  [FAILED] CircularBuffer suite error: %s\n\n", ME.message);
        totalFailed = totalFailed + 1;
    end

    % Suite 2: Event Detector Tests
    try
        res2 = testDetector();
        totalPassed = totalPassed + res2.passed;
        totalFailed = totalFailed + res2.failed;
        suiteResults{end+1} = res2;
    catch ME
        fprintf("  [FAILED] Event Detector suite error: %s\n\n", ME.message);
        totalFailed = totalFailed + 1;
    end

    % Suite 3: Storage, Recovery & Metadata Sync Tests
    try
        res3 = testStorage();
        totalPassed = totalPassed + res3.passed;
        totalFailed = totalFailed + res3.failed;
        suiteResults{end+1} = res3;
    catch ME
        fprintf("  [FAILED] Storage suite error: %s\n\n", ME.message);
        totalFailed = totalFailed + 1;
    end

    fprintf("======================================================================\n");
    fprintf("                       TEST SUMMARY REPORT                            \n");
    fprintf("======================================================================\n");
    fprintf("  Total Tests Passed: %d\n", totalPassed);
    fprintf("  Total Tests Failed: %d\n", totalFailed);
    
    if totalFailed == 0
        fprintf("  STATUS: ALL TEST SUITES PASSED [100%% SUCCESS]\n");
        overallSuccess = true;
    else
        fprintf("  STATUS: %d TEST(S) FAILED\n", totalFailed);
        overallSuccess = false;
    end
    fprintf("======================================================================\n\n");
end
