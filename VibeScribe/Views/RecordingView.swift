//
//  RecordingView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// --- Updated Recording View --- 
struct RecordingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var recorderManager = AudioRecorderManager()
    
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
            Text(recorderManager.isRecording ? "Recording..." : recorderManager.error == nil ? "Preparing..." : "Error") // Updated title logic
                .font(.title)

            // Display recording time
            Text(formatTime(recorderManager.recordingTime))
                .font(.title2)
                .monospacedDigit() // Ensures stable width
                .padding(.bottom)

            // Replace microphone icon with audio wave visualization when recording
            if recorderManager.isRecording {
                // Аудио волна во время записи
                AudioWaveView(
                    levels: recorderManager.audioLevels,
                    activeColor: .red,
                    isActive: true
                )
            } else {
                // Иконка микрофона когда не записываем
                Image(systemName: recorderManager.error != nil ? "mic.slash.fill" : "mic.fill") // Show mic.fill if ready
                    .font(.system(size: 60))
                    .foregroundColor(recorderManager.error != nil ? .orange : .secondary)
                    .padding()
            }

            // Display error message if any
            if let error = recorderManager.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            HStack {
                // --- Updated Button Logic ---
                Button("Stop") {
                    // Stop recording
                     guard let result = recorderManager.stopRecording() else {
                         // Handle error if stopRecording failed (error is likely set in manager)
                         // Maybe show an alert or log
                         print("Failed to stop recording properly.")
                         // We might still want to dismiss, or keep the view open showing the error
                         dismiss()
                         return
                     }
                    
                    // <<< Create and save the new Record >>>
                    let defaultName = "Recording \(recordingNameFormatter.string(from: Date()))"
                    let newRecord = Record(name: defaultName, fileURL: result.url, duration: result.duration)
                    
                    print("Attempting to insert new record: \(newRecord.name)")
                    modelContext.insert(newRecord)
                    
                    // Optional: Explicit save, though autosave should work
                    // do {
                    //     try modelContext.save()
                    //     print("New record saved successfully.")
                    // } catch {
                    //     print("Error saving context after inserting record: \(error)")
                    //     // Handle error saving the context (e.g., show alert)
                    // }

                    dismiss() // Dismiss the sheet after stopping and attempting save
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red) // Always red as it's the "Stop" action
                // Disable Stop button if not recording OR if recording time is too short (prevents accidental taps) OR if there's an error
                .disabled(!recorderManager.isRecording || recorderManager.recordingTime < 0.5 || recorderManager.error != nil)

                // Cancel Button (Always visible, but primary action changes)
                // If recording: Cancels the recording
                // If not recording (e.g., during setup or error): Closes the sheet
                Button(recorderManager.isRecording ? "Cancel" : "Close") {
                    if recorderManager.isRecording {
                        recorderManager.cancelRecording()
                        // No need to call onComplete
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
            print("RecordingView appeared. Attempting to start recording.")
            // Clear previous errors before starting
             recorderManager.error = nil 
            recorderManager.startRecording()
        }
        .onDisappear {
            // Ensure recording is stopped/cancelled if the view disappears unexpectedly
            // This might happen if the user closes the window or the app quits
            if recorderManager.isRecording {
                print("RecordingView disappeared while recording. Cancelling.")
                // We call cancel which also cleans up the file
                recorderManager.cancelRecording() 
                // We might want to inform the caller, but onComplete might not be valid anymore
                // onComplete(nil, nil) // Be cautious calling this here
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