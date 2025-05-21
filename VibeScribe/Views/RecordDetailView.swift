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
    @State private var selectedTab: Tab = .transcription // Tab selection state
    @State private var isSummarizing = false // Track summarization status
    @State private var summaryError: String? = nil

    // State for inline title editing - Переименовал для ясности
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool
    
    // Enum для вкладок
    enum Tab {
        case transcription
        case summary
    }

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
        VStack(alignment: .leading, spacing: 12) { // Уменьшаем базовый интервал
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
            .padding(.bottom, 4)
            
            // --- Audio Player UI --- 
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    // Play/Pause Button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
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
                    .controlSize(.small)
                    .frame(height: 16)

                    // Time Label
                    Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
                        .font(.caption)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .disabled(playerManager.player == nil)
            .padding(.bottom, 8)
            
            Divider()
            
            // Tab picker - properly centered segmented control following macOS HIG
            Picker("", selection: $selectedTab) {
                Text("Transcription").tag(Tab.transcription)
                Text("Summary").tag(Tab.summary)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300) // Limit width for better appearance
            .frame(maxWidth: .infinity, alignment: .center) // Center in the container
            .padding(.vertical, 8)
            
            // Tab content
            if selectedTab == .transcription {
                // Transcription Tab Content
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Button {
                            copyTranscription()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Transcription")
                        .disabled(!record.hasTranscription || record.transcriptionText == nil)
                    }
                    
                    // Show error if exists
                    if let error = transcriptionError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.bottom, 4)
                    }
                    
                    // ScrollView for transcription
                    ScrollView {
                        Text(transcriptionText)
                            .font(.body)
                            .foregroundStyle(record.hasTranscription && record.transcriptionText != nil ? 
                                            Color(NSColor.labelColor) : 
                                            Color(NSColor.secondaryLabelColor))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.iBeam.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Transcribe Button 
                    Button {
                        startTranscription()
                    } label: {
                        HStack {
                            if isTranscribing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 5)
                            }
                            Text("Transcribe")
                            Image(systemName: "waveform")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isTranscribing || record.fileURL == nil)
                    .padding(.top, 4)
                }
            } else {
                // Summary Tab Content
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Button {
                            copySummary()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Summary")
                        .disabled(record.summaryText == nil)
                    }
                    
                    // Show error if exists
                    if let error = summaryError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.bottom, 4)
                    }
                    
                    // ScrollView for summary
                    ScrollView {
                        if let summaryText = record.summaryText, !summaryText.isEmpty {
                            Text(summaryText)
                                .font(.body)
                                .foregroundStyle(Color(NSColor.labelColor))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.iBeam.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .padding(12)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                        } else {
                            Text("No summary available yet.")
                                .font(.body)
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Summarize Button 
                    Button {
                        startSummarization()
                    } label: {
                        HStack {
                            if isSummarizing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 5)
                            }
                            Text("Summarize")
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSummarizing || record.transcriptionText == nil || !record.hasTranscription)
                    .padding(.top, 4)
                }
            }
        }
        .padding(16) // Более компактный общий отступ
        .onAppear {
            // --- Refined File Loading Logic ---
            guard let fileURL = record.fileURL else {
                print("Error: Record '\(record.name)' has no associated fileURL.")
                return // Exit early
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Error: Audio file for record '\(record.name)' not found at path: \(fileURL.path)")
                return // Exit early
            }

            print("Loading audio from: \(fileURL.path)")
            playerManager.setupPlayer(url: fileURL)
            
            // If summary exists, switch to summary tab
            if let summaryText = record.summaryText, !summaryText.isEmpty {
                selectedTab = .summary
            }
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
    
    private func copySummary() {
        if let text = record.summaryText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("Summary copied to clipboard.")
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
    
    // Функция для запуска суммаризации
    private func startSummarization() {
        guard let transcriptionText = record.transcriptionText, 
              !transcriptionText.isEmpty,
              !isSummarizing else { return }
        
        isSummarizing = true
        summaryError = nil
        
        print("Starting summarization for: \(record.name), using OpenAI compatible API at URL: \(settings.openAICompatibleURL)")
        
        // Разбиваем транскрипцию на чанки
        let chunks = splitTranscriptionIntoChunks(transcriptionText, chunkSize: settings.chunkSize)
        print("Split transcription into \(chunks.count) chunks")
        
        // Создаем массив для хранения суммаризаций чанков
        var chunkSummaries = [String]()
        let group = DispatchGroup()
        
        // Суммаризируем каждый чанк
        for (index, chunk) in chunks.enumerated() {
            group.enter()
            
            summarizeChunk(chunk, index: index).sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Chunk \(index) summarization completed")
                    case .failure(let error):
                        print("Chunk \(index) summarization error: \(error.localizedDescription)")
                        summaryError = "Error summarizing chunk \(index): \(error.localizedDescription)"
                    }
                    group.leave()
                },
                receiveValue: { summary in
                    chunkSummaries.append(summary)
                }
            ).store(in: &cancellables)
        }
        
        // Когда все чанки суммаризированы, объединяем их
        group.notify(queue: .main) {
            if chunkSummaries.isEmpty {
                self.isSummarizing = false
                if self.summaryError == nil {
                    self.summaryError = "Failed to generate chunk summaries"
                }
                return
            }
            
            // Если есть только один чанк, используем его как финальную суммаризацию
            if chunkSummaries.count == 1 {
                self.record.summaryText = chunkSummaries[0]
                try? self.modelContext.save()
                self.isSummarizing = false
                return
            }
            
            // Если чанков несколько, объединяем их
            self.combineSummaries(chunkSummaries).sink(
                receiveCompletion: { completion in
                    self.isSummarizing = false
                    switch completion {
                    case .finished:
                        print("Combined summary completed")
                    case .failure(let error):
                        print("Combined summary error: \(error.localizedDescription)")
                        self.summaryError = "Error combining summaries: \(error.localizedDescription)"
                    }
                },
                receiveValue: { finalSummary in
                    self.record.summaryText = finalSummary
                    try? self.modelContext.save()
                }
            ).store(in: &self.cancellables)
        }
    }
    
    // Разбиваем транскрипцию на чанки
    private func splitTranscriptionIntoChunks(_ text: String, chunkSize: Int) -> [String] {
        var chunks = [String]()
        let words = text.split(separator: " ")
        var currentChunk = [Substring]()
        
        for word in words {
            currentChunk.append(word)
            if currentChunk.joined(separator: " ").count >= chunkSize {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = []
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks
    }
    
    // Суммаризируем один чанк
    private func summarizeChunk(_ chunk: String, index: Int) -> AnyPublisher<String, Error> {
        let prompt = settings.chunkPrompt.replacingOccurrences(of: "{transcription}", with: chunk)
        
        return callOpenAIAPI(
            prompt: prompt,
            url: settings.openAICompatibleURL
        )
    }
    
    // Объединяем суммаризации чанков
    private func combineSummaries(_ summaries: [String]) -> AnyPublisher<String, Error> {
        let combinedSummaries = summaries.joined(separator: "\n\n")
        let prompt = settings.summaryPrompt.replacingOccurrences(of: "{summaries}", with: combinedSummaries)
        
        return callOpenAIAPI(
            prompt: prompt,
            url: settings.openAICompatibleURL
        )
    }
    
    // Вызываем OpenAI-совместимый API
    private func callOpenAIAPI(prompt: String, url: String) -> AnyPublisher<String, Error> {
        return Future<String, Error> { promise in
            guard let url = URL(string: url) else {
                promise(.failure(NSError(domain: "Invalid URL", code: -1)))
                return
            }
            
            // Создаем запрос
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Формируем тело запроса
            let requestBody: [String: Any] = [
                "model": "gpt-3.5-turbo",
                "messages": [
                    ["role": "system", "content": "You are a helpful assistant."],
                    ["role": "user", "content": prompt]
                ]
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                promise(.failure(error))
                return
            }
            
            // Отправляем запрос
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let data = data else {
                    promise(.failure(NSError(domain: "No data received", code: -1)))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        promise(.success(content))
                    } else {
                        if let jsonStr = String(data: data, encoding: .utf8) {
                            print("Unexpected response format: \(jsonStr)")
                        }
                        promise(.failure(NSError(domain: "Invalid response format", code: -1)))
                    }
                } catch {
                    promise(.failure(error))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }
    
    // Helper to format time like MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 