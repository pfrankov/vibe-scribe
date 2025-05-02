//
//  RecordingView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData
import ScreenCaptureKit

// --- Updated Recording View --- 
struct RecordingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    // Managers
    @StateObject private var micRecorderManager = AudioRecorderManager()
    // System recorder is always instantiated, but only USED on 12.3+
    @StateObject private var systemRecorderManager = SystemAudioRecorderManager()
    
    // State for file URLs (will be set on stop)
    // Mic URL comes from its manager, Sys URL is generated here
    @State private var systemAudioOutputURL: URL? = nil

    // Error handling - combine errors or prioritize?
    private var displayError: Error? {
        if #available(macOS 12.3, *) {
            return micRecorderManager.error ?? systemRecorderManager.error
        } else {
            return micRecorderManager.error
        }
    }
    
    // Combined recording state requires system manager only if available
    private var isCombinedRecordingActive: Bool {
        if #available(macOS 12.3, *) {
             return micRecorderManager.isRecording && systemRecorderManager.isRecording
        } else {
            return micRecorderManager.isRecording
        }
    }

    private var canStopRecording: Bool {
        // Stop should be enabled if at least the mic recorder is running and has recorded enough
        micRecorderManager.isRecording && micRecorderManager.recordingTime >= 0.5
    }

    // Date formatter for default recording names
    private var recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            // Title reflects recorder state more dynamically
            Text(micRecorderManager.isRecording ? "Recording..." : displayError == nil ? "Preparing..." : "Error")
                .font(.title)

            // Display recording time (use mic recorder as primary timer)
            Text(formatTime(micRecorderManager.recordingTime))
                .font(.title2)
                .monospacedDigit() // Ensures stable width
                .padding(.bottom)

            // Replace microphone icon with audio wave visualization when recording
            if micRecorderManager.isRecording {
                // Аудио волна во время записи (using mic levels)
                AudioWaveView(
                    levels: micRecorderManager.audioLevels,
                    activeColor: .red,
                    isActive: true
                )
            } else {
                // Иконка микрофона когда не записываем
                Image(systemName: displayError != nil ? "mic.slash.fill" : "mic.fill") // Show mic.fill if ready
                    .font(.system(size: 60))
                    .foregroundColor(displayError != nil ? .orange : .secondary)
                    .padding()
            }

            // Display error message if any
            if let error = displayError {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            HStack {
                // --- Updated Button Logic ---
                Button("Stop") {
                    stopAndProcessRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red) // Always red as it's the "Stop" action
                // Disable Stop button based on canStopRecording flag
                .disabled(!canStopRecording || displayError != nil)

                // Cancel Button (Always visible, but primary action changes)
                // If recording: Cancels the recording
                // If not recording (e.g., during setup or error): Closes the sheet
                Button(micRecorderManager.isRecording ? "Cancel" : "Close") {
                    if micRecorderManager.isRecording {
                        cancelActiveRecording()
                    }
                    // Always dismiss when this button is pressed
                    dismiss() 
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Spacer() // Push controls up
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Start recording automatically
            startCombinedRecording()
        }
        .onDisappear {
            // Ensure recording is stopped/cancelled if the view disappears unexpectedly
             var wasRecording = micRecorderManager.isRecording
             if #available(macOS 12.3, *) {
                 wasRecording = wasRecording || systemRecorderManager.isRecording
             }
             
            if wasRecording {
                print("RecordingView disappeared while recording. Cancelling.")
                cancelActiveRecording()
            }
        }
    }
    
    // MARK: - Recording Control Functions
    
    private func startCombinedRecording() {
        print("RecordingView appeared. Attempting to start combined recording.")
        // Clear previous errors
        micRecorderManager.error = nil
         if #available(macOS 12.3, *) {
             systemRecorderManager.error = nil
         }
        
        // Generate unique URL *only* for system audio
        let timestamp = Int(Date().timeIntervalSince1970)
        guard let sysURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("sys_\(timestamp).caf")
        else {
            print("Error generating system recording URL")
             // Set error on mic manager for display?
            micRecorderManager.error = NSError(domain: "RecordingView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create system file URL."])
            return
        }
        self.systemAudioOutputURL = sysURL // Store potential sys URL
        print("System Audio URL: \(sysURL.path)")
        
        // Start Mic Recording (generates its own URL)
        micRecorderManager.startRecording() 
        
        // Start System Audio Recording (if available)
        if #available(macOS 12.3, *) {
            systemRecorderManager.startRecording(outputURL: sysURL)
        } else {
            print("System audio recording not started (OS unsupported).")
        }
    }
    
    private func stopAndProcessRecording() {
        // Stop Microphone
        guard let micResult = micRecorderManager.stopRecording() else {
            print("Failed to stop mic recording properly.")
            dismiss()
            return
        }
        
        var systemAudioStoppedURL: URL? = nil
        // Stop System Audio (if available and was recording)
        if #available(macOS 12.3, *), systemRecorderManager.isRecording {
            systemRecorderManager.stopRecording()
            systemAudioStoppedURL = self.systemAudioOutputURL // Use the URL we generated
            print("Stopped system audio recording. URL: \(systemAudioStoppedURL?.path ?? "nil")")
        } else {
             print("System audio recording was not active or not supported.")
        }
        
        // --- TODO: MERGING STEP --- 
        print("Mic file: \(micResult.url.path)")
        if let sysURL = systemAudioStoppedURL {
            print("System file: \(sysURL.path)")
            
            // >>> Call merging function here <<< 
            AudioUtils.mergeAudioFiles(micURL: micResult.url, systemURL: sysURL) { result in
                 DispatchQueue.main.async { // Ensure UI updates and model context access on main thread
                     switch result {
                     case .success(let mergedURL):
                         print("Merge successful. Saving record with URL: \(mergedURL.path)")
                         // Use mic duration as primary? Or recalculate? Using mic duration for now.
                         self.createAndSaveRecord(url: mergedURL, duration: micResult.duration)
                         // Clean up original mic and sys files after successful merge
                         self.cleanupTemporaryFiles(micURL: micResult.url, sysURL: sysURL)
                         self.dismiss()
                     case .failure(let error):
                         print("Audio merge failed: \(error.localizedDescription)")
                         // Decide how to handle merge failure. 
                         // Option 1: Save only the mic recording as a fallback
                         print("Saving only microphone recording due to merge failure.")
                         self.createAndSaveRecord(url: micResult.url, duration: micResult.duration)
                         // Clean up only the system file if merge failed
                          self.cleanupTemporaryFiles(micURL: nil, sysURL: sysURL) // Keep mic, delete sys
                         self.dismiss()
                         
                         // Option 2: Show an error to the user and don't save anything
                         // self.micRecorderManager.error = error // Set error for UI display
                         // self.cleanupTemporaryFiles(micURL: micResult.url, sysURL: sysURL) // Delete both originals
                         // // Don't dismiss automatically, let user close the error view?
                     }
                 }
            }
            // Don't dismiss immediately here, wait for merge completion
            // dismiss() 
        } else {
             print("No system audio file generated or recorded. Saving only mic recording.")
            // Save the mic recording directly if no system audio was recorded
             createAndSaveRecord(url: micResult.url, duration: micResult.duration)
             // No system file to clean up in this case
            dismiss() // Dismiss after saving mic-only record
        }

        // Don't dismiss here anymore, handled within completion or else block
        // dismiss() // Dismiss after stopping
    }
    
    private func cancelActiveRecording() {
        print("Cancelling active recording.")
        micRecorderManager.cancelRecording() // Deletes its own temp file
        
        if #available(macOS 12.3, *), systemRecorderManager.isRecording {
            // Stop system recorder
            systemRecorderManager.stopRecording() 
            // Explicitly delete the system audio file we generated
            if let sysURL = self.systemAudioOutputURL {
                 print("Deleting cancelled system audio file: \(sysURL.path)")
                try? FileManager.default.removeItem(at: sysURL)
            }
        }
        self.systemAudioOutputURL = nil // Clear the URL
    }
    
    // Helper to create and save the Record object (called after merging ideally)
    private func createAndSaveRecord(url: URL, duration: TimeInterval) {
         let defaultName = "Recording \(recordingNameFormatter.string(from: Date()))"
         let newRecord = Record(name: defaultName, fileURL: url, duration: duration)
         
         print("Attempting to insert final record: \(newRecord.name) at \(url.path)")
         modelContext.insert(newRecord)
         // Optional: Explicit save
         // do { try modelContext.save() } catch { print("Error saving context: \(error)") }
    }

    // Helper function to delete temporary audio files
    private func cleanupTemporaryFiles(micURL: URL?, sysURL: URL?) {
        if let micURL = micURL {
            do {
                try FileManager.default.removeItem(at: micURL)
                print("Cleaned up temporary mic file: \(micURL.path)")
            } catch {
                print("Warning: Could not delete temporary mic file \(micURL.path): \(error.localizedDescription)")
            }
        }
        if let sysURL = sysURL {
            do {
                try FileManager.default.removeItem(at: sysURL)
                print("Cleaned up temporary system audio file: \(sysURL.path)")
            } catch {
                print("Warning: Could not delete temporary system audio file \(sysURL.path): \(error.localizedDescription)")
            }
        }
    }

    // Re-use the time formatter from RecordDetailView
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 