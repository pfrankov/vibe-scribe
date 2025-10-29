//
//  RecordProcessingManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 26.04.2025.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class RecordProcessingManager: ObservableObject {
    // MARK: - Nested Types
    
    struct RecordProcessingState: Equatable {
        var isTranscribing: Bool = false
        var isSummarizing: Bool = false
        var transcriptionError: String? = nil
        var summaryError: String? = nil
        var isStreaming: Bool = false
        var streamingChunks: [String] = []
        var pendingTranscriptionCount: Int = 0
        var pendingSummarizationCount: Int = 0
    }
    
    struct SettingsSnapshot: Equatable {
        let whisperProviderRawValue: String
        let whisperBaseURL: String
        let whisperAPIKey: String
        let whisperModel: String
        let openAIBaseURL: String
        let openAIAPIKey: String
        let openAIModel: String
        let useChunking: Bool
        let chunkSize: Int
        let chunkPrompt: String
        let summaryPrompt: String
        let autoGenerateTitleFromSummary: Bool
        let summaryTitlePrompt: String
        let speechAnalyzerLocaleIdentifier: String
        
        init(settings: AppSettings) {
            self.whisperProviderRawValue = settings.whisperProviderRawValue
            self.whisperBaseURL = settings.whisperBaseURL
            self.whisperAPIKey = settings.whisperAPIKey
            self.whisperModel = settings.whisperModel
            self.openAIBaseURL = settings.openAIBaseURL
            self.openAIAPIKey = settings.openAIAPIKey
            self.openAIModel = settings.openAIModel
            self.useChunking = settings.useChunking
            self.chunkSize = settings.chunkSize
            self.chunkPrompt = settings.chunkPrompt
            self.summaryPrompt = settings.summaryPrompt
            self.autoGenerateTitleFromSummary = settings.autoGenerateTitleFromSummary
            self.summaryTitlePrompt = settings.summaryTitlePrompt
            self.speechAnalyzerLocaleIdentifier = settings.speechAnalyzerLocaleIdentifier
        }
        
        var resolvedWhisperModel: String {
            whisperModel.isEmpty ? "whisper-1" : whisperModel
        }
        
        var whisperProvider: WhisperProvider {
            WhisperProvider(rawValue: whisperProviderRawValue) ?? .compatibleAPI
        }
        
        var resolvedWhisperBaseURL: String {
            whisperProvider.resolvedBaseURL(using: whisperBaseURL)
        }

        var resolvedWhisperAPIKey: String {
            whisperProvider.resolvedAPIKey(using: whisperAPIKey)
        }
        
        var usesSpeechAnalyzer: Bool {
            whisperProvider == .speechAnalyzer
        }
        
        var selectedSpeechAnalyzerLocale: Locale? {
            guard !speechAnalyzerLocaleIdentifier.isEmpty else { return nil }
            return Locale(identifier: speechAnalyzerLocaleIdentifier)
        }
        
        /// Creates minimal AppSettings for Whisper API calls
        func makeWhisperSettings() -> AppSettings {
            let baseURL = resolvedWhisperBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = resolvedWhisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return AppSettings(
                whisperProvider: .compatibleAPI,
                whisperBaseURL: baseURL,
                whisperAPIKey: apiKey,
                whisperModel: resolvedWhisperModel,
                useChunking: false,
                chunkSize: 0,
                openAIBaseURL: "",
                openAIAPIKey: "",
                openAIModel: "",
                chunkPrompt: "",
                summaryPrompt: ""
            )
        }
    }
    
    private enum Operation {
        case transcription(preferStreaming: Bool, automatic: Bool)
        case summarization(automatic: Bool)
    }
    
    private struct ProcessingJob {
        let id = UUID()
        let recordID: UUID
        let modelContext: ModelContext
        let settings: SettingsSnapshot
        let operation: Operation
    }
    
    private enum RecordProcessingError: LocalizedError {
        case recordNotFound
        case missingAudioFile
        case emptyCleanText
        case summaryEmpty
        case invalidURL
        case invalidResponse
        case openAIHTTPError(Int)
        case chunkFailed(Int, String)
        
        var errorDescription: String? {
            switch self {
            case .recordNotFound:
                return "Record not found. It may have been deleted."
            case .missingAudioFile:
                return "Audio file not found on disk."
            case .emptyCleanText:
                return "Transcription text is empty after processing."
            case .summaryEmpty:
                return "Summary is empty."
            case .invalidURL:
                return "Invalid API URL."
            case .invalidResponse:
                return "Unexpected response format from LLM server."
            case .openAIHTTPError(let code):
                return "HTTP error from LLM server: \(code)"
            case .chunkFailed(let index, let message):
                return "Error summarizing chunk \(index + 1): \(message)"
            }
        }
    }
    
    // MARK: - Singleton
    
    static let shared = RecordProcessingManager()
    
    // MARK: - Published State
    
    @Published private(set) var recordStates: [UUID: RecordProcessingState] = [:]
    
    // MARK: - Private Properties
    
    private var jobQueue: [ProcessingJob] = []
    private var activeJob: ProcessingJob?
    private var activeTask: Task<Void, Never>?
    private var activeCancellables: [UUID: AnyCancellable] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    func state(for recordID: UUID) -> RecordProcessingState {
        recordStates[recordID] ?? RecordProcessingState()
    }
    
    func enqueueTranscription(
        for record: Record,
        in context: ModelContext,
        settings: AppSettings,
        automatic: Bool,
        preferStreaming: Bool = true
    ) {
        let snapshot = SettingsSnapshot(settings: settings)
        let resolvedPreferStreaming = preferStreaming && snapshot.whisperProvider != .speechAnalyzer
        let job = ProcessingJob(
            recordID: record.id,
            modelContext: context,
            settings: snapshot,
            operation: .transcription(preferStreaming: resolvedPreferStreaming, automatic: automatic)
        )
        append(job)
    }
    
    func enqueueSummarization(
        for record: Record,
        in context: ModelContext,
        settings: AppSettings,
        automatic: Bool
    ) {
        let snapshot = SettingsSnapshot(settings: settings)
        let job = ProcessingJob(
            recordID: record.id,
            modelContext: context,
            settings: snapshot,
            operation: .summarization(automatic: automatic)
        )
        append(job)
    }

    private func enqueueSummarization(
        recordID: UUID,
        context: ModelContext,
        settings: SettingsSnapshot,
        automatic: Bool
    ) {
        let job = ProcessingJob(
            recordID: recordID,
            modelContext: context,
            settings: settings,
            operation: .summarization(automatic: automatic)
        )
        append(job)
    }
    
    // MARK: - Queue Handling
    
    private func append(_ job: ProcessingJob) {
        updateState(for: job.recordID) { state in
            switch job.operation {
            case .transcription:
                state.pendingTranscriptionCount += 1
            case .summarization:
                state.pendingSummarizationCount += 1
            }
        }
        
        jobQueue.append(job)
        processNextIfNeeded()
    }
    
    private func processNextIfNeeded() {
        guard activeJob == nil, activeTask == nil, !jobQueue.isEmpty else { return }
        
        let job = jobQueue.removeFirst()
        activeJob = job
        
        updateState(for: job.recordID) { state in
            switch job.operation {
            case .transcription:
                state.pendingTranscriptionCount = max(0, state.pendingTranscriptionCount - 1)
                state.isTranscribing = true
                state.transcriptionError = nil
            case .summarization:
                state.pendingSummarizationCount = max(0, state.pendingSummarizationCount - 1)
                state.isSummarizing = true
                state.summaryError = nil
            }
        }
        
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(job)
        }
    }
    
    private func execute(_ job: ProcessingJob) async {
        defer {
            activeCancellables.removeValue(forKey: job.id)
            activeTask = nil
            activeJob = nil
            
            updateState(for: job.recordID) { state in
                switch job.operation {
                case .transcription:
                    state.isTranscribing = false
                    state.isStreaming = false
                    state.streamingChunks.removeAll()
                case .summarization:
                    state.isSummarizing = false
                }
            }
            
            processNextIfNeeded()
        }
        
        switch job.operation {
        case .transcription(let preferStreaming, let automatic):
            await executeTranscription(job, preferStreaming: preferStreaming, automatic: automatic)
        case .summarization(let automatic):
            await executeSummarization(job, automatic: automatic)
        }
    }
    
    // MARK: - Transcription
    
    private func executeTranscription(
        _ job: ProcessingJob,
        preferStreaming: Bool,
        automatic: Bool
    ) async {
        guard let record = fetchRecord(id: job.recordID, in: job.modelContext) else {
            updateState(for: job.recordID) { state in
                state.transcriptionError = RecordProcessingError.recordNotFound.localizedDescription
            }
            return
        }
        
        guard
            let fileURL = record.fileURL,
            FileManager.default.fileExists(atPath: fileURL.path)
        else {
            updateState(for: job.recordID) { state in
                state.transcriptionError = RecordProcessingError.missingAudioFile.localizedDescription
            }
            return
        }
        
        do {
            let transcriptionText: String
            if job.settings.usesSpeechAnalyzer {
                do {
                    let localeOverride = job.settings.selectedSpeechAnalyzerLocale
                    transcriptionText = try await performSpeechAnalyzerTranscription(fileURL: fileURL, locale: localeOverride)
                } catch let error as TranscriptionError {
                    Logger.warning("Native transcription failed: \(error.description). Falling back to configured service.", category: .transcription)
                    transcriptionText = try await performRegularTranscription(job: job, fileURL: fileURL)
                } catch {
                    Logger.warning("Native transcription failed with unexpected error: \(error.localizedDescription). Falling back to configured service.", category: .transcription)
                    transcriptionText = try await performRegularTranscription(job: job, fileURL: fileURL)
                }
            } else if preferStreaming {
                do {
                    transcriptionText = try await attemptStreamingTranscription(job: job, fileURL: fileURL)
                } catch let error as TranscriptionError {
                    if case .streamingNotSupported = error {
                        Logger.warning("SSE not supported, falling back to regular transcription.", category: .transcription)
                        transcriptionText = try await performRegularTranscription(job: job, fileURL: fileURL)
                    } else {
                        throw error
                    }
                }
            } else {
                transcriptionText = try await performRegularTranscription(job: job, fileURL: fileURL)
            }
            
            let trimmed = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.isEmpty {
                record.hasTranscription = true
                record.transcriptionText = ""
                updateState(for: job.recordID) { state in
                    state.transcriptionError = "Error: Empty transcription received. Please try again with a different model or check your audio quality."
                }
            } else {
                record.hasTranscription = true
                record.transcriptionText = trimmed
                updateState(for: job.recordID) { state in
                    state.transcriptionError = nil
                }
            }
            
            try job.modelContext.save()
            
            if automatic, !trimmed.isEmpty {
                enqueueSummarization(recordID: job.recordID, context: job.modelContext, settings: job.settings, automatic: true)
            }
        } catch let error as TranscriptionError {
            updateState(for: job.recordID) { state in
                state.transcriptionError = "Error: \(error.description)"
            }
        } catch {
            updateState(for: job.recordID) { state in
                state.transcriptionError = "Error: \(error.localizedDescription)"
            }
        }
    }
    private func attemptStreamingTranscription(job: ProcessingJob, fileURL: URL) async throws -> String {
        var accumulatedText = ""
        let settingsModel = job.settings.makeWhisperSettings()
        
        return try await withCheckedThrowingContinuation { continuation in
            let cancellable = WhisperTranscriptionManager.shared
                .transcribeAudioRealTime(audioURL: fileURL, settings: settingsModel)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        guard let self else { return }
                        self.activeCancellables.removeValue(forKey: job.id)
                        self.updateState(for: job.recordID) { state in
                            state.isStreaming = false
                        }
                        
                        switch completion {
                        case .finished:
                            continuation.resume(returning: accumulatedText)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { [weak self] update in
                        guard let self else { return }
                        let cleanText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanText.isEmpty else { return }
                        
                        self.updateStreamingState(for: job.recordID, with: cleanText)
                        
                        if update.isPartial {
                            if accumulatedText.isEmpty {
                                accumulatedText = cleanText
                            } else {
                                accumulatedText += " \(cleanText)"
                            }
                        } else {
                            accumulatedText = cleanText
                        }
                    }
                )
            
            activeCancellables[job.id] = cancellable
        }
    }
    
    private func performSpeechAnalyzerTranscription(fileURL: URL, locale: Locale?) async throws -> String {
        guard SpeechAnalyzerTranscriptionManager.shared.isSupported() else {
            throw TranscriptionError.featureUnavailable
        }
        return try await SpeechAnalyzerTranscriptionManager.shared.transcribeAudio(at: fileURL, locale: locale)
    }
    
    private func performRegularTranscription(job: ProcessingJob, fileURL: URL) async throws -> String {
        let fallbackBaseURL = job.settings.resolvedWhisperBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackBaseURL.isEmpty else {
            throw TranscriptionError.processingFailed("Remote transcription fallback requires a configured Whisper endpoint.")
        }

        guard APIURLBuilder.isValidBaseURL(fallbackBaseURL) else {
            throw TranscriptionError.processingFailed("Whisper endpoint \(fallbackBaseURL) is not a valid base URL.")
        }

        let settingsModel = job.settings.makeWhisperSettings()
        var didResume = false
        
        return try await withCheckedThrowingContinuation { continuation in
            let cancellable = WhisperTranscriptionManager.shared
                .transcribeAudio(audioURL: fileURL, settings: settingsModel, useStreaming: false)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        guard let self else { return }
                        self.activeCancellables.removeValue(forKey: job.id)
                        
                        if didResume {
                            return
                        }
                        
                        switch completion {
                        case .finished:
                            // Nothing to do; value already delivered.
                            break
                        case .failure(let error):
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                    },
                    receiveValue: { transcription in
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(returning: transcription)
                    }
                )
            
            activeCancellables[job.id] = cancellable
        }
    }
    
    private func updateStreamingState(for recordID: UUID, with cleanText: String) {
        updateState(for: recordID) { state in
            state.isStreaming = true
            
            let words = cleanText.split(whereSeparator: \.isWhitespace)
            let chunk = words.suffix(12).joined(separator: " ")
            
            if !chunk.isEmpty, state.streamingChunks.last != chunk {
                state.streamingChunks.append(chunk)
                if state.streamingChunks.count > 10 {
                    state.streamingChunks.removeFirst()
                }
            }
        }
    }
    
    // MARK: - Summarization
    
    private func executeSummarization(_ job: ProcessingJob, automatic: Bool) async {
        guard let record = fetchRecord(id: job.recordID, in: job.modelContext) else {
            updateState(for: job.recordID) { state in
                state.summaryError = RecordProcessingError.recordNotFound.localizedDescription
            }
            return
        }

        if automatic {
            Logger.debug("Automatic summarization triggered for record \(record.name)", category: .llm)
        }
        
        guard
            let transcriptionText = record.transcriptionText,
            !transcriptionText.isEmpty
        else {
            updateState(for: job.recordID) { state in
                state.summaryError = "Transcription text is required before summarizing."
            }
            return
        }
        
        let cleanText = extractCleanText(from: transcriptionText)
        
        guard !cleanText.isEmpty else {
            updateState(for: job.recordID) { state in
                state.summaryError = RecordProcessingError.emptyCleanText.localizedDescription
            }
            return
        }
        
        do {
            let summary = try await generateSummary(for: cleanText, job: job)
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedSummary.isEmpty else {
                throw RecordProcessingError.summaryEmpty
            }
            
            record.summaryText = trimmedSummary
            try job.modelContext.save()
            
            updateState(for: job.recordID) { state in
                state.summaryError = nil
            }
            
            if job.settings.autoGenerateTitleFromSummary {
                await maybeGenerateTitle(for: record, summary: trimmedSummary, job: job)
            }
        } catch {
            updateState(for: job.recordID) { state in
                state.summaryError = "Error: \((error as? RecordProcessingError)?.localizedDescription ?? error.localizedDescription)"
            }
        }
    }
    
    private func generateSummary(for text: String, job: ProcessingJob) async throws -> String {
        guard job.settings.useChunking else {
            let prompt = job.settings.chunkPrompt.replacingOccurrences(of: "{transcription}", with: text)
            return try await callOpenAIAPI(prompt: prompt, settings: job.settings)
        }
        
        let chunks = TextChunker.chunkText(text, maxChunkSize: job.settings.chunkSize, forceChunking: false)
        var chunkSummaries: [String] = []
        
        for (index, chunk) in chunks.enumerated() {
            let prompt = job.settings.chunkPrompt.replacingOccurrences(of: "{transcription}", with: chunk)
            do {
                let summary = try await callOpenAIAPI(prompt: prompt, settings: job.settings)
                chunkSummaries.append(summary)
            } catch {
                throw RecordProcessingError.chunkFailed(index, error.localizedDescription)
            }
        }
        
        guard !chunkSummaries.isEmpty else {
            throw RecordProcessingError.summaryEmpty
        }
        
        if chunkSummaries.count == 1 {
            return chunkSummaries[0]
        }
        
        let combined = chunkSummaries.joined(separator: "\n\n")
        let prompt = job.settings.summaryPrompt.replacingOccurrences(of: "{transcription}", with: combined)
        return try await callOpenAIAPI(prompt: prompt, settings: job.settings)
    }
    
    private func maybeGenerateTitle(for record: Record, summary: String, job: ProcessingJob) async {
        let prompt = job.settings.summaryTitlePrompt.replacingOccurrences(of: "{summary}", with: summary)
        
        do {
            let rawTitle = try await callOpenAIAPI(prompt: prompt, settings: job.settings)
            let sanitizedTitle = sanitizeGeneratedTitle(rawTitle)
            
            guard !sanitizedTitle.isEmpty else {
                Logger.error("Generated title is empty after sanitization; keeping existing name.", category: .llm)
                return
            }
            
            if record.name == sanitizedTitle {
                Logger.info("Generated title matches existing name '\(sanitizedTitle)'; no update needed.", category: .llm)
                return
            }
            
            record.name = sanitizedTitle
            try job.modelContext.save()
            Logger.info("Auto-generated title saved: \(sanitizedTitle)", category: .llm)
        } catch {
            Logger.error("Failed to generate title from summary: \(error.localizedDescription)", category: .llm)
        }
    }
    
    // MARK: - OpenAI Compatible Calls
    
    private func callOpenAIAPI(prompt: String, settings: SettingsSnapshot) async throws -> String {
        guard let url = APIURLBuilder.buildURL(baseURL: settings.openAIBaseURL, endpoint: "chat/completions") else {
            throw RecordProcessingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !settings.openAIAPIKey.isEmpty {
            let cleanAPIKey = SecurityUtils.sanitizeAPIKey(settings.openAIAPIKey)
            request.setValue("Bearer \(cleanAPIKey)", forHTTPHeaderField: "Authorization")
            Logger.debug("Using LLM API key \(SecurityUtils.maskAPIKey(cleanAPIKey))", category: .llm)
        } else {
            Logger.debug("No API key provided for LLM request.", category: .llm)
        }
        
        let body: [String: Any] = [
            "model": settings.openAIModel,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        Logger.info("🤖 Sending LLM request to \(url.absoluteString)", category: .llm)
        Logger.info("📜 Prompt length: \(prompt.count) characters", category: .llm)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecordProcessingError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw RecordProcessingError.openAIHTTPError(httpResponse.statusCode)
        }
        
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        
        guard
            let json = jsonObject as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.error("❌ Unexpected LLM response: \(jsonString)", category: .llm)
            }
            throw RecordProcessingError.invalidResponse
        }
        
        Logger.info("✅ LLM response received (\(content.count) characters)", category: .llm)
        
        if let usage = json["usage"] as? [String: Any] {
            let promptTokens = usage["prompt_tokens"] as? Int ?? 0
            let completionTokens = usage["completion_tokens"] as? Int ?? 0
            let totalTokens = usage["total_tokens"] as? Int ?? 0
            Logger.info("📈 Token usage — Prompt: \(promptTokens), Completion: \(completionTokens), Total: \(totalTokens)", category: .llm)
        }
        
        return content
    }
    
    private func sanitizeGeneratedTitle(_ rawTitle: String) -> String {
        let quotesCharacterSet = CharacterSet(charactersIn: "\"'“”‘’`")
        let punctuationAndWhitespace = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        
        var cleaned = rawTitle
            .components(separatedBy: quotesCharacterSet)
            .joined()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        cleaned = cleaned.trimmingCharacters(in: punctuationAndWhitespace)
        
        if cleaned.lowercased().hasPrefix("title:") {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 6)
            cleaned = String(cleaned[index...]).trimmingCharacters(in: punctuationAndWhitespace)
        } else if cleaned.lowercased().hasPrefix("heading:") {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 8)
            cleaned = String(cleaned[index...]).trimmingCharacters(in: punctuationAndWhitespace)
        }
        
        let words = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(5)
        
        return words.joined(separator: " ").trimmingCharacters(in: punctuationAndWhitespace)
    }
    
    // MARK: - Helpers
    
    private func updateState(for recordID: UUID, mutate: (inout RecordProcessingState) -> Void) {
        var state = recordStates[recordID] ?? RecordProcessingState()
        mutate(&state)
        recordStates[recordID] = state
    }
    
    private func fetchRecord(id: UUID, in context: ModelContext) -> Record? {
        let descriptor = FetchDescriptor<Record>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
    
    /// Extracts clean text from transcription, handling SRT format if present
    private func extractCleanText(from transcriptionText: String) -> String {
        if transcriptionText.contains("-->"), transcriptionText.contains("\n\n") {
            return WhisperTranscriptionManager.shared.extractTextFromSRT(transcriptionText)
        }
        return transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
