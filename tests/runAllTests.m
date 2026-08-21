function testResults = runAllTests()
% RUNALLTESTS - Comprehensive Automated Verification Test Suite
%
% PURPOSE:
%   Executes rigorous automated unit and integration tests covering:
%   1. Array Geometry & Baseline Physics
%   2. GCC-PHAT Fractional Sub-Sample Delay Estimation Accuracy
%   3. Physical TDOA Constraints & Invalid Delay Rejection
%   4. Synchronized Multi-Channel Circular Ring Buffer
%   5. Adaptive Impulsive Event Detector & Multi-Channel Coincidence
%   6. SRP-PHAT Spatial Beamforming Peak Accuracy
%   7. Hybrid Fusion & Continuous Angle Interpolation (0° to 360°)
%   8. Circular Angular Error Benchmark across Cardinal & Intermediate Angles
%   9. Channel Timing Multiplexing Skew Calibration Recovery
%  10. Processing Latency Budget (< 50 ms per event)
%
% OUTPUT:
%   testResults - Structure summarizing pass/fail status and performance metrics

    fprintf("\n======================================================================\n");
    fprintf("    ACOUSTIC GUNSHOT LOCALIZATION SYSTEM - AUTOMATED VERIFICATION     \n");
    fprintf("======================================================================\n\n");

    cfg = config();
    totalTests = 0;
    passedTests = 0;

    %% Test 1: Array Geometry & Physical Limits
    totalTests = totalTests + 1;
    fprintf("TEST 1: Array Geometry & Theoretical Baseline Delays ... ");
    try
        geom = computeGeometry(cfg);
        assert(geom.numMics == 6, "Expected 6 microphones");
        assert(geom.numPairs == 15, "Expected 15 unique pairs");
        assert(abs(cfg.arrayRadius - 0.13) < 1e-6, "Array radius must be 0.13 m");
        
        % Check max diameter distance D = 0.26m
        maxDist = max(geom.pairDistances);
        assert(abs(maxDist - 0.26) < 1e-4, "Max inter-mic distance must be 0.26 m");
        
        % Check max delay tau_max = 0.26 / 343 = 0.758 ms
        maxTau = max(geom.maxDelays);
        assert(abs(maxTau - (0.26 / 343.0)) < 1e-5, "Max delay must match d/c");
        
        fprintf("PASSED (R = %0.2f m, D = %0.2f m, Max Delay = %0.3f ms)\n", ...
            cfg.arrayRadius, maxDist, maxTau * 1000);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 2: GCC-PHAT Sub-Sample Delay Accuracy
    totalTests = totalTests + 1;
    fprintf("TEST 2: GCC-PHAT Sub-Sample Fractional Delay Accuracy ... ");
    try
        fs = cfg.fs;
        tPulse = (0:1/fs:0.003)';
        pulse = sin(2*pi*1200*tPulse) .* exp(-tPulse/0.001);
        
        testFractionalDelays = [-3.75, -1.20, 0.45, 2.33, 4.80] / fs;
        maxErrorSamples = 0;
        
        for k = 1:numel(testFractionalDelays)
            dSec = testFractionalDelays(k);
            % Sinc fractional delay
            N_sinc = 41;
            dSamples = dSec * fs;
            intD = floor(dSamples);
            fracD = dSamples - intD;
            t_s = (-floor(N_sinc/2) : floor(N_sinc/2))' - fracD;
            h = sinc(t_s);
            
            sig1 = zeros(2048, 1);
            sig2 = zeros(2048, 1);
            sig1(500 : 500 + numel(pulse) - 1) = pulse;
            delayedP = conv(pulse, h, 'same');
            sig2(500 + intD : 500 + intD + numel(delayedP) - 1) = delayedP;
            
            [tauEst, q, ~, ~] = gccPhat(sig1, sig2, fs, 0.005);
            errSamples = abs(tauEst - dSec) * fs;
            maxErrorSamples = max(maxErrorSamples, errSamples);
        end
        
        assert(maxErrorSamples < 0.08, "Sub-sample error exceeded 0.08 samples");
        fprintf("PASSED (Max Error = %0.4f samples, ~%0.2f µs)\n", ...
            maxErrorSamples, (maxErrorSamples / fs) * 1e6);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 3: Physical TDOA Constraint & Impossible Delay Rejection
    totalTests = totalTests + 1;
    fprintf("TEST 3: Physical Delay Limits & Pair Validation ... ");
    try
        geom = computeGeometry(cfg);
        testTDOA = geom.maxDelays * 0.8; % All physically valid
        testQualities = 0.9 * ones(15, 1);
        
        [vMask1, vCount1, ~, ~] = pairValidation(testTDOA, testQualities, cfg, geom);
        assert(vCount1 == 15, "All valid pairs should be accepted");
        
        % Inject 3 impossible delays exceeding d/c
        testTDOA(3) = geom.maxDelays(3) * 2.5; % Impossible
        testTDOA(7) = -geom.maxDelays(7) * 3.0; % Impossible
        testQualities(12) = 0.05; % Below quality threshold
        
        [vMask2, vCount2, ~, ~] = pairValidation(testTDOA, testQualities, cfg, geom);
        assert(~vMask2(3) && ~vMask2(7) && ~vMask2(12), "Impossible and low-quality pairs must be rejected");
        assert(vCount2 == 12, "Expected 12 valid pairs after rejection");
        
        fprintf("PASSED (Accurately rejected %d invalid pairs)\n", 15 - vCount2);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 4: Synchronized Multi-Channel Circular Ring Buffer
    totalTests = totalTests + 1;
    fprintf("TEST 4: Synchronized Circular Ring Buffer Integrity ... ");
    try
        buf = CircularBuffer(2400, 6);
        block1 = ones(512, 6) * 1.5;
        block2 = ones(512, 6) * 2.5;
        block3 = ones(512, 6) * 3.5;
        
        buf.write(block1);
        buf.write(block2);
        buf.write(block3);
        
        [win, isComp] = buf.extractEventWindow(400, 1000);
        assert(isComp, "Event window must be extracted successfully");
        assert(size(win, 1) == 1400 && size(win, 2) == 6, "Extracted window dimensions incorrect");
        
        % Verify chronological order
        tail = win(end - 100 : end, :);
        assert(all(abs(tail(:) - 3.5) < 1e-9), "Buffer chronological order preserved");
        
        fprintf("PASSED (1400x6 Window Extracted, Multi-Channel Synced)\n");
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 5: Impulsive Event Detector & Coincidence Voting
    totalTests = totalTests + 1;
    fprintf("TEST 5: Impulsive Acoustic Event Detector ... ");
    try
        % 1. Ambient noise without gunshot
        quietData = randn(2400, 6) * 0.02;
        [det1, ~] = eventDetector(quietData, cfg, -inf);
        assert(~det1, "Detector must not trigger on ambient noise");
        
        % 2. Synthetic gunshot impulse at 42.37°
        [shotData, ~, ~, ~] = simulateGunshot(42.37, 5.0, 25.0, cfg);
        [det2, meta2] = eventDetector(shotData, cfg, -inf);
        assert(det2, "Detector must trigger on gunshot impulse");
        assert(meta2.triggeredChannels >= 3, "At least 3 channels must trigger");
        assert(meta2.peakRatio >= cfg.trigger.peakRatio, "Peak ratio must exceed threshold");
        
        % 3. Refractory Cooldown Test
        recentTic = tic;
        [det3, ~] = eventDetector(shotData, cfg, recentTic);
        assert(~det3, "Detector must honor cooldown refractory period");
        
        fprintf("PASSED (Triggered %d channels, Peak Ratio = %0.1f, SNR = %0.1f dB)\n", ...
            meta2.triggeredChannels, meta2.peakRatio, meta2.snr_dB);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 6: SRP-PHAT Spatial Beamformer
    totalTests = totalTests + 1;
    fprintf("TEST 6: SRP-PHAT Spatial Beamforming Peak Accuracy ... ");
    try
        testAngle = 135.0;
        [shotData, ~, ~, ~] = simulateGunshot(testAngle, 5.0, 30.0, cfg);
        cleanData = removeDC(shotData);
        filtData  = bandpassFilter(cleanData, cfg);
        
        geom = computeGeometry(cfg);
        [~, ~, R_corrs, lags] = estimateTDOA(filtData, cfg, geom);
        [P_srp, ~, bestAngle] = srpPhat(R_corrs, lags, cfg, geom);
        
        angErr = min(abs(bestAngle - testAngle), 360 - abs(bestAngle - testAngle));
        assert(angErr <= 2.0, sprintf("SRP error %0.2f exceeds 2.0 degrees", angErr));
        
        fprintf("PASSED (True: %0.1f°, SRP Peak: %0.1f°, Error: %0.2f°)\n", ...
            testAngle, bestAngle, angErr);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 7: Hybrid Localization & Continuous Angle Estimation
    totalTests = totalTests + 1;
    fprintf("TEST 7: Hybrid GCC+SRP & Continuous DOA Estimation ... ");
    try
        testBearings = [0.0, 42.37, 90.0, 135.5, 180.0, 215.8, 270.0, 330.25];
        maxAngularError = 0;
        totalAngularError = 0;
        
        for k = 1:numel(testBearings)
            trueAngle = testBearings(k);
            [shotData, ~, ~, ~] = simulateGunshot(trueAngle, 5.0, 25.0, cfg);
            
            cleanData = removeDC(shotData);
            filtData  = bandpassFilter(cleanData, cfg);
            normData  = normalizeChannels(filtData, cfg);
            
            res = hybridDOA(normData, cfg);
            
            % Circular angular difference: min(|a - b|, 360 - |a - b|)
            err = min(abs(res.angle - trueAngle), 360 - abs(res.angle - trueAngle));
            maxAngularError = max(maxAngularError, err);
            totalAngularError = totalAngularError + err;
            
            assert(err < 2.5, sprintf("DOA Error %0.2f° exceeds 2.5° for target %0.2f°", err, trueAngle));
            assert(res.confidence >= 0.70, sprintf("Confidence %0.2f too low for clear signal", res.confidence));
        end
        
        meanAngularError = totalAngularError / numel(testBearings);
        fprintf("PASSED (Mean Error = %0.2f°, Max Error = %0.2f° across 8 bearings)\n", ...
            meanAngularError, maxAngularError);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 8: Sub-Degree Quadratic Angle Interpolation
    totalTests = totalTests + 1;
    fprintf("TEST 8: Sub-Degree Quadratic Peak Interpolation ... ");
    try
        % Synthetic parabola centered at 42.37 degrees
        az = (0:359)';
        truePeak = 42.37;
        % Gaussian-like peak on circle
        circDist = min(abs(az - truePeak), 360 - abs(az - truePeak));
        P_synth = exp(- (circDist.^2) / (2 * 2.5^2));
        
        [~, bestI] = max(P_synth);
        [interpAngle, ~] = quadraticInterpolation(P_synth, bestI, az);
        
        interpError = abs(interpAngle - truePeak);
        assert(interpError < 0.15, sprintf("Interpolation error %0.3f° too large", interpError));
        
        % Wrap-around test at 359.8 degrees
        truePeakWrap = 359.8;
        circDistWrap = min(abs(az - truePeakWrap), 360 - abs(az - truePeakWrap));
        P_wrap = exp(- (circDistWrap.^2) / (2 * 2.5^2));
        [~, bestIWrap] = max(P_wrap);
        [interpAngleWrap, ~] = quadraticInterpolation(P_wrap, bestIWrap, az);
        
        wrapError = min(abs(interpAngleWrap - truePeakWrap), 360 - abs(interpAngleWrap - truePeakWrap));
        assert(wrapError < 0.15, sprintf("Wrap interpolation error %0.3f° too large", wrapError));
        
        fprintf("PASSED (Target: 42.37° -> Interp: %0.2f°, Target: 359.8° -> Interp: %0.2f°)\n", ...
            interpAngle, interpAngleWrap);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 9: Channel Timing Multiplexing Skew Calibration
    totalTests = totalTests + 1;
    fprintf("TEST 9: Channel Timing Multiplexing Calibration ... ");
    try
        [offsets, report] = channelTimingCalibration([], 0.0, cfg);
        assert(numel(offsets) == 6, "Expected 6 channel timing offsets");
        assert(report.rmsResidualMicroseconds < 25.0, "RMS timing error must be < 25 µs");
        
        fprintf("PASSED (Calibrated 6 Channels, RMS Residual = %0.2f µs)\n", report.rmsResidualMicroseconds);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Test 10: Full Processing Latency Benchmark (< 50 ms budget)
    totalTests = totalTests + 1;
    fprintf("TEST 10: Event Processing Speed Benchmark (< 50 ms) ... ");
    try
        [shotData, ~, ~, ~] = simulateGunshot(75.5, 5.0, 25.0, cfg);
        
        % Benchmark 10 consecutive event processing runs
        times = zeros(10, 1);
        for run = 1:10
            t0 = tic;
            cleanData = removeDC(shotData);
            filtData  = bandpassFilter(cleanData, cfg);
            normData  = normalizeChannels(filtData, cfg);
            res = hybridDOA(normData, cfg);
            times(run) = toc(t0) * 1000.0;
        end
        
        meanTime = mean(times);
        maxTime  = max(times);
        assert(meanTime < 50.0, sprintf("Mean processing time %0.2f ms exceeded 50 ms budget", meanTime));
        
        fprintf("PASSED (Mean Latency = %0.2f ms, Max Latency = %0.2f ms)\n", meanTime, maxTime);
        passedTests = passedTests + 1;
    catch ME
        fprintf("FAILED: %s\n", ME.message);
    end

    %% Summary
    fprintf("\n----------------------------------------------------------------------\n");
    fprintf("TEST SUITE SUMMARY: %d of %d tests PASSED (%0.1f%% Success Rate)\n", ...
        passedTests, totalTests, (passedTests / totalTests) * 100);
    fprintf("----------------------------------------------------------------------\n\n");

    testResults = struct();
    testResults.totalTests  = totalTests;
    testResults.passedTests = passedTests;
    testResults.allPassed   = (passedTests == totalTests);
end
