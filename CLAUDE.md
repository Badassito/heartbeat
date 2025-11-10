# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Heartbeat is a C++ implementation of remote photoplethysmography (rPPG) for measuring heart rate without skin contact. It analyzes video recordings or live camera feeds of faces to detect subtle changes in skin color caused by blood flow, using this information to estimate heart rate.

## Build and Development Commands

### Building the Project

```sh
# Build using Makefile (macOS)
make

# Alternative compilation for Ubuntu (OpenCV 3.1+)
g++ -std=c++11 Heartbeat.cpp opencv.cpp RPPG.cpp `pkg-config --cflags --libs opencv` -o Heartbeat

# Clean build artifacts
make clean

# Clean all including dependencies
make dist-clean
```

### Running the Application

```sh
# Run with webcam (live mode)
./Heartbeat

# Run with video file
./Heartbeat -i path/to/video.mp4

# Example with common options
./Heartbeat -i input.mp4 -rppg pca -facedet deep -r 1 -f 1 -gui true -log true
```

## Architecture

### Core Components

**Heartbeat** (Heartbeat.cpp/hpp)
- Entry point with command-line argument parsing
- Initializes video capture (webcam or file)
- Main processing loop that feeds frames to RPPG module
- Handles frame downsampling and GUI display

**RPPG** (RPPG.cpp/hpp)
- Core rPPG algorithm implementation
- Manages the complete pipeline: face detection → tracking → signal extraction → heart rate estimation
- Supports three rPPG algorithms:
  - `g`: Green channel only (simple, fast)
  - `pca`: RGB channels with PCA (more robust)
  - `xminay`: Alternative color space method
- Supports two face detection methods:
  - `haar`: Haar cascade classifier (fast, less accurate)
  - `deep`: Deep neural network (slower, more accurate)

**opencv** (opencv.cpp/hpp)
- Signal processing utilities and filters
- Key functions:
  - `normalization()`: Signal normalization
  - `denoise()`: Jump detection and removal
  - `detrend()`: Removes linear trends from signal
  - `bandpass()`: Bandpass filtering for heart rate range
  - `timeToFrequency()` / `frequencyToTime()`: FFT operations
  - `pcaComponent()`: PCA for multi-channel signals
  - `movingAverage()`: Smoothing filter

### Processing Pipeline

1. **Frame Capture**: Grab RGB frame from video source, convert to grayscale for face detection
2. **Face Detection**: Initial detection using Haar cascade or DNN, then frame-to-frame tracking
3. **ROI Extraction**: Define region of interest on detected face with mask
4. **Signal Extraction**: Extract color signal from face ROI using selected rPPG algorithm
5. **Signal Processing**: Apply denoising, detrending, and bandpass filtering
6. **Heart Rate Estimation**: FFT analysis to find dominant frequency in valid BPM range (42-240)
7. **Visualization & Logging**: Display results in GUI and/or log to CSV files

### Key Design Patterns

- **Sliding Window**: Signal buffer with configurable min/max size for temporal analysis
- **Periodic Tasks**: Face re-detection and heart rate estimation run at configurable frequencies
- **State Management**: Tracks face validity, triggers re-detection when tracking fails
- **Frequency Analysis**: Uses power spectrum to identify heart rate from periodic color changes

## Dependencies

- **OpenCV**: Core dependency for computer vision operations
  - Headers expected in: `/usr/local/include/opencv4` or `/usr/include/opencv4`
  - Required modules: core, dnn, highgui, imgcodecs, imgproc, objdetect, video, videoio
- **C++11**: Required language standard

## Required Data Files

- `haarcascade_frontalface_alt.xml`: Haar cascade for face detection (required)
- `opencv/deploy.prototxt`: DNN proto file (required for deep face detection)
- `opencv/res10_300x300_ssd_iter_140000.caffemodel`: DNN model (required for deep face detection)

## Command-Line Options

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `-i` | filepath | (none) | Input video file; omit for webcam |
| `-rppg` | g, pca, xminay | g | rPPG algorithm variant |
| `-facedet` | haar, deep | haar | Face detection method |
| `-r` | float | 1 | Face re-detection interval (seconds) |
| `-f` | float | 1 | Heart rate sampling frequency (Hz) |
| `-max` | int | 5 | Maximum signal window size |
| `-min` | int | 5 | Minimum signal window size |
| `-gui` | true, false | true | Display GUI |
| `-log` | true, false | false | Enable detailed logging |
| `-ds` | int | 1 | Downsample factor (process every nth frame) |

## Key Constants

Defined in RPPG.cpp:
- `LOW_BPM`: 42 - Minimum valid heart rate
- `HIGH_BPM`: 240 - Maximum valid heart rate
- `REL_MIN_FACE_SIZE`: 0.4 - Minimum face size as fraction of frame
- `MAX_CORNERS`: 10 - Maximum corners for tracking
- `MIN_CORNERS`: 5 - Minimum corners for valid tracking
- `QUALITY_LEVEL`: 0.01 - Quality threshold for corner detection
- `MIN_DISTANCE`: 25 - Minimum distance between corners

## Output Files

When logging is enabled (`-log true`), generates CSV files:
- `{input}_rppg={alg}_facedet={det}_min={min}_max={max}_ds={ds}_bpm.csv`: Sampled heart rate data
- `{input}_rppg={alg}_facedet={det}_min={min}_max={max}_ds={ds}_bpmAll.csv`: All heart rate estimates

Format: `time;face_valid;mean;min;max` and `time;face_valid;bpm`
