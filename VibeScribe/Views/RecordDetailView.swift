//
//  RecordDetailView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData
import AVFoundation
import Combine
@_exported import Foundation // добавляем для доступа к WhisperTranscriptionManager

// Detail view for a single record - Refactored to use AudioPlayerManager
struct RecordDetailView: View {
    // Use @Bindable for direct modification of @Model properties
    @Bindable var record: Record
    @Environment(\.modelContext) private var modelContext
    @Query private var appSettings: [AppSettings]
    
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isEditingSlider = false // Track if user is scrubbing
    @State private var isTranscribing = false
    @State private var transcriptionError: String? = nil
    @State private var cancellables = Set<AnyCancellable>()

    // State for inline title editing - Переименовал для ясности
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool

    // Computed property for transcription text for easier access
    private var transcriptionText: String {
        if let text = record.transcriptionText, !text.isEmpty {
            return text
        } else if record.hasTranscription {
            return "Transcription processing... Check back later."
        } else {
            return "Transcription not available yet."
        }
    }
    
    // Получаем текущие настройки
    private var settings: AppSettings {
        appSettings.first ?? AppSettings()
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
                .disabled(!record.hasTranscription || record.transcriptionText == nil)
            }
            
            // Show error if exists
            if let error = transcriptionError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.bottom, 4)
            }
            
            // ScrollView for transcription
            ScrollView {
                Text(transcriptionText)
                    .font(.body)
                    .foregroundColor(record.hasTranscription && record.transcriptionText != nil ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
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
            .background(Color(NSColor.windowBackgroundColor)) // Добавляем непрозрачный фон для самого ScrollView

            // Transcribe Button 
            Button {
                startTranscription()
            } label: {
                HStack {
                    if isTranscribing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 5)
                    }
                    Label("Transcribe", systemImage: "waveform")
                }
                .frame(maxWidth: .infinity) // Растягиваем кнопку
            }
            .buttonStyle(.borderedProminent) // Акцентная кнопка
            .controlSize(.regular) // Стандартный размер
            .disabled(isTranscribing || record.fileURL == nil)
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
            // Отменяем все подписки при закрытии окна
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
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
        if let text = record.transcriptionText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("Transcription copied to clipboard.")
        }
    }
    
    // Функция для запуска транскрипции
    private func startTranscription() {
        guard let fileURL = record.fileURL, !isTranscribing else { return }
        
        isTranscribing = true
        transcriptionError = nil
        
        print("Starting transcription for: \(record.name), using Whisper API at URL: \(settings.whisperURL)")
        
        let whisperManager = WhisperTranscriptionManager.shared
        whisperManager.transcribeAudio(
            audioURL: fileURL, 
            whisperURL: settings.whisperURL,
            language: "ru", // Используем русский язык по умолчанию
            responseFormat: "srt" // Формат субтитров
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                isTranscribing = false
                
                switch completion {
                case .finished:
                    print("Transcription completed successfully")
                case .failure(let error):
                    transcriptionError = "Error: \(error.description)"
                    print("Transcription error: \(error.description)")
                }
            },
            receiveValue: { transcription in
                print("Received transcription of length: \(transcription.count) characters")
                record.transcriptionText = transcription
                record.hasTranscription = true
                try? modelContext.save()
            }
        )
        .store(in: &cancellables)
    }
    
    // Helper to format time like MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 