function heartbeat_rppg(varargin)
% HEARTBEAT_RPPG - Measure heart rate using remote photoplethysmography (rPPG)
%
% Usage:
%   heartbeat_rppg()                           % Use webcam
%   heartbeat_rppg('video.mp4')               % Use video file
%   heartbeat_rppg('video.mp4', 'pca')        % Specify rPPG algorithm
%   heartbeat_rppg('video.mp4', 'pca', true)  % Enable GUI display
%
% Parameters:
%   videoFile  - (optional) Path to video file, omit for webcam
%   algorithm  - (optional) 'g' (green channel) or 'pca' (default: 'g')
%   showGUI    - (optional) true/false to show GUI (default: true)
%
% Algorithm:
%   1. Detect face using Viola-Jones cascade
%   2. Track face using KLT point tracking
%   3. Extract color signal from forehead ROI
%   4. Process signal: denoise, normalize, detrend, filter
%   5. Estimate heart rate using FFT analysis
%
% Author: MATLAB version of Heartbeat by Philipp Rouast
% License: GPL-3.0

    %% Parse input arguments
    p = inputParser;
    addOptional(p, 'videoFile', '', @ischar);
    addOptional(p, 'algorithm', 'g', @(x) any(validatestring(x, {'g', 'pca'})));
    addOptional(p, 'showGUI', true, @islogical);
    parse(p, varargin{:});

    videoFile = p.Results.videoFile;
    algorithm = p.Results.algorithm;
    showGUI = p.Results.showGUI;

    %% Parameters
    LOW_BPM = 42;                    % Minimum heart rate (BPM)
    HIGH_BPM = 240;                  % Maximum heart rate (BPM)
    SEC_PER_MIN = 60;
    RESCAN_FREQUENCY = 1;            % Face re-detection interval (Hz)
    SAMPLING_FREQUENCY = 1;          % HR estimation frequency (Hz)
    MIN_SIGNAL_SIZE = 5;             % Minimum signal window (seconds)
    MAX_SIGNAL_SIZE = 30;            % Maximum signal window (seconds)
    DOWNSAMPLE = 1;                  % Process every nth frame

    % Face detection parameters
    REL_MIN_FACE_SIZE = 0.4;         % Minimum face size as fraction of frame
    MAX_CORNERS = 10;                % Maximum tracking points
    MIN_CORNERS = 5;                 % Minimum tracking points for valid tracking

    fprintf('Heartbeat rPPG - MATLAB Implementation\n');
    fprintf('Algorithm: %s\n', upper(algorithm));

    %% Initialize video source
    if isempty(videoFile)
        fprintf('Opening webcam...\n');
        vid = webcam;
        frameRate = 30; % Assume 30 fps for webcam
        useWebcam = true;
    else
        fprintf('Opening video file: %s\n', videoFile);
        vid = VideoReader(videoFile);
        frameRate = vid.FrameRate;
        useWebcam = false;
    end

    %% Initialize face detector
    faceDetector = vision.CascadeObjectDetector('ClassificationModel', 'FrontalFaceCART');

    %% Initialize KLT point tracker
    pointTracker = vision.PointTracker('MaxBidirectionalError', 2);

    %% Initialize state variables
    faceValid = false;
    lastScanTime = 0;
    lastSamplingTime = 0;
    frameCount = 0;
    lastBpm = NaN;       % Last valid BPM estimate

    % Signal buffers
    signalRGB = [];      % RGB signal time series [Nx3]
    signalTime = [];     % Timestamp for each signal sample
    rescanFlags = [];    % Flags indicating face re-detection events
    bpmHistory = [];     % History of BPM estimates

    % Tracking variables
    trackingPoints = [];
    faceBox = [];
    roi = [];

    %% Setup GUI
    if showGUI
        hFig = figure('Name', sprintf('rPPG - %s algorithm', upper(algorithm)), ...
                     'NumberTitle', 'off', 'Position', [100 100 1200 500]);
        hAxVideo = subplot(1, 2, 1);
        hAxSignal = subplot(1, 2, 2);
        hTextBPM = annotation('textbox', [0.42 0.85 0.15 0.1], ...
                             'String', 'BPM: --', 'FontSize', 20, ...
                             'FontWeight', 'bold', 'EdgeColor', 'none', ...
                             'HorizontalAlignment', 'center');
    end

    fprintf('Starting rPPG processing...\n');
    fprintf('Press Ctrl+C to stop\n\n');

    %% Main processing loop
    try
        while true
            %% Read frame
            if useWebcam
                frame = snapshot(vid);
                currentTime = frameCount / frameRate * 1000; % ms
            else
                if ~hasFrame(vid)
                    break;
                end
                frame = readFrame(vid);
                currentTime = vid.CurrentTime * 1000; % ms
            end

            frameCount = frameCount + 1;

            % Skip frames for downsampling
            if mod(frameCount, DOWNSAMPLE) ~= 0
                continue;
            end

            % Convert to grayscale for face detection
            frameGray = rgb2gray(frame);

            %% Face detection and tracking
            rescanFlag = false;

            if ~faceValid
                % Need to detect face
                fprintf('[Frame %d] Detecting face...\n', frameCount);
                [faceValid, faceBox, trackingPoints] = detectFace(frame, frameGray, ...
                    faceDetector, pointTracker, REL_MIN_FACE_SIZE);
                lastScanTime = currentTime;

            elseif (currentTime - lastScanTime) / 1000 >= 1 / RESCAN_FREQUENCY
                % Periodic re-detection
                fprintf('[Frame %d] Re-scanning face...\n', frameCount);
                release(pointTracker);
                [faceValid, faceBox, trackingPoints] = detectFace(frame, frameGray, ...
                    faceDetector, pointTracker, REL_MIN_FACE_SIZE);
                lastScanTime = currentTime;
                rescanFlag = true;

            else
                % Track existing face
                [trackingPoints, validityPoints] = step(pointTracker, frameGray);

                % Check if we have enough valid points
                numValidPoints = sum(validityPoints);
                if numValidPoints < MIN_CORNERS
                    fprintf('[Frame %d] Tracking lost (%d points)\n', frameCount, numValidPoints);
                    faceValid = false;
                    continue;
                end

                % Keep only valid points
                trackingPoints = trackingPoints(validityPoints, :);

                % Update face box using geometric transform
                if ~isempty(trackingPoints)
                    oldCenter = [faceBox(1) + faceBox(3)/2, faceBox(2) + faceBox(4)/2];
                    newCenter = mean(trackingPoints, 1);
                    displacement = newCenter - oldCenter;
                    faceBox(1:2) = faceBox(1:2) + displacement;
                end
            end

            if ~faceValid
                continue;
            end

            %% Extract ROI (forehead region)
            % ROI is upper-center portion of face (forehead)
            roiX = round(faceBox(1) + 0.3 * faceBox(3));
            roiY = round(faceBox(2) + 0.1 * faceBox(4));
            roiWidth = round(0.4 * faceBox(3));
            roiHeight = round(0.15 * faceBox(4));

            % Ensure ROI is within frame bounds
            roiX = max(1, min(roiX, size(frame, 2) - roiWidth));
            roiY = max(1, min(roiY, size(frame, 1) - roiHeight));
            roi = [roiX, roiY, roiWidth, roiHeight];

            %% Extract color signal from ROI
            roiRegion = frame(roiY:roiY+roiHeight-1, roiX:roiX+roiWidth-1, :);
            meanR = mean(roiRegion(:, :, 1), 'all');
            meanG = mean(roiRegion(:, :, 2), 'all');
            meanB = mean(roiRegion(:, :, 3), 'all');

            % Add to signal buffer
            signalRGB = [signalRGB; meanR, meanG, meanB];
            signalTime = [signalTime; currentTime];
            rescanFlags = [rescanFlags; rescanFlag];

            %% Calculate effective frame rate from signal
            if size(signalRGB, 1) > 1
                timeDiff = (signalTime(end) - signalTime(1)) / 1000; % seconds
                effectiveFps = size(signalRGB, 1) / timeDiff;
            else
                effectiveFps = frameRate;
            end

            %% Trim signal buffer to max size
            maxSamples = ceil(effectiveFps * MAX_SIGNAL_SIZE);
            if size(signalRGB, 1) > maxSamples
                signalRGB = signalRGB(end-maxSamples+1:end, :);
                signalTime = signalTime(end-maxSamples+1:end);
                rescanFlags = rescanFlags(end-maxSamples+1:end);
            end

            %% Process signal and estimate heart rate
            bpm = lastBpm;  % Use last valid BPM by default
            processedSignal = [];
            powerSpectrum = [];
            freqAxis = [];

            minSamples = ceil(effectiveFps * MIN_SIGNAL_SIZE);
            if size(signalRGB, 1) >= minSamples
                % Calculate frequency band limits
                numSamples = size(signalRGB, 1);
                lowIdx = max(1, floor(numSamples * LOW_BPM / SEC_PER_MIN / effectiveFps));
                highIdx = min(numSamples, ceil(numSamples * HIGH_BPM / SEC_PER_MIN / effectiveFps));

                % Extract and process signal based on algorithm
                if strcmp(algorithm, 'g')
                    % Green channel only
                    processedSignal = processSignalGreen(signalRGB, rescanFlags, effectiveFps);
                else
                    % PCA on all channels
                    processedSignal = processSignalPCA(signalRGB, rescanFlags, effectiveFps, lowIdx, highIdx);
                end

                % Only estimate heart rate at sampling frequency
                if (currentTime - lastSamplingTime) / 1000 >= 1 / SAMPLING_FREQUENCY
                    % Estimate heart rate using FFT
                    [newBpm, powerSpectrum, freqAxis] = estimateHeartRate(processedSignal, ...
                        effectiveFps, lowIdx, highIdx, LOW_BPM, HIGH_BPM);

                    if ~isnan(newBpm)
                        bpm = newBpm;
                        lastBpm = newBpm;
                        bpmHistory = [bpmHistory; currentTime, bpm];
                        fprintf('[Frame %d] BPM: %.1f (FPS: %.1f, Samples: %d)\n', ...
                            frameCount, bpm, effectiveFps, numSamples);
                    end

                    lastSamplingTime = currentTime;
                end
            end

            %% Update GUI
            if showGUI
                % Display video with overlays
                axes(hAxVideo);
                imshow(frame);
                hold on;

                % Draw face box
                rectangle('Position', faceBox, 'EdgeColor', 'y', 'LineWidth', 2);

                % Draw ROI
                if ~isempty(roi)
                    rectangle('Position', roi, 'EdgeColor', 'g', 'LineWidth', 2);
                end

                % Draw tracking points
                if ~isempty(trackingPoints)
                    plot(trackingPoints(:, 1), trackingPoints(:, 2), 'g+', 'MarkerSize', 10);
                end

                hold off;
                title(sprintf('Frame %d - Face tracking', frameCount));

                % Display signal and power spectrum
                axes(hAxSignal);
                if ~isempty(powerSpectrum) && ~isempty(freqAxis)
                    % Plot power spectrum
                    plot(freqAxis * effectiveFps / numSamples * SEC_PER_MIN, powerSpectrum, 'b-', 'LineWidth', 1.5);
                    xlabel('Heart Rate (BPM)');
                    ylabel('Power');
                    title(sprintf('Power Spectrum - Current BPM: %.1f', bpm));
                    xlim([LOW_BPM HIGH_BPM]);
                    grid on;
                elseif ~isempty(processedSignal)
                    % Plot signal while accumulating samples
                    plot(processedSignal, 'b-');
                    xlabel('Sample');
                    ylabel('Normalized Signal');
                    title(sprintf('Accumulating samples... (%d/%d)', ...
                        size(signalRGB, 1), minSamples));
                    grid on;
                end

                % Update BPM text
                if ~isnan(bpm)
                    hTextBPM.String = sprintf('BPM: %.1f', bpm);
                    hTextBPM.Color = 'green';
                else
                    hTextBPM.String = 'BPM: --';
                    hTextBPM.Color = 'red';
                end

                drawnow;
            end
        end

    catch ME
        if ~strcmp(ME.identifier, 'MATLAB:class:InvalidHandle')
            rethrow(ME);
        end
    end

    %% Cleanup
    if useWebcam
        clear vid;
    end

    fprintf('\nProcessing complete!\n');
    if ~isempty(bpmHistory)
        fprintf('Mean BPM: %.1f (std: %.1f)\n', mean(bpmHistory(:, 2)), std(bpmHistory(:, 2)));
        fprintf('Min BPM: %.1f, Max BPM: %.1f\n', min(bpmHistory(:, 2)), max(bpmHistory(:, 2)));
    end
end

%% Helper function: Detect face
function [valid, box, points] = detectFace(frame, frameGray, detector, tracker, relMinSize)
    % Detect faces
    minSize = round(min(size(frame, 1), size(frame, 2)) * relMinSize);
    bbox = step(detector, frameGray);

    valid = false;
    box = [];
    points = [];

    if isempty(bbox)
        fprintf('  No face found\n');
        return;
    end

    % Use the largest face
    if size(bbox, 1) > 1
        areas = bbox(:, 3) .* bbox(:, 4);
        [~, idx] = max(areas);
        bbox = bbox(idx, :);
    end

    box = bbox;

    % Detect tracking points in forehead region (tracking region)
    trackX = round(box(1) + 0.22 * box(3));
    trackY = round(box(2) + 0.21 * box(4));
    trackWidth = round(0.56 * box(3));
    trackHeight = round(0.44 * box(4));

    % Ensure tracking region is within bounds
    trackX = max(1, min(trackX, size(frameGray, 2) - trackWidth));
    trackY = max(1, min(trackY, size(frameGray, 1) - trackHeight));
    trackRegion = [trackX, trackY, trackWidth, trackHeight];

    % Detect corners for tracking
    points = detectMinEigenFeatures(frameGray, 'ROI', trackRegion, ...
        'MinQuality', 0.01, 'FilterSize', 3);

    if points.Count < 5
        fprintf('  Not enough tracking points found\n');
        return;
    end

    % Select strongest points
    points = points.selectStrongest(min(10, points.Count));

    % Initialize point tracker
    initialize(tracker, points.Location, frameGray);

    valid = true;
    points = points.Location;
    fprintf('  Face detected with %d tracking points\n', size(points, 1));
end

%% Helper function: Process signal (Green channel)
function processedSignal = processSignalGreen(signalRGB, rescanFlags, fps)
    % Extract green channel
    signal = signalRGB(:, 2);

    % Denoise (remove jumps from face re-detection)
    signal = denoiseSignal(signal, rescanFlags);

    % Normalize
    signal = normalizeSignal(signal);

    % Detrend
    signal = detrendSignal(signal, fps);

    % Moving average filter
    windowSize = max(2, floor(fps / 6));
    signal = movmean(signal, windowSize);

    processedSignal = signal;
end

%% Helper function: Process signal (PCA)
function processedSignal = processSignalPCA(signalRGB, rescanFlags, fps, lowIdx, highIdx)
    % Denoise all channels
    signal = signalRGB;
    for ch = 1:3
        signal(:, ch) = denoiseSignal(signal(:, ch), rescanFlags);
    end

    % Normalize all channels
    signal = normalizeSignal(signal);

    % Detrend all channels
    for ch = 1:3
        signal(:, ch) = detrendSignal(signal(:, ch), fps);
    end

    % Apply PCA and select component with strongest peak in valid BPM range
    [~, score, ~] = pca(signal);

    % Find component with strongest peak in valid frequency band
    bestComponent = 1;
    maxPower = 0;

    for comp = 1:min(3, size(score, 2))
        % Get power spectrum
        fftSignal = fft(score(:, comp));
        powerSpec = abs(fftSignal(1:floor(end/2)));

        % Find max in valid band
        validPower = powerSpec(lowIdx:min(highIdx, length(powerSpec)));
        if ~isempty(validPower)
            currentMax = max(validPower);
            if currentMax > maxPower
                maxPower = currentMax;
                bestComponent = comp;
            end
        end
    end

    signal = score(:, bestComponent);

    % Moving average filter
    windowSize = max(2, floor(fps / 6));
    signal = movmean(signal, windowSize);

    processedSignal = signal;
end

%% Helper function: Denoise signal (eliminate jumps)
function denoised = denoiseSignal(signal, jumps)
    denoised = signal;
    if length(signal) < 2
        return;
    end

    % Calculate differences
    diff_signal = diff(signal);

    % For each jump (face re-detection), remove the discontinuity
    for i = 2:length(jumps)
        if jumps(i)
            % Subtract the jump from all subsequent values
            denoised(i:end) = denoised(i:end) - diff_signal(i-1);
        end
    end
end

%% Helper function: Normalize signal
function normalized = normalizeSignal(signal)
    % Normalize each column to zero mean and unit variance
    normalized = (signal - mean(signal, 1)) ./ (std(signal, 0, 1) + eps);
end

%% Helper function: Detrend signal
function detrended = detrendSignal(signal, lambda)
    % Advanced detrending using smoothness priors (high-pass filter)
    n = length(signal);

    if n < 3
        detrended = signal;
        return;
    end

    % Construct second-order difference matrix D2
    D = spdiags([ones(n-2,1) -2*ones(n-2,1) ones(n-2,1)], 0:2, n-2, n);

    % Solve (I + lambda^2 * D'*D) * x = signal
    % Detrended = signal - x
    I = speye(n);
    trend = (I + lambda^2 * (D' * D)) \ signal;
    detrended = signal - trend;
end

%% Helper function: Estimate heart rate
function [bpm, powerSpectrum, freqAxis] = estimateHeartRate(signal, fps, lowIdx, highIdx, lowBPM, highBPM)
    % Compute FFT
    n = length(signal);
    fftSignal = fft(signal);
    powerSpectrum = abs(fftSignal(1:floor(n/2)));
    freqAxis = (0:length(powerSpectrum)-1)';

    % Find peak in valid frequency range
    validIdx = max(1, lowIdx):min(length(powerSpectrum), highIdx);

    if isempty(validIdx)
        bpm = NaN;
        return;
    end

    [~, maxIdx] = max(powerSpectrum(validIdx));
    peakIdx = validIdx(1) + maxIdx - 1;

    % Convert frequency index to BPM
    bpm = peakIdx * fps / n * 60;

    % Validate BPM is in expected range
    if bpm < lowBPM || bpm > highBPM
        bpm = NaN;
    end
end
