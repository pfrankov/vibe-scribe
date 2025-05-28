//
//  SettingsView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData
import Combine

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
    
    @StateObject private var modelService = ModelService.shared
    
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
        .onAppear {
            _ = settings
            loadModelsIfNeeded()
        }
        .onChange(of: settings.whisperBaseURL) { _, _ in
            loadWhisperModelsIfURLValid()
        }
        .onChange(of: settings.whisperAPIKey) { _, _ in
            loadWhisperModelsIfURLValid()
        }
        .onChange(of: settings.openAIBaseURL) { _, _ in
            loadOpenAIModelsIfURLValid()
        }
        .onChange(of: settings.openAIAPIKey) { _, _ in
            loadOpenAIModelsIfURLValid()
        }
    }
    
    // MARK: - Content Sections
    
    @ViewBuilder
    private var speechToTextContent: some View {
        settingsField(
            title: "Whisper compatible API base URL",
            placeholder: "https://api.example.com/v1/",
            value: Binding(
                get: { settings.whisperBaseURL },
                set: { newValue in
                    settings.whisperBaseURL = newValue
                    trySave()
                }
            ),
            caption: "e.g., https://api.openai.com/v1/ or your local Whisper instance base URL. Endpoint will be appended automatically."
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
            HStack {
                Text("Whisper Model")
                    .font(.system(size: UIConstants.fontSize))
                
                Spacer()
                
                Button(action: { modelService.loadWhisperModels(baseURL: settings.whisperBaseURL, apiKey: settings.whisperAPIKey) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(modelService.isLoadingWhisperModels || settings.whisperBaseURL.isEmpty)
                .help("Refresh models list")
            }
            
            if modelService.isLoadingWhisperModels {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 22)
            } else {
                ComboBoxView(
                    placeholder: modelService.whisperModels.isEmpty ? "Enter model name or refresh list" : "Select Whisper model",
                    options: modelService.whisperModels,
                    selectedOption: Binding(
                        get: { settings.whisperModel },
                        set: { newValue in
                            settings.whisperModel = newValue
                            trySave()
                        }
                    )
                )
                .frame(height: 22)
            }
            
            if let error = modelService.whisperModelsError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            captionText("Specify the Whisper model to use for transcription. You can select from the list, refresh to load from server, or choose 'Custom...' to enter manually.")
        }
    }
    
    @ViewBuilder
    private var summaryContent: some View {
        settingsField(
            title: "OpenAI compatible API base URL",
            placeholder: "https://api.example.com/v1/",
            value: Binding(
                get: { settings.openAIBaseURL },
                set: { newValue in
                    settings.openAIBaseURL = newValue
                    trySave()
                }
            ),
            caption: "e.g., https://api.openai.com/v1/ or your custom summarization endpoint base URL. Endpoint will be appended automatically."
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
            HStack {
                Text("OpenAI Model")
                    .font(.system(size: UIConstants.fontSize))
                
                Spacer()
                
                Button(action: { modelService.loadOpenAIModels(baseURL: settings.openAIBaseURL, apiKey: settings.openAIAPIKey) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(modelService.isLoadingOpenAIModels || settings.openAIBaseURL.isEmpty)
                .help("Refresh models list")
            }
            
            if modelService.isLoadingOpenAIModels {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 22)
            } else {
                ComboBoxView(
                    placeholder: modelService.openAIModels.isEmpty ? "Enter model name or refresh list" : "Select LLM model",
                    options: modelService.openAIModels,
                    selectedOption: Binding(
                        get: { settings.openAIModel },
                        set: { newValue in
                            settings.openAIModel = newValue
                            trySave()
                        }
                    )
                )
                .frame(height: 22)
            }
            
            if let error = modelService.openAIModelsError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            captionText("Specify the model to use for summarization. You can select from the list, refresh to load from server, or choose 'Custom...' to enter manually.")
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
    
    private func loadModelsIfNeeded() {
        loadWhisperModelsIfURLValid()
        loadOpenAIModelsIfURLValid()
    }
    
    private func loadWhisperModelsIfURLValid() {
        guard !settings.whisperBaseURL.isEmpty else { return }
        
        guard APIURLBuilder.isValidBaseURL(settings.whisperBaseURL) else {
            modelService.whisperModelsError = "Invalid URL format"
            return
        }
        
        modelService.loadWhisperModels(baseURL: settings.whisperBaseURL, apiKey: settings.whisperAPIKey)
    }
    
    private func loadOpenAIModelsIfURLValid() {
        guard !settings.openAIBaseURL.isEmpty else { return }
        
        guard APIURLBuilder.isValidBaseURL(settings.openAIBaseURL) else {
            modelService.openAIModelsError = "Invalid URL format"
            return
        }
        
        modelService.loadOpenAIModels(baseURL: settings.openAIBaseURL, apiKey: settings.openAIAPIKey)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
} 