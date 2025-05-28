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
    case dataParsingError(String)
    
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
        case .dataParsingError(let message):
            return "Data parsing error: \(message)"
        }
    }
}

// Класс для работы с Whisper API
class WhisperTranscriptionManager {
    static let shared = WhisperTranscriptionManager()
    
    private init() {}
    
    // Функция для транскрипции аудиофайла
    func transcribeAudio(audioURL: URL, whisperBaseURL: String, apiKey: String = "", model: String = "whisper-1", language: String = "ru", responseFormat: String = "srt") -> AnyPublisher<String, TranscriptionError> {
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
}

// Extension для Data для удобства работы с multipart/form-data
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 