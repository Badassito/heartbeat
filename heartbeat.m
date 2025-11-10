% rPPG heart rate detection with Haar cascade face detection
% heartbeat('video.mp4')

function heartbeat(input)
    close all;
    % Configuration
    LOW_BPM = 50;
    HIGH_BPM = 180;
    WINDOW_SIZE = 150;
    vid = VideoReader(input);
    fps = vid.FrameRate;
    faceDetector = vision.CascadeObjectDetector('FrontalFaceCART');
    
    % Initialize signal buffer
    signal = [];
    frameCount = 0;
    bpm_history = [];
    
    % Create figure
    figure('Name', 'rPPG Heart Rate Detection', 'Position', [100, 100, 900, 900]);

    % Main processing loop
    while true
        frame = readFrame(vid);
        
        frameCount = frameCount + 1;
        
        % Detect face
        bboxes = step(faceDetector, frame);
        if ~isempty(bboxes)
            face = bboxes(1, :);
        else
            face = [];  % or handle the no-face case
        end
        
        % Define ROI (forehead region)
        roi_x = round(face(1) + 0.3 * face(3));
        roi_y = round(face(2) + 0.1 * face(4));
        roi_w = round(0.4 * face(3));
        roi_h = round(0.15 * face(4));
        
        if roi_w > 0 && roi_h > 0
            roi = frame(roi_y:roi_y+roi_h-1, roi_x:roi_x+roi_w-1, :); % Extract ROI
            green_value = mean(mean(roi(:, :, 2))); % Extract mean green channel value (rPPG signal)
            signal = [signal; green_value]; % Add to signal buffer
            
            % Limit buffer size
            if length(signal) > WINDOW_SIZE
                signal = signal(end-WINDOW_SIZE+1:end);
            end
            
            % Estimate heart rate
            bpm = 0;
            powerSpectrum = [];
            freqs = [];
            if length(signal) >= WINDOW_SIZE
                [bpm, powerSpectrum, freqs] = estimateHeartRate(signal, fps, LOW_BPM, HIGH_BPM);
                
                if bpm > 0
                    bpm_history = [bpm_history; bpm];
                    if length(bpm_history) > 10
                        bpm_history = bpm_history(end-9:end);
                    end
                end
            end
            
            % Calculate smoothed BPM
            display_bpm = 0;
            if length(bpm_history) >= 5
                display_bpm = median(bpm_history(end-4:end));
            elseif ~isempty(bpm_history)
                display_bpm = bpm_history(end);
            end
            
            displayResults(frame, face, [roi_x, roi_y, roi_w, roi_h], display_bpm, signal, powerSpectrum, freqs, bpm, LOW_BPM, HIGH_BPM, frameCount);
        end
        
        drawnow;
    end
end

function displayResults(frame, face, roi, display_bpm, signal, powerSpectrum, freqs, bpm, low_bpm, high_bpm, frameCount)
    % Display video with overlays
    subplot(3, 1, 1);
    imshow(frame);
    hold on;
    
    % Draw stuff
    rectangle('Position', face, 'EdgeColor', 'b', 'LineWidth', 2); % face box
    rectangle('Position', roi, 'EdgeColor', 'g', 'LineWidth', 2); % Draw ROI
    text(10, 30, sprintf('Heart Rate: %.1f BPM', display_bpm), 'Color', 'green', 'FontSize', 16, 'FontWeight', 'bold', 'BackgroundColor', 'black'); % Display BPM
    text(10, 70, sprintf('Frame: %d', frameCount), 'Color', 'white', 'FontSize', 10, 'BackgroundColor', 'black'); % Frame counter
    
    hold off;
    
    % Signal plot
    subplot(3, 1, 2);
    if length(signal) > 1
        plot(signal, 'g', 'LineWidth', 2);
        title('rPPG Green Channel Signal');
        xlabel('Frame');
        ylabel('Intensity');
        grid on;
        xlim([0, length(signal)]);
    end
    
    % Power spectrum
    subplot(3, 1, 3);
    if ~isempty(powerSpectrum) && ~isempty(freqs)
        plot(freqs, powerSpectrum, 'b', 'LineWidth', 1.5);
        hold on;

        peak_idx = find(abs(freqs - bpm) < 0.5, 1);
        if ~isempty(peak_idx)
            plot(bpm, powerSpectrum(peak_idx), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
        end
        hold off;
        title('Frequency Spectrum (FFT)');
        xlabel('Heart Rate (BPM)');
        ylabel('Power');
        xlim([low_bpm-10, high_bpm+10]);
        grid on;
    end
end

function [bpm, powerSpectrum, freqs] = estimateHeartRate(signal, fps, low_bpm, high_bpm) % Heart rate estimation using FFT
    
    % 1. Detrend
    signal_det = detrend(signal);
    
    % 2. Normalize
    signal_norm = (signal_det - mean(signal_det)) / std(signal_det);
    
    % 3. Bandpass filter
    low_hz = low_bpm / 60;
    high_hz = high_bpm / 60;
    [b, a] = cheby2(4, 40, [low_hz, high_hz] / (fps/2), 'bandpass'); % Replaced Filter: butter(4, [low_hz, high_hz] / (fps/2), 'bandpass');
    signal_filtered = filtfilt(b, a, signal_norm);
    
    % 4. Apply Hamming window
    hamming_window = hamming(length(signal_filtered));
    signal_windowed = signal_filtered .* hamming_window;
    
    % 5. FFT with zero-padding
    nfft = 2^nextpow2(length(signal_windowed) * 4);
    Y = fft(signal_windowed, nfft);
    L = length(signal_windowed);
    
    % 6. Power spectrum
    P2 = abs(Y/L);
    P1 = P2(1:floor(nfft/2)+1);
    P1(2:end-1) = 2*P1(2:end-1);
    
    % 7. Frequency vector in BPM
    f = fps * (0:floor(nfft/2)) / nfft;
    bpm_values = f * 60;
    
    % 8. Find peak in valid range
    valid_idx = (bpm_values >= low_bpm) & (bpm_values <= high_bpm);
    
    powerSpectrum = P1;
    freqs = bpm_values;
    
    if sum(valid_idx) > 0
        valid_power = P1(valid_idx);
        valid_bpm = bpm_values(valid_idx);
        
        [~, max_idx] = max(valid_power);
        bpm = valid_bpm(max_idx);
    else
        bpm = 0;
    end
end