//
//  WhisperTranscriptionManager.swift
//  VibeScribe
//
//  Created by System on 15.04.2025.
//

import Foundation
import Combine
import AVFoundation
import EventSource

// Error types for transcription process
enum TranscriptionError: Error {
    case invalidAudioFile
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case unknownError
    case dataParsingError(String)
    case streamingNotSupported
    case eventSourceError(String)
    
    var description: String {
        switch self {
        case .invalidAudioFile:
            return "Audio file is invalid or corrupted"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknownError:
            return "An unknown error occurred"
        case .dataParsingError(let message):
            return "Data parsing error: \(message)"
        case .streamingNotSupported:
            return "Server doesn't support SSE streaming"
        case .eventSourceError(let message):
            return "EventSource error: \(message)"
        }
    }
}

// Structure for real-time transcription updates
struct TranscriptionUpdate: Sendable {
    let isPartial: Bool     // Whether this is a partial or final result
    let text: String        // The transcription text
    let timestamp: Date     // When this update was received
    
    init(isPartial: Bool, text: String) {
        self.isPartial = isPartial
        self.text = text
        self.timestamp = Date()
    }
}

// MARK: - WhisperTranscriptionManager

// Класс для работы с Whisper API с поддержкой SSE через EventSource
class WhisperTranscriptionManager {
    static let shared = WhisperTranscriptionManager()
    
    // Cache for server SSE support to avoid repeated checks
    private var serverSupportsSSE: [String: Bool] = [:]
    private let cacheQueue = DispatchQueue(label: "whisper.cache.queue", attributes: .concurrent)
    
    private init() {}
    
    // MARK: - Main API Methods
    
    // Main transcription method - always tries SSE first, then fallback
    func transcribeAudio(audioURL: URL, settings: AppSettings) -> AnyPublisher<String, TranscriptionError> {
        print("🎯 Starting transcription for: \(audioURL.lastPathComponent)")
        
        // Check if we already know this server doesn't support SSE
        let serverKey = settings.whisperBaseURL
        if let cachedResult = getCachedSSESupport(for: serverKey), !cachedResult {
            print("📋 Server \(serverKey) known to not support SSE, using regular mode")
            return transcribeAudioRegular(
                audioURL: audioURL,
                whisperBaseURL: settings.whisperBaseURL,
                apiKey: settings.whisperAPIKey,
                model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel
            )
        }
        
        // Always try SSE streaming first (same endpoint, stream=true)
        print("🚀 Attempting SSE streaming with stream=true parameter...")
        return transcribeAudioStreaming(
            audioURL: audioURL,
            whisperBaseURL: settings.whisperBaseURL,
            apiKey: settings.whisperAPIKey,
            model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel
        )
        .catch { error -> AnyPublisher<String, TranscriptionError> in
            if case .streamingNotSupported = error {
                print("⚠️ SSE streaming not supported, falling back to regular mode")
                self.setCachedSSESupport(for: serverKey, supports: false)
                
                return self.transcribeAudioRegular(
                    audioURL: audioURL,
                    whisperBaseURL: settings.whisperBaseURL,
                    apiKey: settings.whisperAPIKey,
                    model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel
                )
            } else {
                print("❌ SSE streaming failed with error: \(error.description)")
                return Fail(error: error).eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }
    
    // Real-time streaming method with intermediate updates using EventSource
    func transcribeAudioRealTime(audioURL: URL, settings: AppSettings) -> AnyPublisher<TranscriptionUpdate, TranscriptionError> {
        print("⚡ Starting REAL-TIME streaming transcription for: \(audioURL.lastPathComponent)")
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ Error: Audio file not found at path: \(audioURL.path)")
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
        
        guard let serverURL = APIURLBuilder.buildURL(baseURL: settings.whisperBaseURL, endpoint: "audio/transcriptions") else {
            print("❌ Error: Invalid Whisper API base URL: \(settings.whisperBaseURL)")
            return Fail(error: TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1, userInfo: nil))).eraseToAnyPublisher()
        }
        
        print("🔗 Using transcription endpoint with stream=true for REAL-TIME: \(serverURL.absoluteString)")
        
        // Use PassthroughSubject to send multiple updates
        let subject = PassthroughSubject<TranscriptionUpdate, TranscriptionError>()
        
        Task {
            do {
                let request = try self.buildStreamingRequest(
                    url: serverURL,
                    audioURL: audioURL,
                    apiKey: settings.whisperAPIKey,
                    model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel
                )
                
                // Use EventSource for clean SSE handling
                let eventSource = EventSource(mode: .dataOnly)
                let dataTask = await eventSource.dataTask(for: request)
                
                var responseText = ""
                
                for await event in await dataTask.events() {
                    switch event {
                    case .open:
                        print("✅ Real-time SSE connection established")
                        
                    case .event(let sseEvent):
                        if let eventData = sseEvent.data {
                            print("📨 Real-time SSE Event: '\(eventData)'")
                            
                            // Parse the streaming data
                            if let update = self.parseStreamingData(eventData) {
                                // Accumulate text for final result
                                if !update.text.isEmpty {
                                    responseText += (responseText.isEmpty ? "" : " ") + update.text
                                    print("🔄 Real-time accumulated: \(responseText.count) chars")
                                }
                                
                                // Send each update for real-time display
                                subject.send(update)
                                
                                // Don't cancel on partial updates - wait for connection to close
                                // Only cancel if we get explicit final signal
                                if !update.isPartial {
                                    print("✅ Real-time transcription completed: \(update.text)")
                                    await dataTask.cancel()
                                    subject.send(completion: .finished)
                                    return
                                }
                            }
                        }
                        
                    case .error(let error):
                        print("❌ Real-time SSE error: \(error.localizedDescription)")
                        subject.send(completion: .failure(.eventSourceError(error.localizedDescription)))
                        return
                        
                    case .closed:
                        print("📡 Real-time SSE connection closed")
                        if !responseText.isEmpty {
                            let finalUpdate = TranscriptionUpdate(isPartial: false, text: responseText)
                            subject.send(finalUpdate)
                        }
                        subject.send(completion: .finished)
                        return
                    }
                }
                
            } catch {
                print("❌ Real-time transcription setup failed: \(error.localizedDescription)")
                subject.send(completion: .failure(.networkError(error)))
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    // SSE streaming transcription using EventSource
    private func transcribeAudioStreaming(
        audioURL: URL,
        whisperBaseURL: String,
        apiKey: String,
        model: String
    ) -> AnyPublisher<String, TranscriptionError> {
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ Error: Audio file not found at path: \(audioURL.path)")
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
        
        // Build API URL (same endpoint as regular transcription)
        guard let serverURL = APIURLBuilder.buildURL(baseURL: whisperBaseURL, endpoint: "audio/transcriptions") else {
            print("❌ Error: Invalid Whisper API base URL: \(whisperBaseURL)")
            return Fail(error: TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1, userInfo: nil))).eraseToAnyPublisher()
        }
        
        print("🔗 Using transcription endpoint with stream=true: \(serverURL.absoluteString)")
        
        return Future<String, TranscriptionError> { promise in
            Task {
                do {
                    let request = try self.buildStreamingRequest(
                        url: serverURL,
                        audioURL: audioURL,
                        apiKey: apiKey,
                        model: model
                    )
                    
                    // Use EventSource for clean SSE handling
                    let eventSource = EventSource(mode: .dataOnly)
                    let dataTask = await eventSource.dataTask(for: request)
                    
                    var responseText = ""
                    
                    for await event in await dataTask.events() {
                        switch event {
                        case .open:
                            print("✅ SSE streaming connection established successfully")
                            // Cache that this server supports SSE
                            self.setCachedSSESupport(for: whisperBaseURL, supports: true)
                            
                        case .event(let sseEvent):
                            if let eventData = sseEvent.data {
                                print("📨 SSE Event: '\(eventData)'")
                                
                                // Parse the streaming data
                                if let update = self.parseStreamingData(eventData) {
                                    // Accumulate all text instead of replacing
                                    if !update.text.isEmpty {
                                        responseText += (responseText.isEmpty ? "" : " ") + update.text
                                        print("🔄 Accumulated text: \(responseText.count) chars, latest: \(update.text.prefix(50))...")
                                    }
                                    
                                    // Don't close on individual chunks - let connection close naturally
                                    // if !update.isPartial {
                                    //     print("✅ Streaming transcription completed")
                                    //     await dataTask.cancel()
                                    //     promise(.success(responseText))
                                    //     return
                                    // }
                                }
                            }
                            
                        case .error(let error):
                            print("❌ SSE streaming error: \(error.localizedDescription)")
                            
                            // Check if this is a "streaming not supported" error
                            if error.localizedDescription.contains("text/plain") || 
                               error.localizedDescription.contains("application/json") {
                                print("⚠️ Server returned non-SSE content type, falling back")
                                promise(.failure(.streamingNotSupported))
                            } else {
                                promise(.failure(.eventSourceError(error.localizedDescription)))
                            }
                            return
                            
                        case .closed:
                            print("📡 SSE connection closed")
                            if !responseText.isEmpty {
                                promise(.success(responseText))
                            } else {
                                promise(.failure(.streamingNotSupported))
                            }
                            return
                        }
                    }
                    
                } catch {
                    print("❌ Streaming transcription setup failed: \(error.localizedDescription)")
                    promise(.failure(.networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // Regular (non-streaming) transcription method
    private func transcribeAudioRegular(audioURL: URL, whisperBaseURL: String, apiKey: String = "", model: String = "whisper-1", language: String = "ru", responseFormat: String = "srt") -> AnyPublisher<String, TranscriptionError> {
        // Проверяем, существует ли файл
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("Error: Audio file not found at path: \(audioURL.path)")
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
        
        // Формируем полный URL с эндпоинтом
        guard let serverURL = APIURLBuilder.buildURL(baseURL: whisperBaseURL, endpoint: "audio/transcriptions") else {
            print("Error: Invalid Whisper API base URL: \(whisperBaseURL)")
            return Fail(error: TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1, userInfo: nil))).eraseToAnyPublisher()
        }
        
        print("Starting transcription for: \(audioURL.path), using Whisper API at URL: \(serverURL.absoluteString)")
        
        // Создаем multipart request для отправки аудио
        var request = URLRequest(url: serverURL)
        let boundary = UUID().uuidString
        
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Добавляем API Key, если он предоставлен
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Получаем данные аудиофайла
        do {
            let audioData = try Data(contentsOf: audioURL)
            print("Loaded audio data, size: \(ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))")
            
            var body = Data()
            
            // Добавляем параметр model
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
            
            // Добавляем параметр response_format
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(responseFormat)\r\n".data(using: .utf8)!)
            
            // Добавляем параметр language
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
            
            // Добавляем файл
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            // Выводим информацию о запросе для отладки
            print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
            print("Request body size: \(ByteCountFormatter.string(fromByteCount: Int64(body.count), countStyle: .file))")
            
            return URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { data, response -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("Error: Invalid response type")
                        throw TranscriptionError.invalidResponse
                    }
                    
                    print("Response status code: \(httpResponse.statusCode)")
                    print("Response headers: \(httpResponse.allHeaderFields)")
                    
                    if (200..<300).contains(httpResponse.statusCode) {
                        // Проверяем, что данные не пустые
                        guard !data.isEmpty else {
                            print("Error: Empty response data")
                            throw TranscriptionError.invalidResponse
                        }
                        
                        // Логируем размер полученных данных
                        print("Response data size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                        
                        return data
                    } else {
                        if let errorMessage = String(data: data, encoding: .utf8) {
                            print("Error response: \(errorMessage)")
                            throw TranscriptionError.serverError(errorMessage)
                        } else {
                            throw TranscriptionError.serverError("Status code: \(httpResponse.statusCode)")
                        }
                    }
                }
                .tryMap { data -> String in
                    // Пытаемся распарсить ответ
                    guard let responseText = String(data: data, encoding: .utf8) else {
                        print("Error: Could not decode response data as UTF-8 string")
                        throw TranscriptionError.dataParsingError("Could not decode response as UTF-8 string")
                    }
                    
                    // Для формата srt, проверяем его структуру
                    if responseFormat == "srt" {
                        if responseText.contains("-->") && responseText.contains("\n\n") {
                            // Выглядит как правильный SRT формат
                            print("Response appears to be valid SRT format, length: \(responseText.count) characters")
                        } else {
                            print("Warning: Response doesn't appear to be in SRT format: \(responseText.prefix(100))...")
                        }
                    } else {
                        // Для других форматов логируем начало ответа
                        print("Response format: \(responseFormat), preview: \(responseText.prefix(100))...")
                    }
                    
                    // Извлекаем только текст из SRT, если это требуется
                    // В данном случае возвращаем как есть, но можно добавить парсинг SRT
                    return responseText
                }
                .mapError { error -> TranscriptionError in
                    if let transcriptionError = error as? TranscriptionError {
                        return transcriptionError
                    } else {
                        print("Mapped error: \(error.localizedDescription)")
                        return TranscriptionError.networkError(error)
                    }
                }
                .eraseToAnyPublisher()
        } catch {
            print("Error loading audio file: \(error.localizedDescription)")
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
    }
    
    // Вспомогательный метод для парсинга SRT формата и извлечения чистого текста
    func extractTextFromSRT(_ srtContent: String) -> String {
        // Простой парсинг SRT формата - разбиваем на блоки и извлекаем только текст
        let blocks = srtContent.components(separatedBy: "\n\n")
        var extractedText = ""
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            // Пропускаем первые две строки (номер и таймкод), берем остальное как текст
            if lines.count > 2 {
                let textLines = lines.dropFirst(2).joined(separator: " ")
                extractedText += textLines + " "
            }
        }
        
        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper Methods
    
    // Build multipart request with stream=true parameter
    private func buildStreamingRequest(
        url: URL,
        audioURL: URL,
        apiKey: String,
        model: String
    ) throws -> URLRequest {
        let audioData = try Data(contentsOf: audioURL)
        print("📊 Loaded audio data, size: \(ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))")
        
        var request = URLRequest(url: url)
        let boundary = UUID().uuidString
        
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // Add API Key if provided
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        var body = Data()
        
        // Add streaming parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"stream\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // Add response format as text for streaming
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        
        // Add language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("ru\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("📡 Streaming request headers: \(request.allHTTPHeaderFields ?? [:])")
        print("📦 Request body size: \(ByteCountFormatter.string(fromByteCount: Int64(body.count), countStyle: .file))")
        
        return request
    }
    
    // Parse streaming SSE data into TranscriptionUpdate
    private func parseStreamingData(_ data: String) -> TranscriptionUpdate? {
        // Handle OpenAI's data-only streaming format
        if data.hasPrefix("{") {
            // Try to parse as JSON
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Extract text from various possible JSON structures
                if let text = json["text"] as? String {
                    let isPartial = json["partial"] as? Bool ?? true // Default to partial for streaming
                    return TranscriptionUpdate(isPartial: isPartial, text: text)
                }
                
                // Handle OpenAI streaming format
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let text = firstChoice["text"] as? String {
                    let isPartial = json["partial"] as? Bool ?? true
                    return TranscriptionUpdate(isPartial: isPartial, text: text)
                }
            }
        }
        
        // Handle plain text data - all chunks are partial by default in streaming
        if !data.isEmpty && data != "[DONE]" {
            let cleanText = data.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanText.isEmpty {
                // All streaming chunks are partial by default
                // Only mark as final when connection closes or we get explicit signal
                return TranscriptionUpdate(isPartial: true, text: cleanText)
            }
        }
        
        return nil
    }
    
    // Thread-safe cache methods
    private func getCachedSSESupport(for server: String) -> Bool? {
        return cacheQueue.sync {
            return serverSupportsSSE[server]
        }
    }
    
    private func setCachedSSESupport(for server: String, supports: Bool) {
        cacheQueue.async(flags: .barrier) {
            self.serverSupportsSSE[server] = supports
            print("📋 Cached SSE support for \(server): \(supports)")
        }
    }
}

// Extension для Data для удобства работы с multipart/form-data
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 