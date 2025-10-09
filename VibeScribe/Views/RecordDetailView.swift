//
//  RecordDetailView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// Detail view for a single record
struct RecordDetailView: View {
    
    init(record: Record, isSidebarCollapsed: Bool = false, onRecordDeleted: ((UUID) -> Void)? = nil) {
        self.record = record
        self.isSidebarCollapsed = isSidebarCollapsed
        self.onRecordDeleted = onRecordDeleted
    }

    // Use @Bindable for direct modification of @Model properties
    @Bindable var record: Record
    var onRecordDeleted: ((UUID) -> Void)? = nil
    var isSidebarCollapsed: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Query private var appSettings: [AppSettings]
    
    @StateObject private var playerManager = AudioPlayerManager()
    @ObservedObject private var modelService = ModelService.shared
    @ObservedObject private var processingManager = RecordProcessingManager.shared
    @State private var selectedTab: Tab = .summary // Default to summary tab
    @State private var isAutomaticMode = false // Track if this is a new record that should auto-process

    @State private var selectedWhisperModel: String = ""
    @State private var selectedSummaryModel: String = ""

    // State for inline title editing - Renamed for clarity
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool

    // Action menu state
    @State private var isShowingDeleteConfirmation = false
    @State private var isDownloading = false
    // Layout constants for the audio controls
    private let speedControlColumnWidth: CGFloat = 68
    private let speedControlColumnSpacing: CGFloat = 12
    private let controlRowHeight: CGFloat = 28
    @State private var spaceKeyMonitor: Any?

    // Removed tuning controls (auto-optimized waveform)

    // tuning panel removed

    // Extract heavy player UI into a computed property to help type-checker
    private var playerControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Rewind Button (10 seconds back)
                Button {
                    playerManager.skipBackward(10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(playerManager.isPlaying ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isPlaying)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .help("Skip back 10 seconds")

                // Play/Pause Button
                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isReady)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .help(playerManager.isPlaying ? "Pause" : "Play")

                // Forward Button (10 seconds forward)
                Button {
                    playerManager.skipForward(10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(playerManager.isPlaying ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!playerManager.isPlaying)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .help("Skip forward 10 seconds")

                // Spacing between controls and time/slider
                Spacer().frame(width: 12)

                // Time and Slider Column
                VStack(spacing: 2) {
                    Color.clear.frame(height: 12)

                    HStack(spacing: speedControlColumnSpacing) {
                        WaveformScrubberView(
                            progress: Binding(
                                get: { playerManager.playbackProgress },
                                set: { playerManager.previewScrubProgress($0) }
                            ),
                            samples: playerManager.waveformSamples,
                            duration: playerManager.duration,
                            isEnabled: playerManager.isReady && playerManager.duration > 0,
                            onScrubStart: { if playerManager.isReady { playerManager.scrubbingStarted() } },
                            onScrubEnd: { ratio in
                                if playerManager.isReady { playerManager.seek(toProgress: ratio) }
                            }
                        )
                        .frame(maxWidth: .infinity)

                        Color.clear.frame(width: speedControlColumnWidth, height: controlRowHeight)
                    }

                    HStack {
                        Text(playerManager.currentTime.clockString)
                            .font(.caption)
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .monospacedDigit()
                        Spacer()
                        Text(playerManager.duration.clockString)
                            .font(.caption)
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .monospacedDigit()
                    }
                    .padding(.trailing, speedControlColumnWidth + speedControlColumnSpacing)
                }
                .overlay(alignment: .trailing) {
                    Button { playerManager.cyclePlaybackSpeed() } label: {
                        Text("\(playerManager.playbackSpeed, format: .number.precision(.fractionLength(0...2)))×")
                            .font(.title3.weight(.semibold))
                            .frame(width: speedControlColumnWidth, height: controlRowHeight, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerManager.isReady)
                    .help("Playback Speed")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // tuning panel removed
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .disabled(!playerManager.isReady)
        .padding(.vertical, 4)
    }

    // Enum for tabs
    enum Tab {
        case transcription
        case summary
        
        var logName: String {
            switch self {
            case .transcription:
                return "Transcription"
            case .summary:
                return "Summary"
            }
        }
    }
    
    // Computed property for transcription text for easier access
    private var transcriptionText: String {
        if let text = record.transcriptionText, !text.isEmpty {
            return text
        } else if record.hasTranscription && record.transcriptionText != nil {
            // Transcription attempt finished but text is empty
            return "Transcription resulted in empty text. Try again with a different model or check audio quality."
        } else if record.hasTranscription {
            return "Transcription processing... Check back later."
        } else {
            return "Transcription not available yet."
        }
    }
    
    // Get current settings
    private var settings: AppSettings {
        if let existingSettings = appSettings.first {
            return existingSettings
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }

    private var whisperModelOptions: [String] {
        if modelService.whisperModels.isEmpty,
           !settings.whisperModel.isEmpty,
           !modelService.whisperModels.contains(settings.whisperModel) {
            return [settings.whisperModel]
        }
        return modelService.whisperModels
    }

    private var processingStatus: RecordProcessingManager.RecordProcessingState {
        processingManager.state(for: record.id)
    }

    private var transcriptionError: String? {
        processingStatus.transcriptionError
    }

    private var summaryError: String? {
        processingStatus.summaryError
    }

    private var isTranscribing: Bool {
        processingStatus.isTranscribing || processingStatus.pendingTranscriptionCount > 0
    }

    private var isSummarizing: Bool {
        processingStatus.isSummarizing || processingStatus.pendingSummarizationCount > 0
    }

    private var isStreaming: Bool {
        processingStatus.isStreaming
    }

    private var streamingChunks: [String] {
        processingStatus.streamingChunks
    }

    private var currentProcessingState: ProcessingState {
        if let error = transcriptionError ?? summaryError {
            return .error(error)
        } else if isStreaming {
            return .streamingTranscription(streamingChunks)
        } else if processingStatus.isTranscribing || processingStatus.pendingTranscriptionCount > 0 {
            return .transcribing
        } else if processingStatus.isSummarizing || processingStatus.pendingSummarizationCount > 0 {
            return .summarizing
        } else if record.summaryText != nil || (record.transcriptionText != nil && record.hasTranscription) {
            return .completed
        } else {
            return .idle
        }
    }

    private func requestTranscription(from origin: Tab) {
        Logger.debug("User requested transcription from \(origin.logName) tab for record \(record.name)", category: .ui)
        isAutomaticMode = false
        processingManager.enqueueTranscription(
            for: record,
            in: modelContext,
            settings: settings,
            automatic: false,
            preferStreaming: true
        )
    }
    
    private func requestSummarization(from origin: Tab) {
        Logger.debug("User requested summarization from \(origin.logName) tab for record \(record.name)", category: .ui)
        isAutomaticMode = false
        processingManager.enqueueSummarization(
            for: record,
            in: modelContext,
            settings: settings,
            automatic: false
        )
    }
    
    private var summaryModelOptions: [String] {
        if modelService.openAIModels.isEmpty,
           !settings.openAIModel.isEmpty,
           !modelService.openAIModels.contains(settings.openAIModel) {
            return [settings.openAIModel]
        }
        return modelService.openAIModels
    }

    private func updateSettings(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, String>,
        with newValue: String,
        settingName: String
    ) {
        let normalizedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSettings = settings

        guard currentSettings[keyPath: keyPath] != normalizedValue else { return }

        currentSettings[keyPath: keyPath] = normalizedValue

        do {
            try modelContext.save()
            Logger.debug("Updated \(settingName) to: \(normalizedValue)", category: .ui)
        } catch {
            Logger.error("Failed to save updated setting: \(error.localizedDescription)", category: .ui)
        }
    }

    // Check if we should show content or the processing view
    private var shouldShowContent: Bool {
        switch currentProcessingState {
        case .completed:
            return true
        case .error:
            return true // Show content on error so user can see retry buttons
        case .idle:
            // Always show content in idle state so user can try transcription
            // This allows users to retry even if previous transcription was empty
            return true
        case .transcribing, .summarizing, .streamingTranscription:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { // Reduce base spacing
            // Header with Title (now editable) and Close button
            HStack {
                ZStack(alignment: .leading) {
                    // --- TextField (Visible when editing title) ---
                    TextField("Name", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .focused($isTitleFieldFocused)
                        .onSubmit { saveTitle() }
                        .font(.title2.bold())
                        .opacity(isEditingTitle ? 1 : 0)
                        .disabled(!isEditingTitle)
                        .onTapGesture {}

                    // --- Text (Visible when not editing title) ---
                    Text(record.name)
                        .font(.title2.bold())
                        .opacity(isEditingTitle ? 0 : 1)
                        .onTapGesture(count: 2) {
                            startEditingTitle()
                        }
                }
                Spacer()

                Menu {
                    Button {
                        triggerDownload()
                    } label: {
                        Label("Download Audio", systemImage: "arrow.down.to.line")
                    }
                    .disabled(record.fileURL == nil || isDownloading)

                    Button {
                        startEditingTitle()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .disabled(isEditingTitle)

                    Divider()

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.9)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 28, height: 28)
            }
            .padding(.bottom, 4)
            
           // --- Audio Player UI ---
           playerControls

            Divider()
            
            // Processing loader - always shows when processing, positioned below player
            switch currentProcessingState {
            case .transcribing, .summarizing, .streamingTranscription:
                ProcessingProgressView(state: currentProcessingState)
                    .padding(.top, 8)
            default:
                EmptyView()
            }
            
            // Show tabs only when everything is completed
            if shouldShowContent {
                // Tab picker - properly centered segmented control following macOS HIG
                Picker("", selection: $selectedTab) {
                    Text("Transcription").tag(Tab.transcription)
                    Text("Summary").tag(Tab.summary)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300) // Limit width for better appearance
                .frame(maxWidth: .infinity, alignment: .center) // Center in the container
                .padding(.vertical, 8)
                
                // Tab content
                if selectedTab == .transcription {
                    // Transcription Tab Content
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Spacer()
                            Button {
                                copyTranscription()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Transcription")
                            .disabled(!record.hasTranscription || record.transcriptionText == nil)
                        }
                        
                        // Show error if exists
                        if let error = transcriptionError {
                            InlineMessageView(error)
                                .padding(.bottom, 4)
                        }
                        
                        // ScrollView for transcription
                        ScrollView {
                            Text(transcriptionText)
                                .font(.body)
                                .foregroundStyle(record.hasTranscription && record.transcriptionText != nil ? 
                                                Color(NSColor.labelColor) : 
                                                Color(NSColor.secondaryLabelColor))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.iBeam.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .padding(12)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(6)
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Transcribe Controls
                        HStack(spacing: 12) {
                            ComboBoxView(
                                placeholder: whisperModelOptions.isEmpty ? "Select transcription model" : "Choose model",
                                options: whisperModelOptions,
                                selectedOption: $selectedWhisperModel
                            )
                            .frame(width: 220, height: 32)

                            Button {
                                requestTranscription(from: .transcription)
                            } label: {
                                HStack {
                                    if isTranscribing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "waveform")
                                    }
                                    Text("Transcribe")
                                }
                                .frame(minWidth: 130)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isTranscribing || record.fileURL == nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                    }
                } else {
                    // Summary Tab Content
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Spacer()
                            Button {
                                copySummary()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Summary")
                            .disabled(record.summaryText == nil)
                        }
                        
                        // Show error if exists
                        if let error = summaryError {
                            InlineMessageView(error)
                                .padding(.bottom, 4)
                        }
                        
                        // ScrollView for summary
                        ScrollView {
                            if let summaryText = record.summaryText, !summaryText.isEmpty {
                                Text(summaryText)
                                    .font(.body)
                                    .foregroundStyle(Color(NSColor.labelColor))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.iBeam.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                            } else {
                                Text("No summary available yet.")
                                    .font(.body)
                                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Summarize Controls
                        HStack(spacing: 12) {
                            ComboBoxView(
                                placeholder: summaryModelOptions.isEmpty ? "Select summary model" : "Choose model",
                                options: summaryModelOptions,
                                selectedOption: $selectedSummaryModel
                            )
                            .frame(width: 220, height: 32)

                            Button {
                                requestSummarization(from: .summary)
                            } label: {
                                HStack {
                                    if isSummarizing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "doc.text.magnifyingglass")
                                    }
                                    Text("Summarize")
                                }
                                .frame(minWidth: 130)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isSummarizing || record.transcriptionText == nil || !record.hasTranscription)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                    }
                }
            }
            
                                Spacer() // Add Spacer to push content to top
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // Fix alignment to top
        .padding(.horizontal, 16) // Keep sides consistent
        .padding(.top, isSidebarCollapsed ? 16 : 0) // Dynamic top padding: 0 when sidebar is visible, original when collapsed
        .animation(.easeInOut(duration: 0.25), value: isSidebarCollapsed)
        .animation(.easeInOut(duration: 0.4), value: shouldShowContent)
        .onAppear {
            selectedWhisperModel = settings.whisperModel
            selectedSummaryModel = settings.openAIModel

            // Initialize processing state based on current record state
            // --- Refined File Loading Logic ---
            guard let fileURL = record.fileURL else {
                Logger.error("Record '\(record.name)' has no associated fileURL.", category: .ui)
                return // Exit early
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Logger.error("Audio file for record '\(record.name)' not found at path: \(fileURL.path)", category: .audio)
                return // Exit early
            }

            Logger.debug("Loading audio from: \(fileURL.path)", category: .audio)
            playerManager.setupPlayer(url: fileURL)
            registerSpacebarShortcut()

            // Check if this is a new record that should auto-process
            // A record is considered "new" if it has no transcription yet
            if !record.hasTranscription && record.transcriptionText == nil {
                Logger.debug("Detected new record, starting automatic pipeline for: \(record.name)", category: .ui)
                isAutomaticMode = true
                startAutomaticPipeline()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRecordCreated"))) { notification in
            // If this view is showing the newly created record, start automatic processing
            if let recordId = notification.userInfo?["recordId"] as? UUID,
               recordId == record.id {
                Logger.debug("Received notification for new record creation: \(record.name)", category: .ui)
                isAutomaticMode = true
                startAutomaticPipeline()
            }
        }
        .onDisappear {
            unregisterSpacebarShortcut()
            playerManager.stopAndCleanup()
        }
        // Detect focus changes for the title TextField
        .onChange(of: isTitleFieldFocused) { oldValue, newValue in
            if !newValue && isEditingTitle { // If focus is lost AND we were editing
                cancelEditingTitle()
            }
        }
        .onChange(of: selectedWhisperModel) { _, newValue in
            updateSettings(\.whisperModel, with: newValue, settingName: "Whisper model")
        }
        .onChange(of: selectedSummaryModel) { _, newValue in
            updateSettings(\.openAIModel, with: newValue, settingName: "Summary model")
        }
        .onChange(of: appSettings.first?.whisperModel ?? "") { _, newValue in
            if newValue != selectedWhisperModel {
                selectedWhisperModel = newValue
            }
        }
        .onChange(of: appSettings.first?.openAIModel ?? "") { _, newValue in
            if newValue != selectedSummaryModel {
                selectedSummaryModel = newValue
            }
        }
        .onReceive(processingManager.$recordStates) { _ in
            handleProcessingStateChange()
        }
        .onChange(of: record.summaryText ?? "") { _, newValue in
            if isAutomaticMode && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedTab = .summary
                isAutomaticMode = false
            }
        }
        .alert("Delete Recording?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteCurrentRecord()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the recording, transcription, and summary. This action cannot be undone.")
        }
    }

    // MARK: - Keyboard Handling

    private func registerSpacebarShortcut() {
        guard spaceKeyMonitor == nil else { return }

        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard shouldHandleSpacebar(event: event) else { return event }

            playerManager.togglePlayPause()
            return nil
        }
    }

    private func unregisterSpacebarShortcut() {
        if let monitor = spaceKeyMonitor {
            NSEvent.removeMonitor(monitor)
            spaceKeyMonitor = nil
        }
    }

    private func shouldHandleSpacebar(event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }

        guard let window = event.window ?? NSApp.keyWindow, window.isKeyWindow else { return false }
        if window.isSheet { return false }
        if let mainWindow = (NSApplication.shared.delegate as? AppDelegate)?.mainWindow,
           window != mainWindow {
            return false
        }

        guard playerManager.isReady else { return false }
        guard !isEditingTitle else { return false }
        guard !isTextInputActive(in: window) else { return false }
        return true
    }

    private func isTextInputActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }

        if let textView = responder as? NSTextView {
            if textView.isEditable || textView.isFieldEditor { return true }
        }

        if responder is NSTextField { return true }

        if let view = responder as? NSView,
           let fieldEditor = window.fieldEditor(false, for: nil),
           fieldEditor === view {
            return true
        }

        if responder.conforms(to: NSTextInputClient.self) {
            return true
        }

        return false
    }

    // --- Helper Functions ---
    
    private func startEditingTitle() {
        editingTitle = record.name
        isEditingTitle = true
        // Focus immediately - SwiftUI will handle timing properly
        isTitleFieldFocused = true
        Logger.debug("Started editing title for record: \(record.name)", category: .ui)
    }

    private func saveTitle() {
        if !editingTitle.isEmpty && editingTitle != record.name {
            Logger.debug("Saving new title: \(editingTitle) for record ID: \(record.id)", category: .ui)
            record.name = editingTitle
        } else {
            Logger.debug("Title unchanged or empty, reverting.", category: .ui)
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func cancelEditingTitle() {
        Logger.debug("Cancelled editing title for record: \(record.name)", category: .ui)
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func copyTranscription() {
        if let text = record.transcriptionText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            Logger.info("Transcription copied to clipboard.", category: .ui)
        }
    }

    private func copySummary() {
        if let text = record.summaryText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            Logger.info("Summary copied to clipboard.", category: .ui)
        }
    }

    @MainActor
    private func triggerDownload() {
        guard !isDownloading else { return }
        guard let sourceURL = record.fileURL else {
            Logger.warning("Attempted to export record without file URL", category: .audio)
            presentAlert(title: "Export Unavailable", message: "The original audio file could not be located.", style: .warning)
            return
        }

        Task { await exportRecording(from: sourceURL, suggestedName: record.name) }
    }

    @MainActor
    private func exportRecording(from sourceURL: URL, suggestedName: String) async {
        isDownloading = true
        defer { isDownloading = false }

        do {
            guard let destinationURL = await presentSavePanel(suggestedName: suggestedName) else {
                Logger.info("User cancelled save panel for export", category: .audio)
                return
            }

            let convertedURL = try await createTemporaryM4A(from: sourceURL)
            try persistConvertedFile(at: convertedURL, to: destinationURL)

            presentAlert(
                title: "Audio Exported",
                message: "Recording saved to \(destinationURL.path)",
                style: .informational
            )
        } catch {
            Logger.error("Failed to export recording", error: error, category: .audio)
            presentAlert(
                title: "Export Failed",
                message: error.localizedDescription,
                style: .critical
            )
        }
    }

    private func createTemporaryM4A(from inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioUtilsError.exportFailed("Unable to create export session")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.audioTimePitchAlgorithm = .timeDomain
        exportSession.shouldOptimizeForNetworkUse = false

        try await exportSession.export(to: tempURL, as: .m4a)
        return tempURL
    }

    @MainActor
    private func presentSavePanel(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName(for: suggestedName)
        panel.allowedContentTypes = [UTType.mpeg4Audio]
        panel.isExtensionHidden = false

        return await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }

            if let window = NSApplication.shared.mainWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    private func persistConvertedFile(at tempURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        try fileManager.copyItem(at: tempURL, to: destinationURL)
        Logger.info("Recording exported to \(destinationURL.path)", category: .audio)
    }

    private func defaultFileName(for baseName: String) -> String {
        let sanitized = baseName
            .components(separatedBy: CharacterSet(charactersIn: "\\/:?\"<>|"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fileName = sanitized.isEmpty ? "Recording" : sanitized
        return fileName.lowercased().hasSuffix(".m4a") ? fileName : "\(fileName).m4a"
    }

    @MainActor
    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = NSApplication.shared.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    @MainActor
    private func deleteCurrentRecord() {
        playerManager.stopAndCleanup()

        let recordId = record.id
        if let fileURL = record.fileURL {
            do {
                try FileManager.default.removeItem(at: fileURL)
                Logger.info("Deleted audio file at \(fileURL.path)", category: .audio)
            } catch {
                Logger.error("Failed to delete audio file", error: error, category: .audio)
            }
        } else {
            Logger.warning("Deleting record without associated file URL", category: .audio)
        }

        modelContext.delete(record)

        do {
            try modelContext.save()
            Logger.info("Record \(recordId) deleted", category: .general)
            onRecordDeleted?(recordId)
        } catch {
            Logger.error("Failed to delete record", error: error, category: .general)
            presentAlert(
                title: "Deletion Failed",
                message: error.localizedDescription,
                style: .critical
            )
        }
    }
    
    // Function to start automatic pipeline
    private func startAutomaticPipeline() {
        guard isAutomaticMode else { return }
        
        Logger.debug("Starting automatic pipeline for record: \(record.name)", category: .transcription)
        processingManager.enqueueTranscription(
            for: record,
            in: modelContext,
            settings: settings,
            automatic: true,
            preferStreaming: true
        )
    }
    
    private func handleProcessingStateChange() {
        let state = processingStatus
        
        if let error = state.transcriptionError, !error.isEmpty {
            selectedTab = .transcription
            isAutomaticMode = false
        } else if let error = state.summaryError, !error.isEmpty {
            selectedTab = .summary
            isAutomaticMode = false
        }
    }
}

