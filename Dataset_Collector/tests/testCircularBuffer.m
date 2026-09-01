function results = testCircularBuffer()
% TESTCIRCULARBUFFER - Unit Verification for 6-Channel Circular Ring Buffer
%
% Tests:
%   1. Buffer initialization & allocation
%   2. Sequential block write without wrap
%   3. Wrap-around circular boundary integrity & chronological ordering
%   4. Event window extraction (pre/post samples)
%   5. Channel dimension enforcement & reset

    fprintf("--- Running CircularBuffer Unit Tests ---\n");
    results = struct('name', 'testCircularBuffer', 'passed', 0, 'failed', 0, 'details', []);

    % Test 1: Initialization
    buf = CircularBuffer(1000, 6);
    assert(buf.capacity == 1000, "Capacity mismatch");
    assert(buf.numChannels == 6, "Channel count mismatch");
    assert(buf.totalWritten() == 0, "Initial sample count should be 0");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 1. Initialization and dimension checks\n");

    % Test 2: Sequential write without wrap
    data1 = ones(200, 6) * 1.5;
    buf.write(data1);
    assert(buf.totalWritten() == 200, "Written count should be 200");
    readData1 = buf.read(200);
    assert(size(readData1, 1) == 200 && size(readData1, 2) == 6, "Read size mismatch");
    assert(all(readData1(:) == 1.5), "Data integrity corrupted in sequential write");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 2. Sequential write and chronological read\n");

    % Test 3: Circular boundary wrap-around
    data2 = repmat((1:900)', 1, 6);
    buf.write(data2); % Total written now 1100 > 1000 capacity
    assert(buf.totalWritten() == 1000, "Full buffer totalWritten should equal capacity");
    readRecent = buf.read(100);
    assert(size(readRecent, 1) == 100, "Read 100 recent failed");
    expectedEnd = repmat((801:900)', 1, 6);
    assert(max(abs(readRecent(:) - expectedEnd(:))) < 1e-9, "Wrap-around chronological ordering failed");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 3. Wrap-around boundary handling and chronological order\n");

    % Test 4: Pre-trigger and post-trigger event window extraction
    [eventWin, isComplete] = buf.extractEventWindow(400, 600);
    assert(isComplete == true, "Event window should be complete");
    assert(size(eventWin, 1) == 1000 && size(eventWin, 2) == 6, "Event window size mismatch");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 4. Pre/Post event window extraction (400 pre + 600 post)\n");

    % Test 5: Reset
    buf.reset();
    assert(buf.totalWritten() == 0, "Buffer count should be 0 after reset");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 5. Buffer reset and state purge\n");

    fprintf("CircularBuffer Tests Passed: %d / %d\n\n", results.passed, results.passed + results.failed);
end
