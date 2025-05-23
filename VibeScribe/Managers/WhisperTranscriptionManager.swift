//
//  WhisperTranscriptionManager.swift
//  VibeScribe
//
//  Created by System on 15.04.2025.
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
            return "Unknown error occurred"
        }
    }
}

// Класс для работы с Whisper API
class WhisperTranscriptionManager {
    static let shared = WhisperTranscriptionManager()
    
    private init() {}
    
    // Функция для транскрипции аудиофайла
    func transcribeAudio(audioURL: URL, whisperURL: String, apiKey: String = "", model: String = "whisper-1", language: String = "ru", responseFormat: String = "srt") -> AnyPublisher<String, TranscriptionError> {
        // Проверяем, существует ли файл
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
        }
        
        // Формируем полный URL с эндпоинтом /v1/audio/transcriptions
        guard var serverURL = URL(string: whisperURL) else {
            return Fail(error: TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1, userInfo: nil))).eraseToAnyPublisher()
        }
        
        // Если URL уже не содержит эндпоинт, добавляем его
        if !whisperURL.contains("/v1/audio/transcriptions") {
            serverURL = serverURL.appendingPathComponent("v1/audio/transcriptions")
        }
        
        print("Sending transcription request to: \(serverURL.absoluteString)")
        
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
            
            // Выводим запрос для отладки
            print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
            
            return URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { data, response -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranscriptionError.invalidResponse
                    }
                    
                    print("Response status code: \(httpResponse.statusCode)")
                    
                    if (200..<300).contains(httpResponse.statusCode) {
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
                    if let responseText = String(data: data, encoding: .utf8) {
                        return responseText
                    } else {
                        throw TranscriptionError.invalidResponse
                    }
                }
                .mapError { error -> TranscriptionError in
                    if let transcriptionError = error as? TranscriptionError {
                        return transcriptionError
                    } else {
                        return TranscriptionError.networkError(error)
                    }
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: TranscriptionError.invalidAudioFile).eraseToAnyPublisher()
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