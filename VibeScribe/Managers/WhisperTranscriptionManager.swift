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
enum TranscriptionError: LocalizedError {
    case invalidAudioFile
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case unknownError
    case dataParsingError(String)
    case streamingNotSupported
    case streamingError(String)
    case permissionDenied
    case engineUnavailable
    case processingFailed(String)
    case featureUnavailable
}

extension TranscriptionError {
    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return AppLanguage.localized("audio.file.is.invalid.or.corrupted")
        case .networkError(let error):
            return String(format: AppLanguage.localized("network.error.arg1"), error.localizedDescription)
        case .invalidResponse:
            return AppLanguage.localized("invalid.response.from.server")
        case .serverError(let message):
            return String(format: AppLanguage.localized("server.error.arg1"), message)
        case .unknownError:
            return AppLanguage.localized("an.unknown.error.occurred")
        case .dataParsingError(let message):
            return String(format: AppLanguage.localized("data.parsing.error.arg1"), message)
        case .streamingNotSupported:
            return AppLanguage.localized("server.doesnt.support.sse.streaming")
        case .streamingError(let message):
            return String(format: AppLanguage.localized("streaming.error.arg1"), message)
        case .permissionDenied:
            return AppLanguage.localized("permission.was.denied")
        case .engineUnavailable:
            return AppLanguage.localized("transcription.engine.is.unavailable")
        case .processingFailed(let message):
            return String(format: AppLanguage.localized("processing.failed.arg1"), message)
        case .featureUnavailable:
            return AppLanguage.localized("transcription.feature.unavailable.on.this.platform")
        }
    }
    
    var description: String { localizedDescription }
}

// Structure for real-time transcription updates
struct TranscriptionUpdate: Sendable {
    let isPartial: Bool
    let text: String
    let timestamp: Date
    
    init(isPartial: Bool, text: String) {
        self.isPartial = isPartial
        self.text = text
        self.timestamp = Date()
    }
}

// MARK: - WhisperTranscriptionManager

final class WhisperTranscriptionManager: NSObject {
    static let shared = WhisperTranscriptionManager()

    // MARK: Caches and session
    private var urlSession: URLSession!

    // Server SSE capability cache
    private var serverSSECache: [String: Bool] = [:]
    private let serverCacheQueue = DispatchQueue(label: "vibescribe.whisper.sse.cache", attributes: .concurrent)

    // Streaming task contexts keyed by task identifier
    private struct StreamingContext {
        var subject: PassthroughSubject<TranscriptionUpdate, TranscriptionError>?
        var completion: ((Result<String, TranscriptionError>) -> Void)?
        var buffer: String = ""
        var accumulated: String = ""
        var retry: RetryInfo?
    }
    private struct RetryInfo {
        let audioURL: URL
        let serverURL: URL
        let apiKey: String
        let model: String
        let maxRetries: Int
        var currentRetry: Int
    }
    private var contexts: [Int: StreamingContext] = [:]
    private let contextsQueue = DispatchQueue(label: "vibescribe.whisper.contexts")

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: Public API
    func transcribeAudio(
        audioURL: URL,
        settings: AppSettings,
        useStreaming: Bool = true
    ) -> AnyPublisher<String, TranscriptionError> {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Logger.error("Audio file not found at path: \(audioURL.path)", category: .transcription)
            return Fail(error: .invalidAudioFile).eraseToAnyPublisher()
        }

        if !useStreaming {
            return transcribeRegular(audioURL: audioURL,
                                     baseURL: settings.resolvedWhisperBaseURL,
                                     apiKey: settings.resolvedWhisperAPIKey,
                                     model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel,
                                     responseFormat: "srt")
        }

        let serverKey = settings.resolvedWhisperBaseURL
        if let supportsSSE = getSSESupport(for: serverKey), supportsSSE == false {
            Logger.info("Server \(serverKey) known to not support SSE; using regular mode", category: .transcription)
            return transcribeRegular(audioURL: audioURL,
                                     baseURL: settings.resolvedWhisperBaseURL,
                                     apiKey: settings.resolvedWhisperAPIKey,
                                     model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel,
                                     responseFormat: "srt")
        }

        Logger.info("Attempting SSE streaming for \(audioURL.lastPathComponent)", category: .transcription)
        return transcribeStreaming(audioURL: audioURL,
                                   baseURL: settings.resolvedWhisperBaseURL,
                                   apiKey: settings.resolvedWhisperAPIKey,
                                   model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel)
        .catch { [weak self] error -> AnyPublisher<String, TranscriptionError> in
            guard let self else { return Fail(error: error).eraseToAnyPublisher() }
            if case .streamingNotSupported = error {
                self.setSSESupport(false, for: serverKey)
                Logger.warning("SSE not supported; falling back to regular", category: .transcription)
                return self.transcribeRegular(audioURL: audioURL,
                                              baseURL: settings.resolvedWhisperBaseURL,
                                              apiKey: settings.resolvedWhisperAPIKey,
                                              model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel,
                                              responseFormat: "srt")
            }
            return Fail(error: error).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func transcribeAudioRealTime(audioURL: URL, settings: AppSettings) -> AnyPublisher<TranscriptionUpdate, TranscriptionError> {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Logger.error("Audio file not found at path: \(audioURL.path)", category: .transcription)
            return Fail(error: .invalidAudioFile).eraseToAnyPublisher()
        }

        guard let serverURL = APIURLBuilder.buildURL(baseURL: settings.resolvedWhisperBaseURL, endpoint: "audio/transcriptions") else {
            Logger.error("Invalid Whisper API base URL: \(settings.resolvedWhisperBaseURL)", category: .transcription)
            return Fail(error: .networkError(NSError(domain: "InvalidURL", code: -1))).eraseToAnyPublisher()
        }

        let subject = PassthroughSubject<TranscriptionUpdate, TranscriptionError>()

        Task { [weak self] in
            guard let self else { return }
            await self.startStreaming(
                audioURL: audioURL,
                serverURL: serverURL,
                apiKey: settings.resolvedWhisperAPIKey,
                model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel,
                subject: subject,
                completion: nil,
                retry: RetryInfo(audioURL: audioURL, serverURL: serverURL, apiKey: settings.resolvedWhisperAPIKey, model: settings.whisperModel.isEmpty ? "whisper-1" : settings.whisperModel, maxRetries: 3, currentRetry: 0)
            )
        }

        return subject.eraseToAnyPublisher()
    }

    // MARK: Regular transcription
    private func transcribeRegular(
        audioURL: URL,
        baseURL: String,
        apiKey: String,
        model: String,
        responseFormat: String
    ) -> AnyPublisher<String, TranscriptionError> {
        guard let serverURL = APIURLBuilder.buildURL(baseURL: baseURL, endpoint: "audio/transcriptions") else {
            Logger.error("Invalid Whisper API base URL: \(baseURL)", category: .transcription)
            return Fail(error: .networkError(NSError(domain: "InvalidURL", code: -1))).eraseToAnyPublisher()
        }

        do {
            var request = try buildMultipartRequest(
                url: serverURL,
                apiKey: apiKey,
                headers: [:],
                fields: ["model": model, "response_format": responseFormat],
                fileParam: "file",
                fileURL: audioURL,
                fileMime: "audio/m4a"
            )
            request.timeoutInterval = 0

            return urlSession.dataTaskPublisher(for: request)
                .tryMap { output -> Data in
                    guard let http = output.response as? HTTPURLResponse else {
                        throw TranscriptionError.invalidResponse
                    }
                    guard 200..<300 ~= http.statusCode else {
                        let message = String(data: output.data, encoding: .utf8) ?? "Status code: \(http.statusCode)"
                        throw TranscriptionError.serverError(message)
                    }
                    return output.data
                }
                .tryMap { data -> String in
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw TranscriptionError.dataParsingError("Could not decode UTF-8 text")
                    }
                    Logger.info("Received transcription (\(text.count) chars)", category: .transcription)
                    return text
                }
                .mapError { error in
                    (error as? TranscriptionError) ?? .networkError(error)
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: .invalidAudioFile).eraseToAnyPublisher()
        }
    }

    // MARK: Streaming transcription
    private func transcribeStreaming(
        audioURL: URL,
        baseURL: String,
        apiKey: String,
        model: String
    ) -> AnyPublisher<String, TranscriptionError> {
        guard let serverURL = APIURLBuilder.buildURL(baseURL: baseURL, endpoint: "audio/transcriptions") else {
            Logger.error("Invalid Whisper API base URL: \(baseURL)", category: .transcription)
            return Fail(error: .networkError(NSError(domain: "InvalidURL", code: -1))).eraseToAnyPublisher()
        }

        return Future<String, TranscriptionError> { [weak self] promise in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    var request = try self.buildMultipartRequest(
                        url: serverURL,
                        apiKey: apiKey,
                        headers: [
                            "Accept": "text/event-stream",
                            "Cache-Control": "no-cache",
                            "Connection": "keep-alive"
                        ],
                        fields: [
                            "stream": "true",
                            "model": model,
                            "response_format": "text"
                        ],
                        fileParam: "file",
                        fileURL: audioURL,
                        fileMime: "audio/m4a"
                    )
                    request.timeoutInterval = 0

                    let task = self.urlSession.dataTask(with: request)
                    let id = task.taskIdentifier
                    self.contextsQueue.sync {
                        self.contexts[id] = StreamingContext(subject: nil, completion: { result in
                            promise(result)
                        }, buffer: "", accumulated: "", retry: nil)
                    }
                    task.resume()
                    Logger.info("SSE streaming started (taskId=\(id))", category: .transcription)
                } catch {
                    promise(.failure(.networkError(error)))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: Multipart builder
    private func buildMultipartRequest(
        url: URL,
        apiKey: String,
        headers: [String: String],
        fields: [String: String],
        fileParam: String,
        fileURL: URL,
        fileMime: String
    ) throws -> URLRequest {
        let audioData = try Data(contentsOf: fileURL)
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if !apiKey.isEmpty {
            let clean = SecurityUtils.sanitizeAPIKey(apiKey)
            request.setValue("Bearer \(clean)", forHTTPHeaderField: "Authorization")
            Logger.debug("Using Whisper API key \(SecurityUtils.maskAPIKey(clean))", category: .security)
        }

        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileParam)\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(fileMime)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    // MARK: SRT text extraction
    func extractTextFromSRT(_ srtContent: String) -> String {
        let blocks = srtContent.components(separatedBy: "\n\n")
        var extracted = ""
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            if lines.count > 2 {
                let text = lines.dropFirst(2).joined(separator: " ")
                extracted += text + " "
            }
        }
        return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: SSE helpers
    private func parseEvent(_ raw: String) -> TranscriptionUpdate? {
        if raw == "[DONE]" { return nil }
        if raw.hasPrefix("{") {
            if let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let text = json["text"] as? String {
                    let isPartial = json["partial"] as? Bool ?? true
                    return TranscriptionUpdate(isPartial: isPartial, text: text)
                }
                if let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let text = first["text"] as? String {
                    let isPartial = json["partial"] as? Bool ?? true
                    return TranscriptionUpdate(isPartial: isPartial, text: text)
                }
            }
        } else {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return TranscriptionUpdate(isPartial: true, text: clean) }
        }
        return nil
    }

    private func getSSESupport(for server: String) -> Bool? {
        serverCacheQueue.sync { serverSSECache[server] }
    }
    private func setSSESupport(_ supports: Bool, for server: String) {
        serverCacheQueue.async(flags: .barrier) { self.serverSSECache[server] = supports }
    }

    private func startStreaming(
        audioURL: URL,
        serverURL: URL,
        apiKey: String,
        model: String,
        subject: PassthroughSubject<TranscriptionUpdate, TranscriptionError>?,
        completion: ((Result<String, TranscriptionError>) -> Void)?,
        retry: RetryInfo?
    ) async {
        do {
            var request = try buildMultipartRequest(
                url: serverURL,
                apiKey: apiKey,
                headers: [
                    "Accept": "text/event-stream",
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive"
                ],
                fields: [
                    "stream": "true",
                    "model": model,
                    "response_format": "text"
                ],
                fileParam: "file",
                fileURL: audioURL,
                fileMime: "audio/m4a"
            )
            request.timeoutInterval = 0

            let task = urlSession.dataTask(with: request)
            let id = task.taskIdentifier
            contextsQueue.sync {
                contexts[id] = StreamingContext(subject: subject, completion: completion, buffer: "", accumulated: "", retry: retry)
            }
            task.resume()
            Logger.info("SSE streaming started (taskId=\(id))", category: .transcription)
        } catch {
            if let subject { subject.send(completion: .failure(.networkError(error))) }
            if let completion { completion(.failure(.networkError(error))) }
        }
    }
}

// MARK: - URLSessionDataDelegate
extension WhisperTranscriptionManager: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        contextsQueue.sync {
            var ctx = contexts[id] ?? StreamingContext()
            ctx.buffer += chunk

            // Split events by blank line
            let blocks = ctx.buffer.components(separatedBy: "\n\n")
            // Keep last as remainder
            ctx.buffer = blocks.last ?? ""
            let completeBlocks = blocks.dropLast()

            for block in completeBlocks {
                for line in block.components(separatedBy: "\n") {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let update = parseEvent(payload) {
                        if let subject = ctx.subject { subject.send(update) }
                        if !update.text.isEmpty {
                            ctx.accumulated += (ctx.accumulated.isEmpty ? "" : " ") + update.text
                        }
                    }
                }
            }

            contexts[id] = ctx
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier

        contextsQueue.sync {
            guard var ctx = contexts[id] else { return }

            if let error = error {
                Logger.warning("SSE task \(id) error: \(error.localizedDescription)", category: .transcription)

                if var retry = ctx.retry, retry.currentRetry < retry.maxRetries {
                    retry.currentRetry += 1
                    contexts[id] = nil // Cleanup this attempt
                    Task { [retry, ctx] in
                        let delay = Double(retry.currentRetry) * 2.0
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        await self.startStreaming(audioURL: retry.audioURL,
                                                  serverURL: retry.serverURL,
                                                  apiKey: retry.apiKey,
                                                  model: retry.model,
                                                  subject: ctx.subject,
                                                  completion: ctx.completion,
                                                  retry: retry)
                    }
                    return
                }

                if let subject = ctx.subject {
                    subject.send(completion: .failure(.streamingError(error.localizedDescription)))
                }
                if let completion = ctx.completion {
                    completion(.failure(.streamingError(error.localizedDescription)))
                }
            } else {
                // Flush remaining buffer lines
                for line in ctx.buffer.components(separatedBy: "\n") where line.hasPrefix("data:") {
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let update = parseEvent(payload) {
                        if let subject = ctx.subject { subject.send(update) }
                        if !update.text.isEmpty {
                            ctx.accumulated += (ctx.accumulated.isEmpty ? "" : " ") + update.text
                        }
                    }
                }

                if let subject = ctx.subject {
                    if !ctx.accumulated.isEmpty {
                        subject.send(TranscriptionUpdate(isPartial: false, text: ctx.accumulated))
                    }
                    subject.send(completion: .finished)
                }
                if let completion = ctx.completion {
                    if !ctx.accumulated.isEmpty {
                        completion(.success(ctx.accumulated))
                    } else {
                        completion(.failure(.streamingNotSupported))
                    }
                }
            }

            contexts[id] = nil
        }
    }
}
