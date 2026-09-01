function results = testDetector()
% TESTDETECTOR - Verification for 7-Stage Impulsive Acoustic Event Detector
%
% Tests:
%   1. Rejection of ambient silence & Gaussian noise
%   2. Rejection of continuous sinusoidal hum (50/60 Hz)
%   3. Rejection of single-microphone glitch (fails minimum coincident channel threshold)
%   4. Positive detection of authentic 6-channel acoustic impulse
%   5. Cooldown refractory timer enforcement

    fprintf("--- Running Event Detector Unit Tests ---\n");
    results = struct('name', 'testDetector', 'passed', 0, 'failed', 0, 'details', []);

    cfg = config();
    fs = cfg.fs;
    N = 2000; % 50 ms test window

    % Test 1: Ambient Gaussian Noise Floor (Should NOT trigger)
    noiseData = randn(N, 6) * 0.015 + 1.65; % 15 mV RMS with DC bias
    [trig1, ~] = detect_event(noiseData, cfg, -inf);
    assert(trig1 == false, "Detector triggered on ambient Gaussian noise");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 1. Ambient noise rejection (false positive immunity)\n");

    % Test 2: Continuous 1 kHz Tone (Should NOT trigger due to low Peak-to-RMS)
    t = (0:N-1)' / fs;
    toneData = 0.5 * sin(2*pi*1000*t) * ones(1, 6) + 1.65;
    [trig2, ~] = detect_event(toneData, cfg, -inf);
    assert(trig2 == false, "Detector triggered on continuous sinusoidal tone");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 2. Continuous tone / speech rejection (Peak-to-RMS check)\n");

    % Test 3: Single-channel electrical glitch (Only Ch 1 spikes, Ch 2-6 quiet)
    glitchData = randn(N, 6) * 0.010 + 1.65;
    glitchData(end-200, 1) = glitchData(end-200, 1) + 2.5; % 2.5V spike on 1 channel
    [trig3, ~] = detect_event(glitchData, cfg, -inf);
    assert(trig3 == false, "Detector triggered on single-channel glitch");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 3. Single-channel glitch rejection (coincident voting check)\n");

    % Test 4: Authentic 6-channel impulse wave
    impulseData = randn(N, 6) * 0.010 + 1.65;
    % Insert 2.0V impulse pulse on all 6 channels with physical delay
    pulseLen = 40; % 1 ms pulse
    tP = (0:pulseLen-1)' / fs;
    pWave = 2.0 * exp(-tP * 4000) .* sin(2*pi*1200*tP);
    
    for ch = 1:6
        delaySamples = (ch - 1) * 3; % 3 samples per mic = within array radius
        insertIdx = (N - 300) + delaySamples;
        impulseData(insertIdx : insertIdx + pulseLen - 1, ch) = impulseData(insertIdx : insertIdx + pulseLen - 1, ch) + pWave;
    end

    [trig4, meta4] = detect_event(impulseData, cfg, -inf);
    assert(trig4 == true, "Detector failed to detect authentic multi-channel impulse");
    assert(meta4.triggeredChannels >= 3, "Coincident channel count should be >= 3");
    assert(meta4.peakRatio >= cfg.trigger.peakRatio, "Peak ratio should satisfy threshold");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 4. Positive impulse detection & multi-channel coincidence\n");

    % Test 5: Cooldown Enforcement (Immediate re-evaluation with active tic)
    lastTic = tic;
    [trig5, ~] = detect_event(impulseData, cfg, lastTic);
    assert(trig5 == false, "Detector triggered during active cooldown period");
    results.passed = results.passed + 1;
    fprintf("  [PASS] 5. Refractory cooldown timer enforcement (100 ms)\n");

    fprintf("Detector Tests Passed: %d / %d\n\n", results.passed, results.passed + results.failed);
end
