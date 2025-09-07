//
//  AppSettings.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 14.04.2025.
//

import Foundation
import SwiftData

// --- SwiftData Model for Application Settings ---
@Model
final class AppSettings {
    // Default ID for single settings instance
    var id: String = "app_settings" 
    
    // Transcription settings
    var whisperBaseURL: String = "https://api.openai.com/v1/"
    var whisperAPIKey: String = ""
    var whisperModel: String = ""
    
    // LLM Context settings
    var useChunking: Bool = true // Option to enable/disable chunking entirely
    var chunkSize: Int = 25000 // Chunk size when chunking is enabled
    
    // OpenAI compatible server settings
    var openAIBaseURL: String = "https://api.openai.com/v1/"
    var openAIAPIKey: String = ""
    var openAIModel: String = ""
    
    // Prompts
    var chunkPrompt: String = """
Summarize this part of transcription concisely while keeping the main ideas, insights, and important details:

{transcription}

Give me only the summary, don't include any introductory phrases.
"""
    
    var summaryPrompt: String = """
Combine these summaries into one cohesive document that flows naturally:

{transcription}

The combined text should be well-structured and feel like a single document rather than disconnected parts.
"""
    
    init() {
        // Use default values from above
    }
    
    init(id: String = "app_settings", 
         whisperBaseURL: String, 
         whisperAPIKey: String = "",
         whisperModel: String = "",
         useChunking: Bool = true,
         chunkSize: Int = 25000, 
         openAIBaseURL: String,
         openAIAPIKey: String = "",
         openAIModel: String = "",
         chunkPrompt: String,
         summaryPrompt: String) {
        self.id = id
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
    }
}

// MARK: - Extensions

extension AppSettings {
    /// Validate if Whisper settings are properly configured
    var isWhisperConfigured: Bool {
        return !whisperBaseURL.isEmpty && APIURLBuilder.isValidBaseURL(whisperBaseURL)
    }
    
    /// Validate if OpenAI settings are properly configured
    var isOpenAIConfigured: Bool {
        return !openAIBaseURL.isEmpty && APIURLBuilder.isValidBaseURL(openAIBaseURL)
    }
    
    // Convenience flags remain above; removed redundant helpers in earlier edit
} 