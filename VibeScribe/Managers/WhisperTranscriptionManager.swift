//
//  WhisperTranscriptionManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import Combine
import AVFoundation

// Error types for transcription process
enum TranscriptionError: Error {
    case invalidAudioFile
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case unknownError
    case dataParsingError(String)
    case streamingNotSupported
    case streamingError(String)
    
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
        case .streamingError(let message):
            return "Streaming error: \(message)"
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

// Manager class for working with Whisper API with custom SSE support
class WhisperTranscriptionManager: NSObject {
    static let shared = WhisperTranscriptionManager()
    
    // Cache for server SSE support to avoid repeated checks
    private var serverSupportsSSE: [String: Bool] = [:]
    private let cacheQueue = DispatchQueue(label: "whisper.cache.queue", attributes: .concurrent)
    
    // Custom URLSession with no timeout for long transcription tasks
    private var urlSession: URLSession!
    
    // SSE streaming support
    private var streamingCompletions: [Int: (Result<String, TranscriptionError>) -> Void] = [:]
    private var streamingSubjects: [Int: PassthroughSubject<TranscriptionUpdate, TranscriptionError>] = [:]
    private var streamingBuffers: [Int: String] = [:]
    private var streamingTexts: [Int: String] = [:]
    
    // Retry support  
    private var streamingRetryInfo: [Int: StreamingRetryInfo] = [:]
    
    // Struct to hold retry information
    private struct StreamingRetryInfo {
        let audioURL: URL
        let serverURL: URL  
        let apiKey: String
        let model: String
        let subject: PassthroughSubject<TranscriptionUpdate, TranscriptionError>
        let maxRetries: Int
        let currentRetry: Int
    }
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0  // No timeout
        config.timeoutIntervalForResource = 0  // No timeout
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
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
    
    // Real-time streaming method with intermediate updates using custom SSE
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
            await self.startStreamingWithRetry(
                audioURL: audioURL,
                serverURL: serverURL,
                apiKey: settings.whisperAPIKey,
                model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel,
                subject: subject,
                maxRetries: 3
            )
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    // SSE streaming transcription using custom SSE implementation
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
                    
                    // Use custom SSE implementation with URLSessionDataDelegate
                    let dataTask = self.urlSession.dataTask(with: request)
                    let taskId = dataTask.taskIdentifier
                    
                    // Store the completion handler for this task
                    self.streamingCompletions[taskId] = { result in
                        promise(result)
                    }
                    
                    // Start the task
                    dataTask.resume()
                    print("✅ SSE streaming started, task ID: \(taskId)")
                    
                } catch {
                    print("❌ Streaming transcription setup failed: \(error.localizedDescription)")
                    promise(.failure(.networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    

    
    // Regular (non-streaming) transcription method
    private func transcribeAudioRegular(audioURL: URL, whisperBaseURL: String, apiKey: String = "", model: String = "whisper-1", responseFormat: String = "srt") -> AnyPublisher<String, TranscriptionError> {
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("Error: Audio file not found at path: \(audioURL.path)")
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
        
        // Build the full URL with endpoint
        guard let serverURL = APIURLBuilder.buildURL(baseURL: whisperBaseURL, endpoint: "audio/transcriptions") else {
            print("Error: Invalid Whisper API base URL: \(whisperBaseURL)")
            return Fail(error: TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1, userInfo: nil))).eraseToAnyPublisher()
        }
        
        print("Starting transcription for: \(audioURL.path), using Whisper API at URL: \(serverURL.absoluteString)")
        
        // Create multipart request for sending audio
        var request = URLRequest(url: serverURL)
        let boundary = UUID().uuidString
        
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Add API Key if provided
        if !apiKey.isEmpty {
            // Sanitize API key to prevent header injection
            let cleanAPIKey = SecurityUtils.sanitizeAPIKey(apiKey)
            request.setValue("Bearer \(cleanAPIKey)", forHTTPHeaderField: "Authorization")
            print("Request will use API key: \(SecurityUtils.maskAPIKey(cleanAPIKey))")
        } else {
            print("No API key provided for request")
        }
        
        // Get audio file data
        do {
            let audioData = try Data(contentsOf: audioURL)
            print("Loaded audio data, size: \(ByteCountFormatter.string(fromByteCount: Int64(audioData.count), countStyle: .file))")
            
            var body = Data()
            
            // Add model parameter
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
            
            // Add response_format parameter
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(responseFormat)\r\n".data(using: .utf8)!)
            
            // Language parameter removed - let Whisper auto-detect
            
            // Add file
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            // Output request information for debugging
            print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
            print("Request body size: \(ByteCountFormatter.string(fromByteCount: Int64(body.count), countStyle: .file))")
            
            return urlSession.dataTaskPublisher(for: request)
                .tryMap { data, response -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("Error: Invalid response type")
                        throw TranscriptionError.invalidResponse
                    }
                    
                    print("Response status code: \(httpResponse.statusCode)")
                    print("Response headers: \(httpResponse.allHeaderFields)")
                    
                    if (200..<300).contains(httpResponse.statusCode) {
                        // Check that data is not empty
                        guard !data.isEmpty else {
                            print("Error: Empty response data")
                            throw TranscriptionError.invalidResponse
                        }
                        
                        // Log the size of received data
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
                    // Try to parse the response
                    guard let responseText = String(data: data, encoding: .utf8) else {
                        print("Error: Could not decode response data as UTF-8 string")
                        throw TranscriptionError.dataParsingError("Could not decode response as UTF-8 string")
                    }
                    
                    // For SRT format, check its structure
                    if responseFormat == "srt" {
                        if responseText.contains("-->") && responseText.contains("\n\n") {
                            // Looks like proper SRT format
                            print("Response appears to be valid SRT format, length: \(responseText.count) characters")
                        } else {
                            print("Warning: Response doesn't appear to be in SRT format: \(responseText.prefix(100))...")
                        }
                    } else {
                        // For other formats, log the beginning of the response
                        print("Response format: \(responseFormat), preview: \(responseText.prefix(100))...")
                    }
                    
                    // Extract only text from SRT if required
                    // In this case, return as is, but SRT parsing can be added
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
    
    // Helper method for parsing SRT format and extracting clean text
    func extractTextFromSRT(_ srtContent: String) -> String {
        // Simple SRT format parsing - split into blocks and extract only text
        let blocks = srtContent.components(separatedBy: "\n\n")
        var extractedText = ""
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            // Skip the first two lines (number and timecode), take the rest as text
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
            // Sanitize API key to prevent header injection
            let cleanAPIKey = SecurityUtils.sanitizeAPIKey(apiKey)
            request.setValue("Bearer \(cleanAPIKey)", forHTTPHeaderField: "Authorization")
            print("Request will use API key: \(SecurityUtils.maskAPIKey(cleanAPIKey))")
        } else {
            print("No API key provided for request")
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
        
        // Language parameter removed - let Whisper auto-detect
        
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
    
    // MARK: - Retry Logic for Streaming
    
    private func startStreamingWithRetry(
        audioURL: URL,
        serverURL: URL,
        apiKey: String,
        model: String,
        subject: PassthroughSubject<TranscriptionUpdate, TranscriptionError>,
        maxRetries: Int,
        currentRetry: Int = 0
    ) async {
        do {
            let request = try self.buildStreamingRequest(
                url: serverURL,
                audioURL: audioURL,
                apiKey: apiKey,
                model: model
            )
            
            // Use custom SSE implementation with URLSessionDataDelegate
            let dataTask = self.urlSession.dataTask(with: request)
            let taskId = dataTask.taskIdentifier
            
            // Store the subject for this task
            self.streamingSubjects[taskId] = subject
            
            // Store retry info for this task
            self.streamingRetryInfo[taskId] = StreamingRetryInfo(
                audioURL: audioURL,
                serverURL: serverURL,
                apiKey: apiKey,
                model: model,
                subject: subject,
                maxRetries: maxRetries,
                currentRetry: currentRetry
            )
            
            // Start the task
            dataTask.resume()
            print("✅ Real-time SSE streaming started, task ID: \(taskId), retry: \(currentRetry)/\(maxRetries)")
            
        } catch {
            print("❌ Real-time transcription setup failed: \(error.localizedDescription)")
            if currentRetry < maxRetries {
                let delay = Double(currentRetry + 1) * 2.0 // 2, 4, 6 seconds
                print("🔄 Retrying in \(delay) seconds... (\(currentRetry + 1)/\(maxRetries))")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await startStreamingWithRetry(
                    audioURL: audioURL,
                    serverURL: serverURL,
                    apiKey: apiKey,
                    model: model,
                    subject: subject,
                    maxRetries: maxRetries,
                    currentRetry: currentRetry + 1
                )
            } else {
                print("❌ All retries exhausted, failing transcription")
                subject.send(completion: .failure(.networkError(error)))
            }
        }
    }
}

// Extension for Data for convenient work with multipart/form-data
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - URLSessionDataDelegate
extension WhisperTranscriptionManager: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskId = dataTask.taskIdentifier as Int? else { return }
        
        // Convert data to string
        guard let sseData = String(data: data, encoding: .utf8) else { return }
        
        // Append to buffer
        if streamingBuffers[taskId] == nil {
            streamingBuffers[taskId] = ""
        }
        streamingBuffers[taskId]! += sseData
        
        // Process SSE events
        if let events = parseSSEBuffer(streamingBuffers[taskId]!) {
            // Update buffer with remaining data
            streamingBuffers[taskId] = events.remainder
            
            // Process each complete event
            for eventData in events.events {
                print("📨 SSE Event: '\(eventData)'")
                
                if let update = parseStreamingData(eventData) {
                    // Send update to subject for real-time display
                    if let subject = streamingSubjects[taskId] {
                        subject.send(update)
                    }
                    
                    // Accumulate text for completion handlers
                    if streamingTexts[taskId] == nil {
                        streamingTexts[taskId] = ""
                    }
                    if !update.text.isEmpty {
                        streamingTexts[taskId]! += (streamingTexts[taskId]!.isEmpty ? "" : " ") + update.text
                        print("🔄 Accumulated: \(streamingTexts[taskId]!.count) chars")
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskId = task.taskIdentifier as Int? else { return }
        
        if let error = error {
            print("❌ SSE task \(taskId) completed with error: \(error.localizedDescription)")
            
            // Check if we should retry this connection
            if let retryInfo = streamingRetryInfo[taskId], 
               retryInfo.currentRetry < retryInfo.maxRetries {
                
                let nextRetry = retryInfo.currentRetry + 1
                let delay = Double(nextRetry) * 2.0 // 2, 4, 6 seconds
                print("🔄 Connection lost, retrying in \(delay) seconds... (\(nextRetry)/\(retryInfo.maxRetries))")
                
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await startStreamingWithRetry(
                        audioURL: retryInfo.audioURL,
                        serverURL: retryInfo.serverURL,
                        apiKey: retryInfo.apiKey,
                        model: retryInfo.model,
                        subject: retryInfo.subject,
                        maxRetries: retryInfo.maxRetries,
                        currentRetry: nextRetry
                    )
                }
                
                // Only cleanup buffers for this attempt, keep subject/completion for retry
                streamingBuffers.removeValue(forKey: taskId)
                streamingTexts.removeValue(forKey: taskId)
                streamingRetryInfo.removeValue(forKey: taskId)
                return
            }
            
            // No more retries, notify about failure
            if let subject = streamingSubjects[taskId] {
                subject.send(completion: .failure(.streamingError(error.localizedDescription)))
            }
            
            if let completion = streamingCompletions[taskId] {
                completion(.failure(.streamingError(error.localizedDescription)))
            }
        } else {
            print("📡 SSE task \(taskId) completed successfully")
            
            // Process any remaining buffer content (last chunk might be here!)
            if let buffer = streamingBuffers[taskId], !buffer.isEmpty {
                print("🔍 Processing final buffer content: '\(buffer)'")
                
                // Parse any remaining SSE data in buffer
                let lines = buffer.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("data: ") {
                        let eventData = String(line.dropFirst(6)) // Remove "data: " prefix
                        print("📨 Final SSE Event: '\(eventData)'")
                        
                        if let update = parseStreamingData(eventData) {
                            // Send update to subject for real-time display
                            if let subject = streamingSubjects[taskId] {
                                subject.send(update)
                            }
                            
                            // Accumulate text for completion handlers
                            if streamingTexts[taskId] == nil {
                                streamingTexts[taskId] = ""
                            }
                            if !update.text.isEmpty {
                                streamingTexts[taskId]! += (streamingTexts[taskId]!.isEmpty ? "" : " ") + update.text
                                print("🔄 Final accumulated: \(streamingTexts[taskId]!.count) chars")
                            }
                        }
                    }
                }
            }
            
            // Send final accumulated text
            let finalText = streamingTexts[taskId] ?? ""
            
            if let subject = streamingSubjects[taskId] {
                if !finalText.isEmpty {
                    let finalUpdate = TranscriptionUpdate(isPartial: false, text: finalText)
                    subject.send(finalUpdate)
                }
                subject.send(completion: .finished)
            }
            
            if let completion = streamingCompletions[taskId] {
                if !finalText.isEmpty {
                    completion(.success(finalText))
                } else {
                    completion(.failure(.streamingNotSupported))
                }
            }
        }
        
        // Clean up
        streamingCompletions.removeValue(forKey: taskId)
        streamingSubjects.removeValue(forKey: taskId)
        streamingBuffers.removeValue(forKey: taskId)
        streamingTexts.removeValue(forKey: taskId)
        streamingRetryInfo.removeValue(forKey: taskId)
    }
    
    // Parse SSE buffer and extract complete events
    private func parseSSEBuffer(_ buffer: String) -> (events: [String], remainder: String)? {
        var events: [String] = []
        var remainder = buffer
        
        // Split by double newlines (SSE event separator)
        let eventBlocks = buffer.components(separatedBy: "\n\n")
        
        // Process all complete events (all but the last block)
        for i in 0..<eventBlocks.count - 1 {
            let block = eventBlocks[i]
            
            // Extract data from SSE block
            let lines = block.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("data: ") {
                    let eventData = String(line.dropFirst(6)) // Remove "data: " prefix
                    events.append(eventData)
                }
            }
        }
        
        // Keep the last block as remainder (might be incomplete)
        if let lastBlock = eventBlocks.last {
            remainder = lastBlock
        }
        
        return events.isEmpty ? nil : (events: events, remainder: remainder)
    }
} 