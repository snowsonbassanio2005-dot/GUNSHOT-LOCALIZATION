function [eventDir, eventID] = logEvent(rawWindow, filtWindow, locRes, eventMeta, cfg, figHandle)
% LOGEVENT - Automated Event Archival and Telemetry Logging
%
% PURPOSE:
%   Persists detected acoustic impulse events into sequential directories
%   (events/event_0001/, events/event_0002/, etc.) with full raw waveforms,
%   filtered waveforms, 15-pair TDOAs, 360° spatial spectra, JSON metadata,
%   and high-resolution dashboard PNG snapshots. Completely fault-tolerant.
%
% INPUTS:
%   rawWindow  - [N x 6] Raw multi-channel voltage samples
%   filtWindow - [N x 6] Preprocessed / bandpass filtered audio samples
%   locRes     - Hybrid localization results structure from hybridDOA()
%   eventMeta  - Event detector diagnostics from eventDetector()
%   cfg        - Configuration structure
%   figHandle  - (Optional) GUI Figure handle for dashboard screenshot capture
%
% OUTPUTS:
%   eventDir - Absolute path to the created event directory
%   eventID  - Formatted event identifier string (e.g. "event_0001")

    eventDir = "";
    eventID  = "";

    if nargin < 5 || isempty(cfg)
        cfg = config();
    end

    try
        baseDir = cfg.logging.baseDir;
        if ~exist(baseDir, 'dir')
            mkdir(baseDir);
        end

        % Determine next sequential event ID
        existingDirs = dir(fullfile(baseDir, 'event_*'));
        maxIndex = 0;
        for k = 1:numel(existingDirs)
            if existingDirs(k).isdir
                match = regexp(existingDirs(k).name, '^event_(\d+)$', 'tokens');
                if ~isempty(match)
                    num = str2double(match{1}{1});
                    if num > maxIndex
                        maxIndex = num;
                    end
                end
            end
        end

        nextIndex = maxIndex + 1;
        eventID = sprintf("event_%04d", nextIndex);
        eventDir = fullfile(baseDir, eventID);
        if ~exist(eventDir, 'dir')
            mkdir(eventDir);
        end

        %% 1. Save Raw Waveforms (raw.csv)
        if cfg.logging.saveRawCsv && ~isempty(rawWindow)
            try
                rawCsvPath = fullfile(eventDir, 'raw.csv');
                fid = fopen(rawCsvPath, 'w');
                if fid > 0
                    fprintf(fid, "AI0,AI1,AI2,AI3,AI4,AI5\n");
                    for row = 1:size(rawWindow, 1)
                        fprintf(fid, "%0.6f,%0.6f,%0.6f,%0.6f,%0.6f,%0.6f\n", ...
                            rawWindow(row, 1), rawWindow(row, 2), rawWindow(row, 3), ...
                            rawWindow(row, 4), rawWindow(row, 5), rawWindow(row, 6));
                    end
                    fclose(fid);
                end
            catch
            end
        end

        %% 2. Save Filtered Waveforms (filtered.csv)
        if cfg.logging.saveFiltCsv && ~isempty(filtWindow)
            try
                filtCsvPath = fullfile(eventDir, 'filtered.csv');
                fid = fopen(filtCsvPath, 'w');
                if fid > 0
                    fprintf(fid, "AI0_Filt,AI1_Filt,AI2_Filt,AI3_Filt,AI4_Filt,AI5_Filt\n");
                    for row = 1:size(filtWindow, 1)
                        fprintf(fid, "%0.6f,%0.6f,%0.6f,%0.6f,%0.6f,%0.6f\n", ...
                            filtWindow(row, 1), filtWindow(row, 2), filtWindow(row, 3), ...
                            filtWindow(row, 4), filtWindow(row, 5), filtWindow(row, 6));
                    end
                    fclose(fid);
                end
            catch
            end
        end

        %% 3. Save TDOA Analysis (tdoa.csv)
        if cfg.logging.saveTdoaCsv && isfield(locRes, 'tdoa')
            try
                geom = computeGeometry(cfg);
                tdoaCsvPath = fullfile(eventDir, 'tdoa.csv');
                fid = fopen(tdoaCsvPath, 'w');
                if fid > 0
                    fprintf(fid, "PairIndex,MicA,MicB,TDOA_Measured_s,TDOA_Theoretical_s,Residual_s,ValidFlag,Quality\n");
                    for k = 1:geom.numPairs
                        mA = geom.pairs(k, 1);
                        mB = geom.pairs(k, 2);
                        tMeas = locRes.tdoa(k);
                        tTheor = locRes.tauTheor(k);
                        tResid = locRes.tdoaResiduals(k);
                        vFlag = int32(locRes.validMask(k));
                        qual = locRes.qualities(k);
                        fprintf(fid, "%d,%d,%d,%0.8f,%0.8f,%0.8f,%d,%0.4f\n", ...
                            k, mA, mB, tMeas, tTheor, tResid, vFlag, qual);
                    end
                    fclose(fid);
                end
            catch
            end
        end

        %% 4. Save Spatial Response Spectrum (spatialResponse.csv)
        if cfg.logging.saveSrpCsv && isfield(locRes, 'P_fused')
            try
                srpCsvPath = fullfile(eventDir, 'spatialResponse.csv');
                fid = fopen(srpCsvPath, 'w');
                if fid > 0
                    fprintf(fid, "Azimuth_deg,P_GCC,P_SRP,P_Fused\n");
                    for a = 1:numel(locRes.azGridDeg)
                        fprintf(fid, "%d,%0.6f,%0.6f,%0.6f\n", ...
                            locRes.azGridDeg(a), locRes.P_gcc(a), locRes.P_srp(a), locRes.P_fused(a));
                    end
                    fclose(fid);
                end
            catch
            end
        end

        %% 5. Save Metadata (metadata.json)
        if cfg.logging.saveMetaJson
            try
                metaJsonPath = fullfile(eventDir, 'metadata.json');
                
                meta = struct();
                meta.eventID           = char(eventID);
                meta.timestamp         = char(eventMeta.timestamp);
                meta.estimatedAngleDeg = double(locRes.angle);
                meta.coarseAngleDeg    = double(locRes.coarseAngle);
                meta.confidence        = double(locRes.confidence);
                meta.confidencePct     = double(locRes.confidence * 100.0);
                meta.validPairs        = double(locRes.validPairs);
                meta.totalPairs        = 15;
                meta.processingTimeMs  = double(locRes.processingTimeMs);
                meta.snr_dB            = double(eventMeta.snr_dB);
                meta.peakRatio         = double(eventMeta.peakRatio);
                meta.triggeredChannels = double(eventMeta.triggeredChannels);
                meta.samplingRateHz    = double(cfg.fs);
                meta.arrayRadiusMeters = double(cfg.arrayRadius);
                meta.speedOfSoundM_S   = double(cfg.c);
                meta.device            = char(cfg.deviceName);
                meta.simulationMode    = logical(cfg.simulationMode);

                try
                    jsonText = jsonencode(meta, 'PrettyPrint', true);
                catch
                    jsonText = jsonencode(meta);
                end
                fid = fopen(metaJsonPath, 'w');
                if fid > 0
                    fprintf(fid, "%s", jsonText);
                    fclose(fid);
                end
            catch
            end
        end

        %% 6. Save Dashboard Screenshot (dashboard.png)
        if cfg.logging.saveImagePng && nargin >= 6 && ~isempty(figHandle) && isgraphics(figHandle)
            try
                pngPath = fullfile(eventDir, 'dashboard.png');
                saveas(figHandle, pngPath);
            catch
            end
        end

        fprintf("[EVENT LOGGED] %s -> Angle: %0.2f° | Conf: %0.1f%% | Valid: %d/15 | Latency: %0.1f ms\n", ...
            eventID, locRes.angle, locRes.confidence * 100, locRes.validPairs, locRes.processingTimeMs);

    catch mainLogME
        fprintf("[WARNING] logEvent exception (safe fallback): %s\n", mainLogME.message);
    end
end
