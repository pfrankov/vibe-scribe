//
//  SettingsView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import Combine
import AppKit
#if canImport(Speech)
import Speech
#endif

// MARK: - UI Constants
private struct UIConstants {
    static let spacing: CGFloat = 16
    static let smallSpacing: CGFloat = 8
    static let tinySpacing: CGFloat = 6
    
    static let horizontalMargin: CGFloat = 28
    static let verticalMargin: CGFloat = 18
    
    static let cornerRadius: CGFloat = 6
    static let textEditorHeight: CGFloat = 100
    static let tabPickerMaxWidth: CGFloat = 280
    
    static let fontSize: CGFloat = 13
    static let captionFontSize: CGFloat = 11
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case speechToText = "speech.to.text"
    case summary = "summary"
    
    var id: String { self.rawValue }

    var titleKey: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

enum FocusedField {
    case textField
    case chunkPromptEditor
    case summaryPromptEditor
    case chunkSizeField
    case summaryTitlePromptEditor
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
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<AppSettings> { $0.id == "app_settings" })
    private var appSettings: [AppSettings]
#if DEBUG
    @AppStorage("debug.simulateEmptyRecordings") private var simulateEmptyRecordings = false
#endif
    @AppStorage("ui.language.code") private var appLanguageCode: String = ""
    
    @State private var showRestartAlert = false
    @FocusState private var focusedField: FocusedField?
    @State private var selectedTab: SettingsTab = .speechToText
    @State private var chunkSizeText: String = ""
#if canImport(Speech)
    @State private var speechAnalyzerLocales: [Locale] = []
    @State private var isLoadingSpeechAnalyzerLocales = false
    @State private var speechAnalyzerLocalesError: String? = nil
#endif
    
    @StateObject private var modelService = ModelService.shared
    
    private var settings: AppSettings {
        if let existingSettings = appSettings.first {
            // Sync AppStorage to model if needed (e.g., first launch after update)
            if !appLanguageCode.isEmpty, existingSettings.appLanguageCode != appLanguageCode {
                existingSettings.appLanguageCode = appLanguageCode
                try? modelContext.save()
            }
            return existingSettings
        } else {
            let newSettings = AppSettings()
            if !appLanguageCode.isEmpty {
                newSettings.appLanguageCode = appLanguageCode
            }
            modelContext.insert(newSettings)
            return newSettings
        }
    }
    
    private let supportedLanguageCodes: [String] = {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted()
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            appLanguageSection

            // Tab selector
            Picker(AppLanguage.localized("settings"), selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.titleKey).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, UIConstants.horizontalMargin)
            .padding(.top, UIConstants.smallSpacing)
            .padding(.bottom, UIConstants.smallSpacing)
            .frame(maxWidth: UIConstants.tabPickerMaxWidth)
            
            // Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: UIConstants.spacing) {
                    if selectedTab == .speechToText {
                        speechToTextContent
                    } else {
                        summaryContent
                    }
                    
#if DEBUG
                    adminSettingsSection
#endif
                    
                    Spacer(minLength: UIConstants.spacing)
                }
                .padding(.horizontal, UIConstants.horizontalMargin)
                .padding(.top, UIConstants.smallSpacing)
                .padding(.bottom, UIConstants.verticalMargin)
                .contentShape(Rectangle()) // Make the content area tappable
                .onTapGesture {
                    // Dismiss focus when tapping on empty space in content area
                    focusedField = nil
                }
            }
            .scrollDisabled(
                focusedField == .chunkPromptEditor ||
                focusedField == .summaryPromptEditor ||
                focusedField == .summaryTitlePromptEditor
            )
        }
        .onAppear {
            _ = settings
            chunkSizeText = String(settings.chunkSize)
            loadModelsIfNeeded()
            AppLanguage.applyPreferredLanguagesIfNeeded(code: appLanguageCode)
        }
        .onChange(of: settings.whisperBaseURL) { _, _ in
            loadWhisperModelsIfURLValid()
        }
        .onChange(of: settings.whisperAPIKey) { _, _ in
            loadWhisperModelsIfURLValid()
        }
        .onChange(of: settings.whisperProviderRawValue) { _, _ in
            loadWhisperModelsIfURLValid()
            loadSpeechAnalyzerLocalesIfNeeded()
        }
        .onChange(of: settings.openAIBaseURL) { _, _ in
            loadOpenAIModelsIfURLValid()
        }
        .onChange(of: settings.openAIAPIKey) { _, _ in
            loadOpenAIModelsIfURLValid()
        }
    }

    @ViewBuilder
    private var speechAnalyzerLanguageSection: some View {
#if canImport(Speech)
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            HStack {
                Text(AppLanguage.localized("language"))
                    .font(.system(size: UIConstants.fontSize))

                Spacer()

                Button {
                    loadSpeechAnalyzerLocales(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingSpeechAnalyzerLocales)
                .help(AppLanguage.localized("refresh.languages.list"))
            }

            if isLoadingSpeechAnalyzerLocales {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(AppLanguage.localized("loading.languages.ellipsis"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 22)
            } else {
                Picker("", selection: Binding(
                    get: { settings.speechAnalyzerLocaleIdentifier },
                    set: { newValue in
                        settings.speechAnalyzerLocaleIdentifier = newValue
                        trySave()
                    }
                )) {
                    Text(AppLanguage.localized("automatic")).tag("")
                    ForEach(speechAnalyzerLocales, id: \.identifier) { locale in
                        Text(localeDisplayName(locale)).tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260, alignment: .leading)
            }

            if let error = speechAnalyzerLocalesError {
                InlineMessageView(error)
            }
        }
#else
        InlineMessageView(AppLanguage.localized("native.transcription.language.selection.requires.the.speech.framework"))
#endif
    }

    // MARK: - Content Sections

    private var header: some View {
        HStack(spacing: UIConstants.smallSpacing) {
            Text(AppLanguage.localized("settings"))
                .font(.system(size: UIConstants.fontSize, weight: .semibold))

            Spacer()

            Button(action: closeSettings) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .help("Close settings")
        }
        .padding(.horizontal, UIConstants.horizontalMargin)
        .padding(.top, UIConstants.verticalMargin)
        .padding(.bottom, UIConstants.smallSpacing)
    }
    
    @ViewBuilder
    private var speechToTextContent: some View {
        // Provider selector
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Picker("", selection: Binding(
                get: { settings.whisperProvider },
                set: { newValue in
                    settings.whisperProvider = newValue
                    trySave()
                }
            )) {
                ForEach(WhisperProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }

        if settings.whisperProvider == .defaultProvider {
            InlineMessageView(AppLanguage.localized("default.provider.caption"), style: .info)
        }

        if settings.whisperProvider == .speechAnalyzer {
            speechAnalyzerLanguageSection
        }

        // Group: WhisperServer
        if settings.whisperProvider == .whisperServer {
            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                HStack {
                    Text(AppLanguage.localized("model"))
                        .font(.system(size: UIConstants.fontSize))

                    Spacer()

                    Button(action: {
                        modelService.loadWhisperModels(
                            baseURL: settings.resolvedWhisperBaseURL,
                            apiKey: settings.resolvedWhisperAPIKey
                        )
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(modelService.isLoadingWhisperModels)
                    .help(AppLanguage.localized("refresh.models.list"))
                }

                if modelService.isLoadingWhisperModels {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppLanguage.localized("loading.models.ellipsis"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 22)
                } else {
                    ComboBoxView(
                        placeholder: modelService.whisperModels.isEmpty
                            ? AppLanguage.localized("enter.model.name.or.refresh.list")
                            : AppLanguage.localized("select.model"),
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
                    InlineMessageView(error)
                }
            }
        }

        // Group: Whisper compatible API
        if settings.whisperProvider == .compatibleAPI {
            settingsField(
                title: LocalizedStringKey("whisper.compatible.api.base.url"),
                placeholder: LocalizedStringKey("https.api.example.com.v1"),
                value: Binding(
                    get: { settings.whisperBaseURL },
                    set: { newValue in
                        settings.whisperBaseURL = newValue
                        trySave()
                    }
                ),
                caption: LocalizedStringKey("e.g.https.api.openai.com.v1.or.your.local.whisper.instance.base.url.endpoint.will.be.appended.automatically")
            )

            settingsField(
                title: LocalizedStringKey("whisper.api.key"),
                placeholder: LocalizedStringKey("sk.ellipsis"),
                value: Binding(
                    get: { settings.whisperAPIKey },
                    set: { newValue in
                        settings.whisperAPIKey = newValue
                        trySave()
                    }
                ),
                caption: LocalizedStringKey("your.whisper.api.key.leave.empty.for.local.servers.that.dont.require.authentication")
            )

            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                HStack {
                    Text(AppLanguage.localized("whisper.model"))
                        .font(.system(size: UIConstants.fontSize))

                    Spacer()

                    Button(action: {
                        modelService.loadWhisperModels(
                            baseURL: settings.whisperBaseURL,
                            apiKey: settings.whisperAPIKey
                        )
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(modelService.isLoadingWhisperModels || settings.whisperBaseURL.isEmpty)
                    .help(AppLanguage.localized("refresh.models.list"))
                }

                if modelService.isLoadingWhisperModels {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppLanguage.localized("loading.models.ellipsis"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 22)
                } else {
                    ComboBoxView(
                        placeholder: modelService.whisperModels.isEmpty
                            ? AppLanguage.localized("enter.model.name.or.refresh.list")
                            : AppLanguage.localized("select.whisper.model"),
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
                    InlineMessageView(error)
                }

                captionText(LocalizedStringKey("specify.the.whisper.model.to.use.for.transcription.you.can.select.from.the.list.refresh.to.load.from.server.or.choose.custom.ellipsis.to.enter.manually"))
            }
        }
    }
    
    @ViewBuilder
    private var summaryContent: some View {
        settingsField(
            title: LocalizedStringKey("openai.compatible.api.base.url"),
            placeholder: LocalizedStringKey("https.api.example.com.v1"),
            value: Binding(
                get: { settings.openAIBaseURL },
                set: { newValue in
                    settings.openAIBaseURL = newValue
                    trySave()
                }
            ),
            caption: LocalizedStringKey("openai.base.url.caption")
        )
        
        settingsField(
            title: LocalizedStringKey("openai.api.key"),
            placeholder: LocalizedStringKey("sk.ellipsis"),
            value: Binding(
                get: { settings.openAIAPIKey },
                set: { newValue in
                    settings.openAIAPIKey = newValue
                    trySave()
                }
            ),
            caption: LocalizedStringKey("your.openai.api.key.leave.empty.for.local.servers.that.dont.require.authentication")
        )
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            HStack {
                Text(AppLanguage.localized("openai.model"))
                    .font(.system(size: UIConstants.fontSize))
                
                Spacer()
                
                Button(action: { modelService.loadOpenAIModels(baseURL: settings.openAIBaseURL, apiKey: settings.openAIAPIKey) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(modelService.isLoadingOpenAIModels || settings.openAIBaseURL.isEmpty)
                .help(AppLanguage.localized("refresh.models.list"))
            }
            
            if modelService.isLoadingOpenAIModels {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(AppLanguage.localized("loading.models.ellipsis"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 22)
            } else {
                ComboBoxView(
                    placeholder: modelService.openAIModels.isEmpty
                        ? AppLanguage.localized("enter.model.name.or.refresh.list")
                        : AppLanguage.localized("select.llm.model"),
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
                InlineMessageView(error)
            }
            
            captionText(LocalizedStringKey("specify.the.model.to.use.for.summarization.you.can.select.from.the.list.refresh.to.load.from.server.or.choose.custom.ellipsis.to.enter.manually"))
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text(AppLanguage.localized("prompt"))
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
            
            captionText(LocalizedStringKey("use.transcription.as.a.placeholder.for.the.individual.chunk.text"))
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Toggle(AppLanguage.localized("generate.short.title.after.summarization"), isOn: Binding(
                get: { settings.autoGenerateTitleFromSummary },
                set: { newValue in
                    settings.autoGenerateTitleFromSummary = newValue
                    trySave()
                }
            ))
            .toggleStyle(.checkbox)
            
            captionText(LocalizedStringKey("when.enabled.the.app.asks.the.language.model.for.a.concise.title.based.on.the.final.summary"))
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text(AppLanguage.localized("title.generation.prompt"))
                .font(.system(size: UIConstants.fontSize))
            
            styledTextEditor(
                text: Binding(
                    get: { settings.summaryTitlePrompt },
                    set: { newValue in
                        settings.summaryTitlePrompt = newValue
                        trySave()
                    }
                ),
                focusField: .summaryTitlePromptEditor
            )
            .disabled(!settings.autoGenerateTitleFromSummary)
            
            captionText(LocalizedStringKey("use.summary.as.a.placeholder.for.the.completed.summary.text.the.model.should.answer.with.a.title.only"))
        }
        
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            HStack {
                Toggle(AppLanguage.localized("split.long.texts.into.chunks"), isOn: Binding(
                    get: { settings.useChunking },
                    set: { newValue in
                        settings.useChunking = newValue
                        trySave()
                    }
                ))
                .toggleStyle(.checkbox)
                
                Spacer()
            }
            
            captionText(LocalizedStringKey("when.enabled.long.texts.are.split.into.smaller.chunks.before.processing"))
        }
        
        if settings.useChunking {
            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                Text(AppLanguage.localized("final.summary.prompt"))
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
                
                captionText(LocalizedStringKey("use.transcription.as.a.placeholder.for.the.text.to.be.processed"))
            }
            
            VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
                Text(AppLanguage.localized("chunk.size.characters"))
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
                
                captionText(LocalizedStringKey("maximum.size.for.each.text.chunk.in.characters.text.is.split.intelligently.by.paragraphs.first.then.sentences.then.words"))
            }
        }
    }
    
#if DEBUG
    @ViewBuilder
    private var adminSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: UIConstants.smallSpacing) {
                Toggle(AppLanguage.localized("simulate.empty.recordings.list"), isOn: Binding(
                    get: { simulateEmptyRecordings },
                    set: { newValue in
                        simulateEmptyRecordings = newValue
                    }
                ))
                
                captionText(LocalizedStringKey("hides.all.recordings.so.you.can.preview.the.empty.state.available.in.debug.builds.only"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(AppLanguage.localized("admin.tools"), systemImage: "wrench.and.screwdriver")
                .font(.system(size: UIConstants.fontSize, weight: .semibold))
        }
    }
#endif
    
    // MARK: - Helper Components
    
    @ViewBuilder
    private func settingsField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        value: Binding<String>,
        caption: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.smallSpacing) {
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
    
    private func captionText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: UIConstants.captionFontSize))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
    }

    @ViewBuilder
    private var appLanguageSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.tinySpacing) {
            Text(AppLanguage.localized("app.language"))
                .font(.system(size: UIConstants.fontSize, weight: .semibold))

            Picker("", selection: Binding(
                get: { appLanguageCode },
                set: { newValue in
                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if appLanguageCode != normalized {
                        appLanguageCode = normalized
                        settings.appLanguageCode = normalized
                        AppLanguage.applyPreferredLanguagesIfNeeded(code: normalized)
                        trySave()
                        showRestartAlert = true
                    }
                }
            )) {
                Text(AppLanguage.localized("app.language.system")).tag("")
                ForEach(supportedLanguageCodes, id: \.self) { code in
                    Text(displayName(for: code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 240, alignment: .leading)

            captionText(LocalizedStringKey("app.language.caption"))
        }
        .padding(.horizontal, UIConstants.horizontalMargin)
        .padding(.top, UIConstants.smallSpacing)
        .padding(.bottom, UIConstants.smallSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(AppLanguage.localized("app.language.restart.required"), isPresented: $showRestartAlert) {
            Button(AppLanguage.localized("restart.now")) {
                restartApp()
            }
            Button(AppLanguage.localized("restart.later"), role: .cancel) { }
        } message: {
            Text(AppLanguage.localized("app.language.restart.required.message"))
        }
    }

    @MainActor
    private func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error = error {
                Logger.error("Failed to relaunch app", error: error, category: .ui)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if NSApp.isRunning {
                        Logger.warning("Exiting current instance after restart request", category: .ui)
                        exit(EXIT_SUCCESS)
                    }
                }
            }
        }
    }

    private func displayName(for languageCode: String) -> String {
        let locale = Locale(identifier: languageCode)
        return locale.localizedString(forLanguageCode: languageCode)?.capitalized(with: .autoupdatingCurrent) ?? languageCode
    }
    
    private func trySave() {
        do {
            try modelContext.save()
        } catch {
            Logger.error("Error saving settings", error: error, category: .data)
        }
    }

    private func closeSettings() {
        dismiss()
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
        loadSpeechAnalyzerLocalesIfNeeded()
    }
    
    private func loadWhisperModelsIfURLValid() {
        let provider = settings.whisperProvider
        let baseURL = settings.resolvedWhisperBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = settings.resolvedWhisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard provider != .speechAnalyzer else {
            modelService.whisperModelsError = nil
            return
        }

        // For compatible API: don't trigger load if field is empty
        if provider == .compatibleAPI && settings.whisperBaseURL.isEmpty {
            return
        }

        guard APIURLBuilder.isValidBaseURL(baseURL) else {
            modelService.whisperModelsError = AppLanguage.localized("invalid.url.format")
            return
        }

        modelService.loadWhisperModels(baseURL: baseURL, apiKey: apiKey)
    }
    
    private func loadOpenAIModelsIfURLValid() {
        guard !settings.openAIBaseURL.isEmpty else { return }
        
        guard APIURLBuilder.isValidBaseURL(settings.openAIBaseURL) else {
            modelService.openAIModelsError = AppLanguage.localized("invalid.url.format")
            return
        }
        
        modelService.loadOpenAIModels(baseURL: settings.openAIBaseURL, apiKey: settings.openAIAPIKey)
    }

#if canImport(Speech)
    private func loadSpeechAnalyzerLocalesIfNeeded() {
        guard settings.whisperProvider == .speechAnalyzer else { return }
        if !speechAnalyzerLocales.isEmpty || isLoadingSpeechAnalyzerLocales {
            return
        }
        loadSpeechAnalyzerLocales(force: true)
    }
    
    private func loadSpeechAnalyzerLocales(force: Bool) {
        guard settings.whisperProvider == .speechAnalyzer else { return }
        if isLoadingSpeechAnalyzerLocales && !force {
            return
        }
        isLoadingSpeechAnalyzerLocales = true
        speechAnalyzerLocalesError = nil
        Task {
            if #available(macOS 26, *) {
                let locales = await Speech.SpeechTranscriber.supportedLocales
                let sorted = locales.sorted { 
                    localeDisplayName($0).localizedCaseInsensitiveCompare(localeDisplayName($1)) == .orderedAscending 
                }
                await MainActor.run {
                    self.speechAnalyzerLocales = sorted
                    self.isLoadingSpeechAnalyzerLocales = false
                    if sorted.isEmpty {
                        self.speechAnalyzerLocalesError = AppLanguage.localized("no.speech.languages.available.install.dictation.assets.in.system.settings")
                    }
                }
            } else {
                await MainActor.run {
                    self.speechAnalyzerLocales = []
                    self.isLoadingSpeechAnalyzerLocales = false
                    self.speechAnalyzerLocalesError = AppLanguage.localized("requires.macos.26.or.newer")
                }
            }
        }
    }
#else
    private func loadSpeechAnalyzerLocalesIfNeeded() {}
    private func loadSpeechAnalyzerLocales(force: Bool) {}
#endif
    
    private func localeDisplayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: AppSettings.self, inMemory: true)
}
