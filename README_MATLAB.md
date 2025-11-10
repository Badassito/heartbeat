# Heartbeat rPPG - MATLAB Implementation

This is a single-file MATLAB implementation of the Heartbeat remote photoplethysmography (rPPG) system for measuring heart rate without skin contact.

## Features

- **Single script** - All functionality in one `.m` file
- **Webcam or video file** - Process live webcam feed or recorded videos
- **Multiple algorithms** - Green channel (`g`) or PCA-based (`pca`)
- **Real-time visualization** - Live display of face tracking and heart rate estimation
- **KLT tracking** - Efficient face tracking using Kanade-Lucas-Tomasi algorithm
- **Robust signal processing** - Denoising, detrending, and filtering pipeline

## Requirements

- MATLAB R2018b or later
- Computer Vision Toolbox
- Image Processing Toolbox
- Webcam (for live mode) or video file

## Quick Start

### Using Webcam

```matlab
% Basic usage with default settings (green channel algorithm)
heartbeat_rppg()

% Use PCA algorithm
heartbeat_rppg('', 'pca')
```

### Using Video File

```matlab
% Process video file with green channel algorithm
heartbeat_rppg('path/to/video.mp4')

% Process video file with PCA algorithm
heartbeat_rppg('path/to/video.mp4', 'pca')

% Process without GUI (faster)
heartbeat_rppg('path/to/video.mp4', 'g', false)
```

## Function Signature

```matlab
heartbeat_rppg(videoFile, algorithm, showGUI)
```

**Parameters:**
- `videoFile` (optional) - Path to video file. Omit or use empty string `''` for webcam
- `algorithm` (optional) - `'g'` for green channel only, or `'pca'` for PCA-based (default: `'g'`)
- `showGUI` (optional) - `true` to show real-time visualization, `false` for headless processing (default: `true`)

## How It Works

### Processing Pipeline

1. **Face Detection** - Detect face using Viola-Jones cascade classifier
2. **Point Tracking** - Track facial features using KLT algorithm
3. **ROI Extraction** - Extract forehead region (optimal for rPPG)
4. **Signal Extraction** - Compute mean RGB values from ROI over time
5. **Signal Processing**:
   - Denoise (eliminate jumps from face re-detection)
   - Normalize (zero mean, unit variance)
   - Detrend (remove low-frequency trends)
   - Moving average filter (smooth signal)
6. **Heart Rate Estimation** - FFT analysis to find dominant frequency in valid BPM range (42-240)

### Algorithm Comparison

**Green Channel (`g`)**
- Uses only the green channel (most sensitive to blood volume changes)
- Faster and simpler
- Good for well-lit, stable conditions

**PCA (`pca`)**
- Uses all RGB channels with Principal Component Analysis
- Selects component with strongest peak in valid heart rate range
- More robust to lighting variations and noise
- Slightly slower but more accurate

## Parameters

The script uses the following default parameters (can be modified in the code):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LOW_BPM` | 42 | Minimum valid heart rate (BPM) |
| `HIGH_BPM` | 240 | Maximum valid heart rate (BPM) |
| `MIN_SIGNAL_SIZE` | 5 | Minimum signal window (seconds) |
| `MAX_SIGNAL_SIZE` | 30 | Maximum signal window (seconds) |
| `RESCAN_FREQUENCY` | 1 Hz | Face re-detection interval |
| `SAMPLING_FREQUENCY` | 1 Hz | Heart rate estimation frequency |
| `REL_MIN_FACE_SIZE` | 0.4 | Minimum face size (fraction of frame) |
| `MAX_CORNERS` | 10 | Maximum KLT tracking points |
| `MIN_CORNERS` | 5 | Minimum points for valid tracking |

## Output

When running with GUI enabled (default), you'll see:

- **Left panel**: Video with overlays showing:
  - Yellow box: Detected face
  - Green box: ROI (forehead region)
  - Green crosses: KLT tracking points

- **Right panel**:
  - During accumulation: Raw processed signal
  - After sufficient samples: Power spectrum with current BPM estimate

- **Top center**: Current heart rate in BPM (green when valid, red when acquiring)

## Performance Tips

1. **Lighting** - Ensure good, consistent lighting on the face
2. **Stability** - Keep face relatively still and centered
3. **Distance** - Position camera so face occupies ~40% or more of frame
4. **Wait time** - Allow 5-10 seconds for initial stabilization
5. **Algorithm** - Try both `g` and `pca` to see which works better for your conditions

## Troubleshooting

**"No face found"**
- Ensure adequate lighting
- Move closer to camera
- Face camera directly

**"Tracking lost"**
- Face moved too quickly
- Reduce head movement
- Improve lighting

**BPM seems incorrect**
- Allow more time for signal accumulation
- Check lighting conditions
- Try different algorithm (`g` vs `pca`)
- Ensure face is well-lit and stable

## Implementation Notes

This MATLAB version closely follows the C++ implementation but with some adaptations:

- Uses MATLAB's built-in Viola-Jones detector instead of Haar/DNN
- Simplified geometric transform for face box updates
- Native MATLAB functions for signal processing (FFT, PCA, filtering)
- Single file for easy distribution and modification

## Example Usage Scenarios

```matlab
% Test with webcam using PCA (most robust)
heartbeat_rppg('', 'pca')

% Batch process video file without display
heartbeat_rppg('meeting_recording.mp4', 'pca', false)

% Quick test with webcam (fastest)
heartbeat_rppg('', 'g')

% Analyze pre-recorded video with green channel
heartbeat_rppg('heart_rate_test.avi', 'g', true)
```

## Limitations

- Requires visible face throughout processing
- Sensitive to lighting changes
- Motion artifacts can affect accuracy
- Not suitable for clinical/medical use
- Best results with 30+ fps video

## References

Based on the original Heartbeat C++ implementation by Philipp Rouast:
- https://github.com/prouast/heartbeat

For more information on rPPG:
- [Remote Photoplethysmography: Evaluation of Contactless Heart Rate Measurement](https://www.rouast.com/pdf/rouast2016remote_b.pdf)
- [Remote heart rate measurement using low-cost RGB face video](https://www.researchgate.net/publication/306285292)

## License

GPL-3.0 (same as original C++ implementation)
