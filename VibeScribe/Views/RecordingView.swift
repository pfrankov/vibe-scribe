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

    // Error handling - display combined error
    private var displayError: Error? {
        // Simplified: Always consider both managers
        micRecorderManager.error ?? systemRecorderManager.error
    }
    
    // Combined recording state 
    private var isCombinedRecordingActive: Bool {
        // Recording is active if microphone is recording (system audio is optional)
        micRecorderManager.isRecording
    }

    private var canStopRecording: Bool {
        // Stop should be enabled if at least the mic recorder is running and has recorded enough
        micRecorderManager.isRecording && micRecorderManager.recordingTime >= 0.5
    }
    
    // Combined audio levels from both mic and system
    private var combinedAudioLevels: [Float] {
        // Simplified: Always combine levels if system recorder is active
        if systemRecorderManager.isRecording {
            return zip(micRecorderManager.audioLevels, systemRecorderManager.audioLevels).map { max($0, $1) }
        } else {
            // Fallback to mic levels if system isn't recording (e.g., during initial setup or error)
            return micRecorderManager.audioLevels
        }
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
            Spacer() // Верхний спейсер для вертикального центрирования
            
            // Title с красной точкой перед ним
            HStack(spacing: 8) {
                // Мигающая красная точка
                if micRecorderManager.isRecording {
                    Circle()
                        .fill(Color(NSColor.systemRed))
                        .frame(width: 8, height: 8)
                        .opacity(micRecorderManager.isRecording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: micRecorderManager.isRecording)
                }
                
                Text(micRecorderManager.isRecording ? "Recording" : displayError == nil ? "Preparing..." : "Error")
                    .font(.headline)
                    .foregroundColor(micRecorderManager.isRecording ? Color(NSColor.systemRed) : Color(NSColor.labelColor))
                    .animation(.easeInOut(duration: 0.1), value: micRecorderManager.isRecording)
            }

            // Display recording time (use mic recorder as primary timer)
            Text(formatTime(micRecorderManager.recordingTime))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .padding(.bottom, 8)

            // Визуализация во время записи
            if micRecorderManager.isRecording {
                // Use combinedAudioLevels instead of just micRecorderManager.audioLevels
                AudioWaveView(
                    levels: combinedAudioLevels,
                    activeColor: Color(NSColor.controlAccentColor),
                    isActive: true
                )
                .frame(height: 50)
            } else {
                // Иконка когда не записываем
                Image(systemName: displayError != nil ? "exclamationmark.circle" : "waveform")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 50))
                    .foregroundColor(displayError != nil ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor))
                    .padding()
            }

            // Display error message if any
            if let error = displayError {
                Text(error.localizedDescription)
                    .foregroundColor(Color(NSColor.systemRed))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 20) {
                // Кнопка Stop всегда красная
                Button("Stop") {
                    stopAndProcessRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(NSColor.systemRed))
                .keyboardShortcut(.return) // Enter для остановки
                .disabled(!canStopRecording || displayError != nil)

                // Cancel Button (всегда видна, но действие меняется)
                Button(micRecorderManager.isRecording ? "Cancel" : "Close") {
                    if micRecorderManager.isRecording {
                        cancelActiveRecording()
                    }
                    dismiss() 
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape) // Esc для отмены/закрытия
            }
            .padding(.top, 8)
            
            Spacer() // Нижний спейсер для вертикального центрирования
        }
        .padding(16) // Стандартный отступ macOS
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor)) // Стандартный фон macOS
        .onAppear {
            // Start recording automatically
            startCombinedRecording()
        }
        .onDisappear {
            // Ensure recording is stopped/cancelled if the view disappears unexpectedly
            let wasRecording = micRecorderManager.isRecording
             
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
        systemRecorderManager.error = nil
        
        // Start Mic Recording first (always works if mic permissions are granted)
        micRecorderManager.startRecording() 
        
        // Check if we can record system audio and start it conditionally
        Task {
            if #available(macOS 12.3, *) {
                let hasPermission = await systemRecorderManager.hasScreenCapturePermission()
                
                if hasPermission {
                    // Generate unique URL for system audio
                    let timestamp = Int(Date().timeIntervalSince1970)
                    guard let sysURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("sys_\(timestamp).caf") else {
                        print("Error generating system recording URL")
                        return
                    }
                    
                    await MainActor.run {
                        self.systemAudioOutputURL = sysURL
                        print("System Audio URL: \(sysURL.path)")
                        systemRecorderManager.startRecording(outputURL: sysURL)
                    }
                } else {
                    print("Screen capture permission not available. Recording only microphone audio.")
                }
            } else {
                print("System audio recording not available on this macOS version (< 12.3). Recording only microphone audio.")
            }
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
        // Stop System Audio (Simplified: Check if it was recording)
        if systemRecorderManager.isRecording {
            systemRecorderManager.stopRecording()
            systemAudioStoppedURL = self.systemAudioOutputURL // Use the URL we generated
            print("Stopped system audio recording. URL: \(systemAudioStoppedURL?.path ?? "nil")")
        } else {
             print("System audio recording was not active.")
        }
        
        // --- MERGING STEP --- 
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
        
        // Simplified: Stop and clean up system audio if it was recording
        if systemRecorderManager.isRecording {
            systemRecorderManager.stopRecording() 
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
         
         // Save the context to ensure the record is persisted
         do {
             try modelContext.save()
             print("Record saved successfully: \(newRecord.name)")
             
             // Post notification about new record creation
             NotificationCenter.default.post(
                 name: NSNotification.Name("NewRecordCreated"),
                 object: nil,
                 userInfo: ["recordId": newRecord.id]
             )
         } catch {
             print("Error saving record: \(error.localizedDescription)")
         }
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