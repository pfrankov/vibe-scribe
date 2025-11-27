//
//  AppSettings.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 14.04.2025.
//

import Foundation
import SwiftData

// MARK: - Whisper Provider Configuration

enum WhisperProvider: String, CaseIterable, Identifiable, Codable {
    case speechAnalyzer
    case whisperServer
    case compatibleAPI
    
    var id: String { rawValue }
    
    static var allCases: [WhisperProvider] {
        if #available(macOS 26, *) {
            return [.speechAnalyzer, .whisperServer, .compatibleAPI]
        } else {
            return [.whisperServer, .compatibleAPI]
        }
    }
    
    var displayName: String {
        switch self {
        case .speechAnalyzer:
            return AppLanguage.localized("native")
        case .whisperServer:
            return AppLanguage.localized("whisperserver")
        case .compatibleAPI:
            return AppLanguage.localized("whisper.compatible.api")
        }
    }
    
    var defaultBaseURL: String {
        switch self {
        case .speechAnalyzer:
            return ""
        case .whisperServer:
            return "http://localhost:12017/v1/"
        case .compatibleAPI:
            return "https://api.openai.com/v1/"
        }
    }
    
    var defaultAPIKey: String {
        switch self {
        case .speechAnalyzer:
            return ""
        case .whisperServer:
            return ""
        case .compatibleAPI:
            return ""
        }
    }
    
    var allowsCustomCredentials: Bool {
        switch self {
        case .speechAnalyzer:
            return false
        case .whisperServer:
            return false
        case .compatibleAPI:
            return true
        }
    }
}

extension WhisperProvider {
    func resolvedBaseURL(using storedBaseURL: String) -> String {
        switch self {
        case .whisperServer:
            return WhisperProvider.whisperServer.defaultBaseURL
        case .compatibleAPI, .speechAnalyzer:
            return storedBaseURL
        }
    }

    func resolvedAPIKey(using storedAPIKey: String) -> String {
        switch self {
        case .whisperServer:
            return WhisperProvider.whisperServer.defaultAPIKey
        case .compatibleAPI, .speechAnalyzer:
            return storedAPIKey
        }
    }
}

// --- SwiftData Model for Application Settings ---
@Model
final class AppSettings {
    // Default ID for single settings instance
    var id: String = "app_settings" 
    
    // Transcription settings
    var whisperBaseURL: String = "https://api.openai.com/v1/"
    var whisperAPIKey: String = ""
    var whisperModel: String = ""
    var whisperProviderRawValue: String = WhisperProvider.compatibleAPI.rawValue
    var speechAnalyzerLocaleIdentifier: String = ""
    
    // LLM Context settings
    var useChunking: Bool = true // Option to enable/disable chunking entirely
    var chunkSize: Int = 25000 // Chunk size when chunking is enabled
    
    // OpenAI compatible server settings
    var openAIBaseURL: String = "https://api.openai.com/v1/"
    var openAIAPIKey: String = ""
    var openAIModel: String = ""

    // Interface language override (empty = system)
    var appLanguageCode: String = ""
    
    // Prompts
    var chunkPrompt: String = """
<task>
  <instructions>
    Analyze the text in the `<source>` tag.
    Create a concise summary in the SAME language as the original text.
    The summary must be a bulleted list. Each point must start with '- '.
    IMPORTANT: You must output ONLY the bulleted list. Do not add any introductory text, titles, or comments. Your response must begin directly with the first bullet point.
  </instructions>
  <source>
    {transcription}
  </source>
</task>
"""
    
    var summaryPrompt: String = """
<task>
  <instructions>
    Synthesize the fragmented summaries from `<source_summaries>` into a single, de-duplicated list.

    RULES:
    - Merge related points. Remove all repetition.
    - Use the SAME language as the source.
    - Output ONLY a bulleted list ('- '). NO intro, NO titles, NO comments.
  </instructions>

  <source_summaries>
    {transcription}
  </source_summaries>
</task>
"""
    
    var autoGenerateTitleFromSummary: Bool = true
    
    var summaryTitlePrompt: String = """
<task>
  <instructions>
    Analyze the summary in the `<source_summary>` tag.
    Create a short, descriptive title that captures its main topic.
    
    RULES:
    - The title must be in the SAME language as the summary.
    - MAXIMUM 5 words.
    - Output ONLY the title. NO quotes, NO extra punctuation, NO introductory text.
  </instructions>

  <source_summary>
    {summary}
  </source_summary>
</task>
"""
    
    init() {
        // Use default values - let user choose provider explicitly
    }
    
    init(id: String = "app_settings", 
         whisperProvider: WhisperProvider = .compatibleAPI,
         whisperBaseURL: String, 
         whisperAPIKey: String = "",
         whisperModel: String = "",
         useChunking: Bool = true,
         chunkSize: Int = 25000, 
         openAIBaseURL: String,
         openAIAPIKey: String = "",
         openAIModel: String = "",
         chunkPrompt: String,
         summaryPrompt: String,
         autoGenerateTitleFromSummary: Bool = true,
         summaryTitlePrompt: String = """
Create a concise title of at most five words that captures the essence of this summary. Respond with the title only, without quotes or enclosing punctuation.

{summary}
""") {
        self.id = id
        self.whisperProvider = whisperProvider
        self.whisperBaseURL = whisperBaseURL
        self.whisperAPIKey = whisperAPIKey
        self.whisperModel = whisperModel
        self.useChunking = useChunking
        self.chunkSize = chunkSize
        self.openAIBaseURL = openAIBaseURL
        self.openAIAPIKey = openAIAPIKey
        self.openAIModel = openAIModel
        self.chunkPrompt = chunkPrompt
        self.summaryPrompt = summaryPrompt
        self.autoGenerateTitleFromSummary = autoGenerateTitleFromSummary
        self.summaryTitlePrompt = summaryTitlePrompt
    }
}

// MARK: - Extensions

extension AppSettings {
    /// Validate if Whisper settings are properly configured
    var isWhisperConfigured: Bool {
        switch whisperProvider {
        case .speechAnalyzer:
            return true
        case .whisperServer, .compatibleAPI:
            let baseURL = resolvedWhisperBaseURL
            return !baseURL.isEmpty && APIURLBuilder.isValidBaseURL(baseURL)
        }
    }
    
    /// Validate if OpenAI settings are properly configured
    var isOpenAIConfigured: Bool {
        return !openAIBaseURL.isEmpty && APIURLBuilder.isValidBaseURL(openAIBaseURL)
    }
    
    var whisperProvider: WhisperProvider {
        get {
            guard let provider = WhisperProvider(rawValue: whisperProviderRawValue) else {
                return .compatibleAPI
            }
            
            if provider == .speechAnalyzer {
                if #available(macOS 26, *) {
                    return provider
                } else {
                    return .compatibleAPI
                }
            }
            
            return provider
        }
        set {
            if newValue == .speechAnalyzer {
                if #available(macOS 26, *) {
                    whisperProviderRawValue = newValue.rawValue
                } else {
                    whisperProviderRawValue = WhisperProvider.compatibleAPI.rawValue
                }
            } else {
                whisperProviderRawValue = newValue.rawValue
            }
        }
    }
    
    var resolvedWhisperBaseURL: String {
        whisperProvider.resolvedBaseURL(using: whisperBaseURL)
    }
    
    var resolvedWhisperAPIKey: String {
        whisperProvider.resolvedAPIKey(using: whisperAPIKey)
    }
    
    var allowsCustomWhisperCredentials: Bool {
        whisperProvider.allowsCustomCredentials
    }
    
    var resolvedSpeechAnalyzerLocale: Locale {
        if speechAnalyzerLocaleIdentifier.isEmpty {
            return Locale.current
        }
        return Locale(identifier: speechAnalyzerLocaleIdentifier)
    }
}
