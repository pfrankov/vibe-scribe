//
//  AppSettings.swift
//  VibeScribe
//
//  Created by System on 14.04.2025.
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
    var chunkSize: Int = 750
    
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

{summaries}

The combined text should be well-structured and feel like a single document rather than disconnected parts.
"""
    
    init() {
        // Use default values from above
    }
    
    init(id: String = "app_settings", 
         whisperBaseURL: String, 
         whisperAPIKey: String = "",
         whisperModel: String = "",
         chunkSize: Int, 
         openAIBaseURL: String,
         openAIAPIKey: String = "",
         openAIModel: String = "",
         chunkPrompt: String,
         summaryPrompt: String) {
        self.id = id
        self.whisperBaseURL = whisperBaseURL
        self.whisperAPIKey = whisperAPIKey
        self.whisperModel = whisperModel
        self.chunkSize = chunkSize
        self.openAIBaseURL = openAIBaseURL
        self.openAIAPIKey = openAIAPIKey
        self.openAIModel = openAIModel
        self.chunkPrompt = chunkPrompt
        self.summaryPrompt = summaryPrompt
    }
} 