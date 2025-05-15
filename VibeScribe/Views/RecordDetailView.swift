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

    // State for inline title editing - Переименовал для ясности
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool

    // Computed property for transcription text for easier access
    private var transcriptionText: String {
        record.hasTranscription ? "This is the placeholder for the transcription text. It would appear here once the audio is processed...\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua." : "Transcription not available yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { // Стандартный интервал macOS
            // Header with Title (now editable) and Close button
            HStack {
                ZStack(alignment: .leading) {
                    // --- TextField (Visible when editing title) ---
                    TextField("Name", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .focused($isTitleFieldFocused)
                        .onSubmit { saveTitle() }
                        .font(.title2.bold())
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
                    Image(systemName: "xmark.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape)
            }
            
            // --- Audio Player UI --- 
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Play/Pause Button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(Color(NSColor.controlAccentColor))
                    }
                    .buttonStyle(.borderless)
                    .disabled(playerManager.player == nil)
                    .frame(width: 30, height: 30)
                    
                    // Progress Slider - Updated Logic
                    Slider(
                        value: $playerManager.currentTime,
                        in: 0...(playerManager.duration > 0 ? playerManager.duration : 1.0),
                        onEditingChanged: { editing in
                            isEditingSlider = editing
                            if editing {
                                playerManager.scrubbingStarted()
                            } else {
                                playerManager.seek(to: playerManager.currentTime)
                            }
                        }
                    )
                    .tint(Color(NSColor.controlAccentColor))

                    // Time Label
                    Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .disabled(playerManager.player == nil)
            
            Divider()
            
            // Transcription Header with Copy Button
            HStack {
                Text("Transcription")
                    .font(.headline)
                Spacer()
                Button {
                    copyTranscription()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly) // Только иконка
                        .symbolRenderingMode(.hierarchical) // Улучшенное отображение SF Symbol
                }
                .buttonStyle(.borderless) // Стандартный macOS стиль
                .help("Copy Transcription") // Всплывающая подсказка
                // Disable button if no transcription
                .disabled(!record.hasTranscription)
            }
            
            // ScrollView for transcription
            ScrollView {
                Text(transcriptionText)
                    .font(.body)
                    .foregroundColor(record.hasTranscription ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.iBeam.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
            }
            .frame(maxHeight: .infinity)

            // Transcribe Button 
            Button {
                // Action to start transcription (placeholder)
                print("Start transcription for \(record.name)")
            } label: {
                Label("Transcribe", systemImage: "waveform")
                    .frame(maxWidth: .infinity) // Растягиваем кнопку
            }
            .buttonStyle(.borderedProminent) // Акцентная кнопка
            .controlSize(.regular) // Стандартный размер
        }
        .padding(16) // Стандартный отступ macOS
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