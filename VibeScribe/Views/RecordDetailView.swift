//
//  RecordDetailView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData
import AVFoundation

// Detail view for a single record - Refactored to use AudioPlayerManager
struct RecordDetailView: View {
    // Use @Bindable for direct modification of @Model properties
    @Bindable var record: Record
    @Environment(\.dismiss) var dismiss
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isEditingSlider = false // Track if user is scrubbing

    // State for inline title editing
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool

    // Computed property for transcription text for easier access
    private var transcriptionText: String {
        record.hasTranscription ? "This is the placeholder for the transcription text. It would appear here once the audio is processed...\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua." : "Transcription not available yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Title (now editable) and Close button
            HStack {
                ZStack(alignment: .leading) {
                    // --- TextField (Visible when editing title) ---
                    TextField("Name", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .focused($isTitleFieldFocused)
                        .onSubmit { saveTitle() }
                        .font(.title2.bold()) // Match Text style
                        .opacity(isEditingTitle ? 1 : 0)
                        .disabled(!isEditingTitle)
                        .onTapGesture {}

                    // --- Text (Visible when not editing title) ---
                    Text(record.name)
                        .font(.title2.bold())
                        .opacity(isEditingTitle ? 0 : 1)
                        .onTapGesture(count: 2) {
                            startEditingTitle()
                        }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle()) // Remove button chrome
            }
            
            // --- Audio Player UI --- 
            VStack {
                HStack {
                    // Play/Pause Button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 30)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Progress Slider - Updated Logic
                    Slider(
                        value: $playerManager.currentTime, // Bind directly to player's current time for display
                        in: 0...(playerManager.duration > 0 ? playerManager.duration : 1.0),
                        onEditingChanged: { editing in
                            isEditingSlider = editing // Track scrubbing state
                            if editing {
                                playerManager.scrubbingStarted() // Tell manager scrubbing started
                            } else {
                                // Seek when scrubbing ends (using the current value from playerManager)
                                playerManager.seek(to: playerManager.currentTime)
                            }
                        }
                    )
                    // Remove the complex onChange modifier, direct binding handles updates when not editing
                    // .onChange(of: playerManager.currentTime) { oldValue, newValue in ... }


                    // Time Label
                    // Display player's current time / total duration
                    Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
            .disabled(playerManager.player == nil) // Disable based on manager state
            
            Divider()
            
            // Transcription Header with Copy Button
            HStack {
                Text("Transcription") // Removed colon for cleaner look
                    .font(.headline)
                Spacer()
                Button {
                    copyTranscription()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Transcription")
                .buttonStyle(PlainButtonStyle())
                // Disable button if no transcription
                .disabled(!record.hasTranscription)
            }
            
            // Revert back to Text for performance and no blinking cursor
            // Keep ScrollView for potentially long transcriptions
            ScrollView {
                Text(transcriptionText)
                    .foregroundColor(record.hasTranscription ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
                    // Enable text selection
                    .textSelection(.enabled)
                    // Explicitly change cursor on hover
                    .onHover { hovering in
                        if hovering {
                            NSCursor.iBeam.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    // Add padding within the ScrollView for the Text
                    .padding(5)
            }
            .frame(maxHeight: .infinity) // Allow scroll view to expand
            // Removed background, cornerRadius, and border from TextEditor/ScrollView

            // --- Transcribe Button (Always visible) --- 
            Button {
                // Action to start transcription (placeholder)
                print("Start transcription for \(record.name)")
                // In a real app, you'd trigger the transcription process here
                // and update the record's state eventually.
            } label: {
                Label("Transcribe", systemImage: "sparkles")
            }
            .buttonStyle(.bordered) // Apply standard bordered style
            .frame(maxWidth: .infinity, alignment: .center) // Center the button
            .padding(.top, 5) // Add some space above the button
            
            // No need for Spacer() if ScrollView uses maxHeight: .infinity
        }
        .padding() // Overall padding for the sheet content
        .onAppear {
            // --- Refined File Loading Logic ---
            guard let fileURL = record.fileURL else {
                print("Error: Record '\(record.name)' has no associated fileURL.")
                // Optionally disable player controls or show UI error
                // For now, we just prevent player setup
                return // Exit early
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Error: Audio file for record '\(record.name)' not found at path: \(fileURL.path)")
                // Optionally disable player controls or show UI error
                return // Exit early
            }

            print("Loading audio from: \(fileURL.path)")
            playerManager.setupPlayer(url: fileURL)
            // No need to initialize currentSliderValue here anymore
            // currentSliderValue = playerManager.currentTime
        }
        .onDisappear {
            playerManager.stopAndCleanup()
        }
        // Detect focus changes for the title TextField
        .onChange(of: isTitleFieldFocused) { oldValue, newValue in
            if !newValue && isEditingTitle { // If focus is lost AND we were editing
                cancelEditingTitle()
            }
        }
    }

    // --- Helper Functions --- 

    private func startEditingTitle() {
        editingTitle = record.name
        isEditingTitle = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
             isTitleFieldFocused = true
        }
        print("Started editing title for record: \(record.name)")
    }

    private func saveTitle() {
        if !editingTitle.isEmpty && editingTitle != record.name {
            print("Saving new title: \(editingTitle) for record ID: \(record.id)")
            record.name = editingTitle
        } else {
            print("Title unchanged or empty, reverting.")
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func cancelEditingTitle() {
        print("Cancelled editing title for record: \(record.name)")
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func copyTranscription() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptionText, forType: .string)
        print("Transcription copied to clipboard.")
    }
    
    // Helper to format time like MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 