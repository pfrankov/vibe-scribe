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

    // Use the new combined recorder manager
    @StateObject private var recorderManager = CombinedAudioRecorderManager()

    // Error handling
    private var displayError: Error? {
        recorderManager.error
    }
    
    // Recording state 
    private var isRecordingActive: Bool {
        recorderManager.isRecording
    }

    private var canStopRecording: Bool {
        recorderManager.isRecording && recorderManager.recordingTime >= 0.5
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
            Spacer() // Top spacer for vertical centering
            
            // Title with indicators
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    // Blinking red dot
                    if recorderManager.isRecording {
                        Circle()
                            .fill(Color(NSColor.systemRed))
                            .frame(width: 8, height: 8)
                            .opacity(recorderManager.isRecording ? 1 : 0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recorderManager.isRecording)
                    }
                    
                    Text(recorderManager.isRecording ? "Recording" : displayError == nil ? "Preparing..." : "Error")
                        .font(.headline)
                        .foregroundColor(recorderManager.isRecording ? Color(NSColor.systemRed) : Color(NSColor.labelColor))
                        .animation(.easeInOut(duration: 0.1), value: recorderManager.isRecording)
                }
                
                // System audio indicator
                if recorderManager.isRecording {
                    HStack(spacing: 4) {
                        Image(systemName: recorderManager.isSystemAudioRecording ? "speaker.wave.2" : "mic")
                            .font(.caption)
                            .foregroundColor(recorderManager.isSystemAudioRecording ? Color(NSColor.systemBlue) : Color(NSColor.secondaryLabelColor))
                        
                        Text(recorderManager.isSystemAudioRecording ? "Microphone + System Audio" : "Microphone Only")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                }
            }

            // Display recording time
            Text(formatTime(recorderManager.recordingTime))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .padding(.bottom, 8)

            // Audio visualization during recording
            if recorderManager.isRecording {
                AudioWaveView(
                    levels: recorderManager.audioLevels,
                    activeColor: Color(NSColor.controlAccentColor),
                    isActive: true
                )
                .frame(height: 50)
            } else {
                // Icon when not recording
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
                // Stop button - always red
                Button("Stop") {
                    stopAndProcessRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(NSColor.systemRed))
                .keyboardShortcut(.return) // Enter to stop
                .disabled(!canStopRecording || displayError != nil)

                // Cancel Button - always visible, but action changes
                Button(recorderManager.isRecording ? "Cancel" : "Close") {
                    if recorderManager.isRecording {
                        cancelActiveRecording()
                    }
                    dismiss() 
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape) // Escape to cancel/close
            }
            .padding(.top, 8)
            
            Spacer() // Bottom spacer for vertical centering
        }
        .padding(16) // Standard macOS padding
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor)) // Standard macOS background
        .onAppear {
            // Start recording automatically
            startRecording()
        }
        .onDisappear {
            // Ensure recording is stopped/cancelled if the view disappears unexpectedly
            let wasRecording = recorderManager.isRecording
             
            if wasRecording {
                print("RecordingView disappeared while recording. Cancelling.")
                cancelActiveRecording()
            }
        }
    }
    
    // MARK: - Recording Control Functions
    
    private func startRecording() {
        Logger.info("Starting recording from RecordingView", category: .audio)
        recorderManager.startRecording()
    }
    
    private func stopAndProcessRecording() {
        guard let result = recorderManager.stopRecording() else {
            Logger.error("Failed to stop recording properly", category: .audio)
            dismiss()
            return
        }
        
        Logger.info("Recording stopped successfully, saving record", category: .audio)
        createAndSaveRecord(url: result.url, duration: result.duration, includesSystemAudio: result.includesSystemAudio)
        dismiss()
    }
    
    private func cancelActiveRecording() {
        Logger.info("Cancelling active recording", category: .audio)
        recorderManager.cancelRecording()
    }
    
    // Helper to create and save the Record object
    private func createAndSaveRecord(url: URL, duration: TimeInterval, includesSystemAudio: Bool) {
         let defaultName = "Recording \(recordingNameFormatter.string(from: Date()))"
         let newRecord = Record(name: defaultName, fileURL: url, duration: duration, includesSystemAudio: includesSystemAudio)
         
         Logger.info("Creating record: \(newRecord.name) at \(url.path), includes system audio: \(includesSystemAudio)", category: .audio)
         modelContext.insert(newRecord)
         
         // Save the context to ensure the record is persisted
         do {
             try modelContext.save()
             Logger.info("Record saved successfully: \(newRecord.name)", category: .audio)
             
             // Post notification about new record creation
             NotificationCenter.default.post(
                 name: NSNotification.Name("NewRecordCreated"),
                 object: nil,
                 userInfo: ["recordId": newRecord.id]
             )
         } catch {
             Logger.error("Error saving record", error: error, category: .audio)
         }
    }



    // Re-use the time formatter from RecordDetailView
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 