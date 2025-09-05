//
//  ModelService.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 14.04.2025.
//

import Foundation
import Combine

// Service for fetching models from OpenAI-compatible APIs
class ModelService: ObservableObject {
    static let shared = ModelService()
    
    @Published var whisperModels: [String] = []
    @Published var openAIModels: [String] = []
    @Published var isLoadingWhisperModels = false
    @Published var isLoadingOpenAIModels = false
    @Published var whisperModelsError: String? = nil
    @Published var openAIModelsError: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Public Methods
    
    func loadWhisperModels(baseURL: String, apiKey: String) {
        loadModels(
            baseURL: baseURL,
            apiKey: apiKey,
            isLoading: \.isLoadingWhisperModels,
            models: \.whisperModels,
            errorKeyPath: \.whisperModelsError
        )
    }
    
    func loadOpenAIModels(baseURL: String, apiKey: String) {
        loadModels(
            baseURL: baseURL,
            apiKey: apiKey,
            isLoading: \.isLoadingOpenAIModels,
            models: \.openAIModels,
            errorKeyPath: \.openAIModelsError
        )
    }
    
    // MARK: - Private Methods
    
    private func loadModels(
        baseURL: String,
        apiKey: String,
        isLoading: ReferenceWritableKeyPath<ModelService, Bool>,
        models: ReferenceWritableKeyPath<ModelService, [String]>,
        errorKeyPath: ReferenceWritableKeyPath<ModelService, String?>
    ) {
        guard !baseURL.isEmpty else {
            self[keyPath: errorKeyPath] = "Base URL is required"
            return
        }
        
        guard APIURLBuilder.isValidBaseURL(baseURL) else {
            self[keyPath: errorKeyPath] = "Invalid base URL format"
            return
        }
        
        self[keyPath: isLoading] = true
        self[keyPath: errorKeyPath] = nil
        
        fetchModels(baseURL: baseURL, apiKey: apiKey)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?[keyPath: isLoading] = false
                    if case .failure(let error) = completion {
                        self?[keyPath: errorKeyPath] = error.localizedDescription
                        self?[keyPath: models] = []
                    }
                },
                receiveValue: { [weak self] modelList in
                    self?[keyPath: models] = modelList
                    self?[keyPath: errorKeyPath] = nil
                }
            )
            .store(in: &cancellables)
    }
    
    private func fetchModels(baseURL: String, apiKey: String) -> AnyPublisher<[String], Error> {
        return Future<[String], Error> { promise in
            guard let url = APIURLBuilder.buildURL(baseURL: baseURL, endpoint: "models") else {
                promise(.failure(ModelServiceError.invalidURL))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("VibeScribe/1.0", forHTTPHeaderField: "User-Agent")
            
            if !apiKey.isEmpty {
                // Sanitize API key to prevent header injection
                let cleanAPIKey = SecurityUtils.sanitizeAPIKey(apiKey)
                request.setValue("Bearer \(cleanAPIKey)", forHTTPHeaderField: "Authorization")
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    promise(.failure(ModelServiceError.invalidResponse))
                    return
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    promise(.failure(ModelServiceError.httpError(httpResponse.statusCode)))
                    return
                }
                
                guard let data = data else {
                    promise(.failure(ModelServiceError.noData))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let modelsArray = json["data"] as? [[String: Any]] {
                        let modelIds = modelsArray.compactMap { $0["id"] as? String }
                        promise(.success(modelIds))
                    } else {
                        promise(.failure(ModelServiceError.invalidResponseFormat))
                    }
                } catch {
                    promise(.failure(error))
                }
            }.resume()
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Error Types

enum ModelServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noData
    case invalidResponseFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noData:
            return "No data received from server"
        case .invalidResponseFormat:
            return "Unexpected response format"
        }
    }
} 