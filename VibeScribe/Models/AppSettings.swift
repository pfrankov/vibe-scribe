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
    var whisperURL: String = "https://api.openai.com/v1/audio/transcriptions"
    
    // LLM Context settings
    var chunkSize: Int = 750
    
    // OpenAI compatible server settings
    var openAICompatibleURL: String = "https://api.openai.com/v1/chat/completions"
    
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
         whisperURL: String, 
         chunkSize: Int, 
         openAICompatibleURL: String,
         chunkPrompt: String,
         summaryPrompt: String) {
        self.id = id
        self.whisperURL = whisperURL
        self.chunkSize = chunkSize
        self.openAICompatibleURL = openAICompatibleURL
        self.chunkPrompt = chunkPrompt
        self.summaryPrompt = summaryPrompt
    }
} 