//
//  SettingsView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData
import Combine
import AppKit

// MARK: - UI Constants
private struct UIConstants {
    static let spacing: CGFloat = 16
    static let smallSpacing: CGFloat = 6
    static let tinySpacing: CGFloat = 4
    
    static let horizontalMargin: CGFloat = 24
    static let verticalMargin: CGFloat = 16
    
    static let cornerRadius: CGFloat = 6
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

enum FocusedField {
    case textField
    case chunkPromptEditor
    case summaryPromptEditor
    case chunkSizeField
}

// MARK: - Custom TextEditor with controlled scrolling
struct OptimizedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    @FocusState.Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = text
        
        // Configure scroll view to reduce overscroll effects
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        
        // Reduce elastic scrolling effects
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        
        // Set up text change notifications
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Handle focus state
        if isFocused && textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        } else if !isFocused && textView.window?.firstResponder == textView {
            textView.window?.makeFirstResponder(nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: OptimizedTextEditor
        
        init(_ parent: OptimizedTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
        
        // Use proper NSTextViewDelegate methods for focus tracking
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // This method is called when the text view receives commands
            // We can use it to detect when editing begins
            if !parent.isFocused {
                parent.isFocused = true
            }
            return false // Let the text view handle the command
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            guard notification.object as? NSTextView != nil else { return }
            parent.isFocused = true
        }
        
        func textDidEndEditing(_ notification: Notification) {
            guard notification.object as? NSTextView != nil else { return }
            parent.isFocused = false
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<AppSettings> { $0.id == "app_settings" })
    private var appSettings: [AppSettings]
    
    @FocusState private var focusedField: FocusedField?
    @State private var selectedTab: SettingsTab = .speechToText
    @State private var chunkSizeText: String = ""
    
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
                .contentShape(Rectangle()) // Make the content area tappable
                .onTapGesture {
                    // Dismiss focus when tapping on empty space in content area
                    focusedField = nil
                }
            }
            .scrollDisabled(focusedField == .chunkPromptEditor || focusedField == .summaryPromptEditor)
        }
        .onAppear {
            _ = settings
            chunkSizeText = String(settings.chunkSize)
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
            Text("Final summary prompt")
                .font(.system(size: UIConstants.fontSize))
            
            styledTextEditor(
                text: Binding(
                    get: { settings.summaryPrompt },
                    set: { newValue in
                        settings.summaryPrompt = newValue
                        trySave()
                    }
                ),
                focusField: .summaryPromptEditor
            )
            
            captionText("Use {transcription} as a placeholder for the text to be processed.")
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            HStack {
                Toggle("Split long texts into chunks", isOn: Binding(
                    get: { settings.useChunking },
                    set: { newValue in
                        settings.useChunking = newValue
                        trySave()
                    }
                ))
                .toggleStyle(.checkbox)
                
                Spacer()
            }
            
            captionText("When enabled, long texts are split into smaller chunks before processing.")
        }
        
        if settings.useChunking {
            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                Text("Prompt for individual chunks")
                    .font(.system(size: UIConstants.fontSize))
                
                styledTextEditor(
                    text: Binding(
                        get: { settings.chunkPrompt },
                        set: { newValue in
                            settings.chunkPrompt = newValue
                            trySave()
                        }
                    ),
                    focusField: .chunkPromptEditor
                )
                
                captionText("Use {transcription} as a placeholder for the individual chunk text.")
            }
            
            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                Text("Chunk Size (characters)")
                    .font(.system(size: UIConstants.fontSize))
                
                TextField("25000", text: $chunkSizeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($focusedField, equals: .chunkSizeField)
                    .onSubmit {
                        // Save when user presses Enter
                        saveChunkSize()
                        focusedField = nil
                    }
                    .onChange(of: focusedField) { _, newValue in
                        // Save when focus is lost
                        if newValue != .chunkSizeField && !chunkSizeText.isEmpty {
                            saveChunkSize()
                        }
                    }
                
                captionText("Maximum size for each text chunk in characters. Text is split intelligently by paragraphs first, then sentences, then words.")
            }
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
            .focused($focusedField, equals: .textField)
            .onKeyPress(.escape) {
                // Dismiss focus when Escape is pressed
                focusedField = nil
                return .handled
            }
            .onTapGesture {
                // Prevent tap from bubbling up to parent
            }
            
            captionText(caption)
        }
    }
    
    private func styledTextEditor(
        text: Binding<String>,
        focusField: FocusedField
    ) -> some View {
        let isFocused = focusedField == focusField
        
        return TextEditor(text: text)
            .font(.system(size: UIConstants.fontSize))
            .padding(UIConstants.smallSpacing)
            .frame(height: UIConstants.textEditorHeight)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .strokeBorder(
                        isFocused 
                            ? Color(NSColor.keyboardFocusIndicatorColor)
                            : Color(NSColor.separatorColor),
                        lineWidth: isFocused ? 3.0 : 1.0
                    )
                    .allowsHitTesting(false) // Prevent overlay from interfering with scroll
            )
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius))
            .focused($focusedField, equals: focusField)
            .onKeyPress(.escape) {
                // Dismiss focus when Escape is pressed
                focusedField = nil
                return .handled
            }
            .onTapGesture {
                // Prevent tap from bubbling up to parent
            }
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
                            Logger.error("Error saving settings", error: error, category: .data)
        }
    }
    
    private func saveChunkSize() {
        // Convert text to Int, allow any number (including 0 or negative)
        if let chunkSize = Int(chunkSizeText) {
            settings.chunkSize = chunkSize
            trySave()
        } else {
            // If invalid input, revert to current settings value
            chunkSizeText = String(settings.chunkSize)
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