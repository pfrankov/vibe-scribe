//
//  AudioRecorderManager.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import Foundation
import AVFoundation

#if os(macOS)
import AVKit // Make sure we have AVKit for AVCaptureDevice on macOS
#endif

// --- Audio Recorder Logic --- 
class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0.0
    @Published var error: Error? = nil // To report errors
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10) // Array to store audio levels for visualization

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var audioFileURL: URL?

    // Get the directory to save recordings
    private func getRecordingsDirectory() -> URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupportURL = urls.first else {
            fatalError("Could not find Application Support directory.") // Handle more gracefully in production
        }
        
        // Append your app's bundle identifier and a 'Recordings' subdirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
        let recordingsURL = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("Recordings")

        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: recordingsURL.path) {
            do {
                try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true, attributes: nil)
                print("Created recordings directory at: \(recordingsURL.path)")
            } catch {
                fatalError("Could not create recordings directory: \(error.localizedDescription)")
            }
        }
        return recordingsURL
    }

    // Setup the audio recorder
    private func setupRecorder() -> Bool {
        #if os(iOS)
        // iOS specific code for setting up audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
            print("Audio session activated on iOS.")
        } catch {
            print("Error setting up iOS audio session: \(error.localizedDescription)")
            self.error = error
            return false
        }
        #else
        // macOS doesn't require AVAudioSession setup for basic recording
        print("Setting up recorder on macOS (no AVAudioSession needed).")
        #endif
        
        do {
            // --- Updated Recording Settings to use AAC (more compatible) ---
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
            let fileName = "recording_\(dateString).m4a" // Changed extension back to m4a
            audioFileURL = getRecordingsDirectory().appendingPathComponent(fileName)

            guard let url = audioFileURL else {
                print("Error: Audio File URL is nil.")
                self.error = NSError(domain: "AudioRecorderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio file URL."])
                return false
            }
            
            print("Attempting to record to: \(url.path)")

            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // Enable metering if you want to show levels
            
            if audioRecorder?.prepareToRecord() == true {
                 print("Audio recorder prepared successfully.")
                 return true
             } else {
                 print("Error: Audio recorder failed to prepare.")
                 self.error = NSError(domain: "AudioRecorderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio recorder failed to prepare."])
                 return false
             }

        } catch {
            print("Error setting up audio recorder: \(error.localizedDescription)")
            self.error = error
            #if os(iOS)
            // Attempt to deactivate session on error for iOS
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            return false
        }
    }

    // Most minimal possible implementation
    func startRecording() {
        // Check if already recording
        if audioRecorder?.isRecording == true {
            print("Already recording.")
            return
        }

        // Clear previous error
        self.error = nil
        
        print("Attempting to start recording...") // Updated log message

        // Setup the recorder
        if !setupRecorder() {
            // Error should already be set by setupRecorder()
            print("Failed to setup recorder.")
            isRecording = false // Ensure state is correct
            return
        }

        // Recorder should be non-nil if setupRecorder returned true
        guard let recorder = audioRecorder else {
            print("Error: Recorder is nil after successful setup.")
            self.error = NSError(domain: "AudioRecorderError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Internal error: Recorder became nil."])
            isRecording = false
            return
        }

        // Attempt to start recording
        if recorder.record() {
            isRecording = true
            startTimer() // Start updating recordingTime
            print("Recording started successfully.")
        } else {
            // Recording failed to start, even though setup was successful
            print("Error: recorder.record() returned false.")
            self.error = NSError(domain: "AudioRecorderError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording after setup."])
            isRecording = false
            // Clean up recorder instance if start failed? Maybe not necessary here, handled by stop/cancel.
            // audioRecorder = nil 
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }

        print("Stopping recording...")
        let duration = recorder.currentTime
        recorder.stop()
        stopTimer()
        isRecording = false
        recordingTime = 0.0
        let savedURL = audioFileURL
        audioRecorder = nil // Release the recorder
        audioFileURL = nil // Clear the file URL
        
        #if os(iOS)
        // Deactivate the audio session after recording on iOS
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated.")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
            // Don't necessarily set self.error here, as recording succeeded
        }
        #endif

        if let url = savedURL {
            print("Recording stopped. File saved at: \(url.path), Duration: \(duration)")
            return (url, duration)
        } else {
            print("Error: Recorded file URL was nil after stopping.")
            self.error = NSError(domain: "AudioRecorderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Recorded file URL was lost."])
            return nil
        }
    }

    func cancelRecording() {
        guard let recorder = audioRecorder, isRecording else { return }
        
        print("Cancelling recording...")
        recorder.stop()
        stopTimer()
        isRecording = false
        recordingTime = 0.0

        // Delete the partially recorded file
        if let url = audioFileURL {
            print("Deleting temporary file: \(url.path)")
            recorder.deleteRecording() // This deletes the file at recorder's URL
        } else {
            print("Warning: Could not find file URL to delete for cancelled recording.")
        }
        
        audioRecorder = nil
        audioFileURL = nil
        error = nil // Clear error state on cancellation
        
        #if os(iOS)
        // Deactivate the audio session on iOS
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated.")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
        #endif
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
        
        // Convert from decibels (-160...0) to a value (0...1)
        // Typical voice is around -10 to -30 dB, so we normalize for a better visual
        let normalizedValue = min(1.0, max(0.0, (power + 50) / 50))
        
        // Add new value to the end and remove the oldest one
        audioLevels.removeFirst()
        audioLevels.append(Float(normalizedValue))
    }

    // MARK: - AVAudioRecorderDelegate Methods
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Update state on main thread
        DispatchQueue.main.async {
            if !flag {
                print("Recording finished unsuccessfully.")
                // This might happen due to interruption or error. Stop timer etc.
                self.stopTimer()
                self.isRecording = false
                self.recordingTime = 0.0
                self.error = NSError(domain: "AudioRecorderError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recording did not finish successfully."])
                
                #if os(iOS)
                // Deactivate session on iOS
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                    print("Audio session deactivated after unsuccessful recording.")
                } catch {
                    print("Error deactivating audio session: \(error.localizedDescription)")
                }
                #endif
            }
            // Note: We handle successful completion within stopRecording()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Audio recorder encode error: \(error?.localizedDescription ?? "Unknown error")")
        // Update state on main thread
        DispatchQueue.main.async {
            self.stopTimer()
            self.isRecording = false
            self.recordingTime = 0.0
            self.error = error ?? NSError(domain: "AudioRecorderError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Encoding error occurred."])
            
            #if os(iOS)
            // Deactivate session on iOS
            do {
                try AVAudioSession.sharedInstance().setActive(false)
                print("Audio session deactivated after encode error.")
            } catch {
                print("Error deactivating audio session: \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    deinit {
        // Ensure cleanup if the manager is deallocated unexpectedly
        stopTimer()
        if isRecording {
            cancelRecording() // Cancel if still recording
        }
        print("AudioRecorderManager deinitialized")
    }
} 