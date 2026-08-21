# Live Acoustic Gunshot Localization & 360° Tracking System
## National Instruments NI USB-6221 DAQ & 6-Microphone Circular Array

---

## 1. System Overview

The **Live Acoustic Gunshot Localization System** is a research-grade MATLAB digital signal processing platform engineered for real-time detection, Direction of Arrival (DOA) estimation, and tracking of acoustic gunshot playback impulses (muzzle blast / shockwave transients). 

The system continuously samples 6 MAX4466 electret microphone amplifiers arranged in a **26 cm diameter circular array** via a **National Instruments NI USB-6221 DAQ** at **40,000 samples/sec per channel**. When an impulsive acoustic event occurs, the system triggers, extracts a synchronized 60 ms event window ($10\text{ ms pre-trigger} + 50\text{ ms post-trigger}$), performs multi-pair **GCC-PHAT** cross-correlation with sub-sample parabolic interpolation, validates physical acoustic propagation constraints across all 15 microphone pairs, executes **Steered Response Power (SRP-PHAT)** spatial beamforming, fuses the spatial likelihood spectra ($0.6\text{ GCC} + 0.4\text{ SRP}$), computes continuous sub-degree DOA ($0^\circ \le \theta < 360^\circ$), updates a live 360° polar radar and oscilloscope dashboard, and automatically logs complete event telemetry to disk.

---

## 2. Hardware Architecture & Array Geometry

```
                           90° (+Y)
                              ▲
                              │
                    M2 ◄──────┼──────► M1
                   (120°)     │       (60°)
                              │
  180° (-X) ◄────── M3 ───────O─────── M6 ──────► 0° (+X)
                   (180°)     │       (0°)
                              │
                    M4 ◄──────┼──────► M5
                   (240°)     │       (300°)
                              │
                              ▼
                          270° (-Y)
```

### Physical Specifications
- **DAQ Device:** National Instruments NI USB-6221 (`Dev1`)
- **Analog Input Channels:** `ai0`, `ai1`, `ai2`, `ai3`, `ai4`, `ai5` (Channels 0–5)
- **Sampling Rate:** $f_s = 40,000\text{ Hz}$ (40 kS/s per channel; aggregate 240 kS/s)
- **Transducers:** 6 $\times$ MAX4466 adjustable-gain electret microphone preamplifiers
- **Array Geometry:** Circular coplanar array, Radius $R = 0.13\text{ m}$ (13 cm), Diameter $D = 0.26\text{ m}$ (26 cm)
- **Sensor Spacing:** $60^\circ$ equal angular spacing, microphones facing outward

### Coordinate & Microphone Mapping
| Channel | Mic Index | Azimuth ($\theta$) | X Position (m) | Y Position (m) | Z Position (m) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **AI0** | **Mic 1** | $60.0^\circ$ | $+0.0650$ | $+0.1126$ | $0.0000$ |
| **AI1** | **Mic 2** | $120.0^\circ$ | $-0.0650$ | $+0.1126$ | $0.0000$ |
| **AI2** | **Mic 3** | $180.0^\circ$ | $-0.1300$ | $+0.0000$ | $0.0000$ |
| **AI3** | **Mic 4** | $240.0^\circ$ | $-0.0650$ | $-0.1126$ | $0.0000$ |
| **AI4** | **Mic 5** | $300.0^\circ$ | $+0.0650$ | $-0.1126$ | $0.0000$ |
| **AI5** | **Mic 6** | $0.0^\circ$ | $+0.1300$ | $+0.0000$ | $0.0000$ |

---

## 3. Project Directory Structure

```
Gunshot_Localization/
├── main_live.m                         # Master live acquisition & GUI execution script
├── config.m                            # Central configuration & array geometry definition
├── acquisition/
│   ├── initDAQ.m                       # NI USB-6221 DAQ / Simulation initialization
│   ├── readBlock.m                     # Continuous multi-channel block reader
│   └── stopDAQ.m                       # Safe DAQ termination & resource release
├── detection/
│   ├── CircularBuffer.m                # Pre-allocated 6-channel synchronized ring buffer
│   └── eventDetector.m                 # Adaptive noise floor (MAD), energy ratio & coincidence detector
├── preprocessing/
│   ├── removeDC.m                      # Baseline zero-mean offset subtraction
│   ├── bandpassFilter.m                # 4th-order zero-phase Butterworth bandpass (200 - 4000 Hz)
│   └── normalizeChannels.m             # Channel gain compensation & peak normalization
├── localization/
│   ├── computeGeometry.m               # 6-mic array coordinates, 15-pair baselines & delay lookups
│   ├── gccPhat.m                       # GCC-PHAT with 3-point parabolic sub-sample peak refinement
│   ├── estimateTDOA.m                  # 15-pair TDOA extraction & multiplexing skew compensation
│   ├── pairValidation.m                # Physical delay constraint (|tau| <= d/c) & triplet validation
│   ├── srpPhat.m                       # Vectorized Steered Response Power (SRP-PHAT) beamformer
│   ├── hybridDOA.m                     # Spatial fusion (0.6 GCC + 0.4 SRP) & DOA peak search
│   ├── quadraticInterpolation.m        # Continuous sub-degree DOA refinement (e.g. 42.37°)
│   └── confidenceScore.m               # Multi-factor normalized confidence score (PSLR, valid ratio)
├── calibration/
│   ├── channelTimingCalibration.m      # Multiplexed ADC inter-channel delay calibration
│   └── microphoneGainCalibration.m     # Electret sensitivity & potentiometer balancing
├── visualization/
│   ├── initGUI.m                       # High-resolution dark-themed live dashboard & controls
│   ├── updateDashboard.m               # Real-time oscilloscope, polar radar & HUD refresh
│   ├── updateRadar.m                   # 360° polar radar compass with confidence arc & history
│   └── saveDashboardImage.m            # Figure snapshot exporter for event archival
├── events/
│   ├── logEvent.m                      # Structured multi-format event logger
│   └── event_XXXX/                     # Timestamped event directories
├── tests/
│   ├── simulateGunshot.m               # Physics-based gunshot acoustic impulse generator
│   └── runAllTests.m                   # Comprehensive 10-test verification suite
├── README.md                           # Operational manual and hardware setup guide
└── ALGORITHM_WORKING.md                # In-depth DSP theory, mathematical derivations & benchmarks
```

---

## 4. Quick Start Guide

### Prerequisites
- **MATLAB:** Version R2020a through R2024b (tested on R2023b).
- **Toolboxes:** Signal Processing Toolbox, Data Acquisition Toolbox.
- **Hardware:** NI DAQ-6221 (or run in Simulation Mode without hardware).

### Running in Live Hardware Mode
1. Connect the NI USB-6221 DAQ card to your PC.
2. Connect MAX4466 analog output pins to `AI0`, `AI1`, `AI2`, `AI3`, `AI4`, `AI5` with common ground (`AI GND` / `AGND`).
3. Launch MATLAB and navigate to the project directory:
   ```matlab
   cd('s:/GUNSHOT LOCALIZATION');
   ```
4. Ensure `cfg.simulationMode = false;` in `config.m` (or toggle the **MODE** button on the GUI).
5. Run the master application:
   ```matlab
   main_live
   ```

### Running in Simulation Mode (No Hardware Required)
1. Open MATLAB and set `cfg.simulationMode = true;` in `config.m` (or press **MODE: SIMULATION** on the GUI).
2. Execute `main_live`:
   ```matlab
   main_live
   ```
3. The synthetic audio streamer will continuously generate ambient room noise and inject calibrated gunshot playback impulses from bearings such as $42.37^\circ, 120.0^\circ, 215.5^\circ, 330.0^\circ$.
4. Observe the live oscilloscope traces, polar radar compass beam, confidence score, and automatic event logging.

### Running Automated Test Suite
To verify all signal processing algorithms, geometry lookups, sub-sample parabolic interpolation, and latency budgets:
```matlab
testResults = runAllTests();
```

---

## 5. Event Archival & Telemetry Format

Whenever a gunshot impulse triggers the system, an event folder is automatically created under `events/event_XXXX/` containing:

| File | Description |
| :--- | :--- |
| **`raw.csv`** | Synchronized 6-channel raw voltage data ($2400 \times 6$ matrix at 40 kS/s) |
| **`filtered.csv`** | Zero-phase bandpass filtered audio data ($2400 \times 6$) |
| **`tdoa.csv`** | 15 microphone pairs: measured TDOAs, theoretical TDOAs, residuals, valid flags, and qualities |
| **`spatialResponse.csv`** | $360^\circ$ spatial spectra: $P_{\text{GCC}}(\theta)$, $P_{\text{SRP}}(\theta)$, and $P_{\text{Fused}}(\theta)$ |
| **`metadata.json`** | Event metadata (timestamp, estimated DOA, confidence %, valid pairs, SNR dB, processing time) |
| **`dashboard.png`** | High-resolution snapshot of the GUI dashboard at the detection instant |

### Sample `metadata.json`
```json
{
  "eventID": "event_0001",
  "timestamp": "2026-08-21 10:30:15.245",
  "estimatedAngleDeg": 42.37,
  "coarseAngleDeg": 42,
  "confidence": 0.942,
  "confidencePct": 94.2,
  "validPairs": 15,
  "totalPairs": 15,
  "processingTimeMs": 18.4,
  "snr_dB": 28.5,
  "peakRatio": 14.8,
  "triggeredChannels": 6,
  "samplingRateHz": 40000,
  "arrayRadiusMeters": 0.13,
  "speedOfSoundM_S": 343.0,
  "device": "Dev1",
  "simulationMode": false
}
```

---

## 6. Calibration Procedures

### Channel Timing Calibration (Multiplexed ADC Skew)
The NI USB-6221 uses a single SAR ADC multiplexed across analog input channels. At 40 kS/s per channel across 6 channels (240 kS/s aggregate), consecutive channels experience an inter-channel multiplexing phase skew ($\approx 4.17\text{ }\mu\text{s}$).

To calibrate:
1. Position a calibration sound source at $0.0^\circ$ (+X axis, directly facing Mic 6) or at the array center ($R=0$).
2. Run the calibration routine:
   ```matlab
   [offsets, report] = channelTimingCalibration([], 0.0, cfg);
   ```
3. The routine computes the optimal per-channel timing delays via constrained least-squares and saves them to `calibration/channel_timing_cal.mat`.

### Microphone Gain Calibration
To balance potentiometer gain settings across all 6 MAX4466 modules:
1. Play a diffuse broadband noise signal or acoustic calibration tone.
2. Run:
   ```matlab
   [gainOffsets, report] = microphoneGainCalibration(recordingData, cfg);
   ```
3. Gain scale factors are saved to `calibration/microphone_gain_cal.mat` and loaded by `normalizeChannels.m`.
