//
//  AudioRecorderManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import AVFoundation

// --- Audio Recorder Logic --- 
class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0.0
    @Published var error: Error? = nil // To report errors
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10) // Array to store audio levels for visualization

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var audioFileURL: URL?
    
    // Aggregated level logging (mic)
    private var levelLogMinDb: Float = 100
    private var levelLogMaxDb: Float = -100
    private var levelLogSumDb: Double = 0
    private var levelLogCount: Int = 0
    private var levelLogLastTime: CFAbsoluteTime = 0

    // Get the directory to save recordings (centralized in AudioUtils)
    private func getRecordingsDirectory() -> URL {
        if let dir = try? AudioUtils.getRecordingsDirectory() { return dir }
        // Fallback to Documents if creation failed
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
        return docs.appendingPathComponent(bundleID).appendingPathComponent("Recordings")
    }

    // Setup the audio recorder
    private func setupRecorder() -> Bool {
        // macOS doesn't require AVAudioSession setup for basic recording
        Logger.debug("Setting up recorder on macOS (no AVAudioSession needed).", category: .audio)
        
        do {
            let recordingSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),   // Changed to AAC format 
                AVSampleRateKey: 44100,                     // Standard rate
                AVNumberOfChannelsKey: 1,                   // Mono
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue // For AAC
            ]

            // Create a unique file name with .m4a extension
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateString = dateFormatter.string(from: Date())
            let fileName = "recording_\(dateString).m4a"
            audioFileURL = getRecordingsDirectory().appendingPathComponent(fileName)

            guard let url = audioFileURL else {
                Logger.error("Audio File URL is nil", category: .audio)
                self.error = NSError(domain: "AudioRecorderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio file URL."])
                return false
            }
            
            Logger.info("Attempting to record to: \(url.path)", category: .audio)

            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // Enable metering if you want to show levels
            
            if audioRecorder?.prepareToRecord() == true {
                 Logger.info("Audio recorder prepared successfully.", category: .audio)
                 return true
             } else {
                 Logger.error("Audio recorder failed to prepare.", category: .audio)
                 self.error = NSError(domain: "AudioRecorderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio recorder failed to prepare."])
                 return false
             }

        } catch {
            Logger.error("Error setting up audio recorder: \(error.localizedDescription)", error: error, category: .audio)
            self.error = error
            return false
        }
    }

    // Most minimal possible implementation
    func startRecording() {
        // Check if already recording
        if audioRecorder?.isRecording == true {
            Logger.info("Already recording", category: .audio)
            return
        }

        // Clear previous error
        self.error = nil
        
        Logger.info("Attempting to start recording...", category: .audio)

        // Setup the recorder
        if !setupRecorder() {
            // Error should already be set by setupRecorder()
            Logger.error("Failed to setup recorder.", category: .audio)
            isRecording = false // Ensure state is correct
            return
        }

        // Recorder should be non-nil if setupRecorder returned true
        guard let recorder = audioRecorder else {
            Logger.error("Recorder is nil after successful setup.", category: .audio)
            self.error = NSError(domain: "AudioRecorderError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Internal error: Recorder became nil."])
            isRecording = false
            return
        }

        // Attempt to start recording
        if recorder.record() {
            isRecording = true
            startTimer() // Start updating recordingTime
            Logger.info("Recording started successfully.", category: .audio)
        } else {
            // Recording failed to start, even though setup was successful
            Logger.error("recorder.record() returned false.", category: .audio)
            self.error = NSError(domain: "AudioRecorderError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording after setup."])
            isRecording = false
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder else { return nil }

        Logger.info("Stopping recording...", category: .audio)
        let duration = recorder.currentTime
        recorder.stop()
        stopTimer()
        isRecording = false
        isPaused = false
        recordingTime = 0.0
        let savedURL = audioFileURL
        audioRecorder = nil // Release the recorder
        audioFileURL = nil // Clear the file URL
        
        if let url = savedURL {
            Logger.info("Recording stopped. File saved at: \(url.path), Duration: \(duration)", category: .audio)
            return (url, duration)
        } else {
            Logger.error("Recorded file URL was nil after stopping.", category: .audio)
            self.error = NSError(domain: "AudioRecorderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Recorded file URL was lost."])
            return nil
        }
    }

    func cancelRecording() {
        guard let recorder = audioRecorder else { return }
        
        Logger.info("Cancelling recording...", category: .audio)
        recorder.stop()
        stopTimer()
        isRecording = false
        isPaused = false
        recordingTime = 0.0

        // Delete the partially recorded file
        if let url = audioFileURL {
            Logger.info("Deleting temporary file: \(url.path)", category: .audio)
            recorder.deleteRecording() // This deletes the file at recorder's URL
        } else {
            Logger.warning("Could not find file URL to delete for cancelled recording.", category: .audio)
        }
        
        audioRecorder = nil
        audioFileURL = nil
        error = nil // Clear error state on cancellation
        
    }

    // MARK: - Pause/Resume
    func pauseRecording() {
        guard let recorder = audioRecorder, isRecording else { return }
        recorder.pause()
        stopTimer()
        isPaused = true
        isRecording = false
    }

    func resumeRecording() {
        guard let recorder = audioRecorder, isPaused else { return }
        if recorder.record() {
            isPaused = false
            isRecording = true
            startTimer()
        } else {
            // If resume fails, mark error but keep state consistent
            self.error = NSError(domain: "AudioRecorderError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to resume recording."])
        }
    }

    private func startTimer() {
        stopTimer() // Ensure no duplicates
        recordingTime = 0.0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.isRecording else {
                self?.stopTimer() // Stop if self is nil or no recorder/not recording
                return
            }
            self.recordingTime = recorder.currentTime
            
            // Update audio levels for visualization
            self.updateAudioLevels()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // New function to update audio levels
    private func updateAudioLevels() {
        guard let recorder = audioRecorder, isRecording else { return }
        
        recorder.updateMeters() // Update the meters
        
        // Get the power of the audio signal (in decibels)
        let power = recorder.averagePower(forChannel: 0)

        // Visual normalization on dB scale: very sensitive to quiet sounds
        let minDb: Float = -80
        let clipped = max(minDb, Float(power))
        let normalizedDb = (clipped - minDb) / (-minDb) // 0..1
        let normalizedValue = max(0.0, min(1.0, pow(normalizedDb, 1.1)))
        
        // Add new value to the end and remove the oldest one
        audioLevels.removeFirst()
        audioLevels.append(Float(normalizedValue))

        #if DEBUG
        // Aggregate and log every 0.5s for diagnostics
        levelLogMinDb = min(levelLogMinDb, power)
        levelLogMaxDb = max(levelLogMaxDb, power)
        levelLogSumDb += Double(power)
        levelLogCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        if now - levelLogLastTime > 1.0, levelLogCount > 0 {
            let avg = levelLogSumDb / Double(levelLogCount)
            Logger.debug(String(format: "Mic level dB min/avg/max: %.1f / %.1f / %.1f | norm(avg) %.2f", levelLogMinDb, Float(avg), levelLogMaxDb, normalizedValue), category: .audio)
            levelLogMinDb = 100
            levelLogMaxDb = -100
            levelLogSumDb = 0
            levelLogCount = 0
            levelLogLastTime = now
        }
        #endif
    }

    // MARK: - AVAudioRecorderDelegate Methods
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Update state on main thread
        DispatchQueue.main.async {
            if !flag {
                Logger.warning("Recording finished unsuccessfully.", category: .audio)
                // This might happen due to interruption or error. Stop timer etc.
                self.stopTimer()
                self.isRecording = false
                self.recordingTime = 0.0
                self.error = NSError(domain: "AudioRecorderError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recording did not finish successfully."])
                
            }
            // Note: We handle successful completion within stopRecording()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Logger.error("Audio recorder encode error: \(error?.localizedDescription ?? "Unknown error")", error: error, category: .audio)
        // Update state on main thread
        DispatchQueue.main.async {
            self.stopTimer()
            self.isRecording = false
            self.recordingTime = 0.0
            self.error = error ?? NSError(domain: "AudioRecorderError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Encoding error occurred."])
        }
    }
    
    deinit {
        // Ensure cleanup if the manager is deallocated unexpectedly
        stopTimer()
        if isRecording {
            cancelRecording() // Cancel if still recording
        }
        Logger.debug("AudioRecorderManager deinitialized", category: .audio)
    }
} 
