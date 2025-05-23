//
//  SettingsView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// MARK: - UI Constants
private struct UIConstants {
    static let spacing: CGFloat = 16
    static let smallSpacing: CGFloat = 8
    static let tinySpacing: CGFloat = 4
    
    static let horizontalMargin: CGFloat = 24
    static let verticalMargin: CGFloat = 16
    
    static let cornerRadius: CGFloat = 4
    static let textEditorHeight: CGFloat = 100
    static let tabPickerMaxWidth: CGFloat = 280
    
    static let fontSize: CGFloat = 13
    static let captionFontSize: CGFloat = 11
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case speechToText = "Speech to Text"
    case summary = "Summary"
    
    var id: String { self.rawValue }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<AppSettings> { $0.id == "app_settings" })
    private var appSettings: [AppSettings]
    
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isTextEditorFocused: Bool
    @State private var selectedTab: SettingsTab = .speechToText
    
    private var settings: AppSettings {
        if let existingSettings = appSettings.first {
            return existingSettings
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, UIConstants.spacing)
            .padding(.bottom, UIConstants.spacing)
            .frame(maxWidth: UIConstants.tabPickerMaxWidth)
            
            // Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: UIConstants.spacing * 1.5) {
                    if selectedTab == .speechToText {
                        speechToTextContent
                    } else {
                        summaryContent
                    }
                    
                    Spacer(minLength: UIConstants.spacing)
                }
                .padding(.horizontal, UIConstants.horizontalMargin)
                .padding(.vertical, UIConstants.verticalMargin)
            }
        }
        .onAppear { _ = settings }
    }
    
    // MARK: - Content Sections
    
    @ViewBuilder
    private var speechToTextContent: some View {
        settingsField(
            title: "Whisper compatible API URL",
            placeholder: "https://api.example.com/v1/audio/transcriptions",
            value: Binding(
                get: { settings.whisperURL },
                set: { newValue in
                    settings.whisperURL = newValue
                    trySave()
                }
            ),
            caption: "e.g., https://api.openai.com/v1/audio/transcriptions or your local Whisper instance."
        )
        
        settingsField(
            title: "Whisper API Key",
            placeholder: "sk-...",
            value: Binding(
                get: { settings.whisperAPIKey },
                set: { newValue in
                    settings.whisperAPIKey = newValue
                    trySave()
                }
            ),
            caption: "Your Whisper API key. Leave empty for local servers that don't require authentication."
        )
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text("Whisper Model")
                .font(.system(size: UIConstants.fontSize))
            
            ComboBoxView(
                placeholder: "Select Whisper model",
                options: ["whisper-1", "tiny", "base", "small", "medium", "large", "large-v1", "large-v2", "large-v3"],
                selectedOption: Binding(
                    get: { settings.whisperModel },
                    set: { newValue in
                        settings.whisperModel = newValue
                        trySave()
                    }
                )
            )
            .frame(height: 22)
            
            captionText("Specify the Whisper model to use for transcription. May vary depending on your server implementation.")
        }
    }
    
    @ViewBuilder
    private var summaryContent: some View {
        settingsField(
            title: "OpenAI compatible API URL",
            placeholder: "https://api.example.com/v1/chat/completions",
            value: Binding(
                get: { settings.openAICompatibleURL },
                set: { newValue in
                    settings.openAICompatibleURL = newValue
                    trySave()
                }
            ),
            caption: "e.g., https://api.openai.com/v1/chat/completions or your custom summarization endpoint."
        )
        
        settingsField(
            title: "OpenAI API Key",
            placeholder: "sk-...",
            value: Binding(
                get: { settings.openAIAPIKey },
                set: { newValue in
                    settings.openAIAPIKey = newValue
                    trySave()
                }
            ),
            caption: "Your OpenAI API key. Leave empty for local servers that don't require authentication."
        )
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text("OpenAI Model")
                .font(.system(size: UIConstants.fontSize))
            
            ComboBoxView(
                placeholder: "Select LLM model",
                options: ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo", "claude-3-opus-20240229"],
                selectedOption: Binding(
                    get: { settings.openAIModel },
                    set: { newValue in
                        settings.openAIModel = newValue
                        trySave()
                    }
                )
            )
            .frame(height: 22)
            
            captionText("Specify the model to use for summarization. Custom models from local servers can be entered manually.")
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text("Prompt for individual transcription chunks")
                .font(.system(size: UIConstants.fontSize))
            
            styledTextEditor(Binding(
                get: { settings.chunkPrompt },
                set: { newValue in
                    settings.chunkPrompt = newValue
                    trySave()
                }
            ))
            
            captionText("Use {transcription} as a placeholder for the transcription text.")
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text("Prompt for combining chunk summaries")
                .font(.system(size: UIConstants.fontSize))
            
            styledTextEditor(Binding(
                get: { settings.summaryPrompt },
                set: { newValue in
                    settings.summaryPrompt = newValue
                    trySave()
                }
            ))
            
            captionText("Use {summaries} as a placeholder for the combined chunk summaries.")
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text("Chunk Size (characters)")
                .font(.system(size: UIConstants.fontSize))
            
            TextField("1000", value: Binding(
                get: { settings.chunkSize },
                set: { newValue in
                    let clampedValue = max(100, min(2000, newValue))
                    if settings.chunkSize != clampedValue {
                        settings.chunkSize = clampedValue
                        trySave()
                    }
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 100)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            captionText("Text chunk size for LLM processing (100-2000 characters). Larger chunks = more context but higher token cost.")
        }
    }
    
    // MARK: - Helper Components
    
    @ViewBuilder
    private func settingsField(
        title: String,
        placeholder: String,
        value: Binding<String>,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text(title)
                .font(.system(size: UIConstants.fontSize))
            
            TextField(placeholder, text: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    trySave()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isTextFieldFocused)
            
            captionText(caption)
        }
    }
    
    private func styledTextEditor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(size: UIConstants.fontSize))
            .padding(UIConstants.smallSpacing)
            .frame(height: UIConstants.textEditorHeight)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(UIConstants.cornerRadius)
            .focused($isTextEditorFocused)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .stroke(
                        isTextEditorFocused ? Color(NSColor.controlAccentColor) : Color(NSColor.separatorColor),
                        lineWidth: 0.5
                    )
            )
    }
    
    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: UIConstants.captionFontSize))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
    }
    
    private func trySave() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving settings: \(error)")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
} 