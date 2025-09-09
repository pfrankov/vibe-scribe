//
//  RecordDetailView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import AVFoundation
import Combine

// Detail view for a single record
struct RecordDetailView: View {
    // Use @Bindable for direct modification of @Model properties
    @Bindable var record: Record
    @Environment(\.modelContext) private var modelContext
    @Query private var appSettings: [AppSettings]
    
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isEditingSlider = false // Track if user is scrubbing
    @State private var isTranscribing = false
    @State private var transcriptionError: String? = nil
    @State private var cancellables = Set<AnyCancellable>()
    @State private var selectedTab: Tab = .summary // Default to summary tab
    @State private var isSummarizing = false // Track summarization status
    @State private var summaryError: String? = nil
    @State private var isAutomaticMode = false // Track if this is a new record that should auto-process
    
    // Processing state for the beautiful loader
    @State private var processingState: ProcessingState = .idle
    
    // SSE streaming chunks for real-time preview  
    @State private var sseStreamingChunks: [String] = [] // For UI preview (last few lines)
    @State private var sseFullText: String = "" // For accumulating full transcription text
    @State private var isSSEStreaming = false // Track if currently using SSE streaming

    // State for inline title editing - Renamed for clarity
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool
    
    // Enum for tabs
    enum Tab {
        case transcription
        case summary
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
        appSettings.first ?? AppSettings()
    }
    
    // Check if we should show content or the processing view
    private var shouldShowContent: Bool {
        switch processingState {
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
            }
            .padding(.bottom, 4)
            
            // --- Audio Player UI --- 
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    // Play/Pause Button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(playerManager.player == nil)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .help(playerManager.isPlaying ? "Pause" : "Play")
                    
                    // Time and Slider Column
                    VStack(spacing: 8) {
                        // Progress Slider
                        Slider(
                            value: $playerManager.currentTime,
                            in: 0...(playerManager.duration > 0 ? playerManager.duration : 1.0),
                            onEditingChanged: { editing in
                                isEditingSlider = editing
                                if editing {
                                    playerManager.scrubbingStarted()
                                } else {
                                    playerManager.seek(to: playerManager.currentTime)
                                }
                            }
                        )
                        .controlSize(.regular)
                        
                        // Time Label with equal space on both sides for better alignment
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .disabled(playerManager.player == nil)
            .padding(.vertical, 8)
            
            Divider()
            
            // Processing loader - always shows when processing, positioned below player
            switch processingState {
            case .transcribing, .summarizing, .streamingTranscription:
                ProcessingProgressView(state: processingState)
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
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
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
                        
                        // Transcribe Button 
                        Button {
                            startTranscription()
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
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isTranscribing || record.fileURL == nil)
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
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
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
                        
                        // Summarize Button 
                        Button {
                            startSummarization()
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
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isSummarizing || record.transcriptionText == nil || !record.hasTranscription)
                        .padding(.top, 4)
                    }
                }
            }
            
                                Spacer() // Add Spacer to push content to top
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // Fix alignment to top
        .padding(16) // More compact general padding
        .animation(.easeInOut(duration: 0.4), value: shouldShowContent)
        .onAppear {
            // Initialize processing state based on current record state
            updateProcessingState()
            
            // --- Refined File Loading Logic ---
            guard let fileURL = record.fileURL else {
                print("Error: Record '\(record.name)' has no associated fileURL.")
                return // Exit early
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Error: Audio file for record '\(record.name)' not found at path: \(fileURL.path)")
                return // Exit early
            }

            print("Loading audio from: \(fileURL.path)")
            playerManager.setupPlayer(url: fileURL)
            
            // Check if this is a new record that should auto-process
            // A record is considered "new" if it has no transcription yet
            if !record.hasTranscription && record.transcriptionText == nil {
                print("Detected new record, starting automatic pipeline for: \(record.name)")
                isAutomaticMode = true
                startAutomaticPipeline()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRecordCreated"))) { notification in
            // If this view is showing the newly created record, start automatic processing
            if let recordId = notification.userInfo?["recordId"] as? UUID,
               recordId == record.id {
                print("Received notification for new record creation: \(record.name)")
                isAutomaticMode = true
                startAutomaticPipeline()
            }
        }
        .onDisappear {
            playerManager.stopAndCleanup()
            // Cancel all subscriptions when closing window
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }
        // Detect focus changes for the title TextField
        .onChange(of: isTitleFieldFocused) { oldValue, newValue in
            if !newValue && isEditingTitle { // If focus is lost AND we were editing
                cancelEditingTitle()
            }
        }
        // Update processing state when transcription/summarization states change
        .onChange(of: isTranscribing) { oldValue, newValue in
            updateProcessingState()
        }
        .onChange(of: isSummarizing) { oldValue, newValue in
            updateProcessingState()
        }
        .onChange(of: transcriptionError) { oldValue, newValue in
            updateProcessingState()
        }
        .onChange(of: summaryError) { oldValue, newValue in
            updateProcessingState()
        }
        .onChange(of: sseStreamingChunks) { oldValue, newValue in
            updateProcessingState()
        }
        .onChange(of: isSSEStreaming) { oldValue, newValue in
            updateProcessingState()
        }
    }

    // --- Helper Functions --- 
    
    // Update processing state based on current conditions
    private func updateProcessingState() {
        print("🔄 updateProcessingState called")
        print("🔍 isTranscribing: \(isTranscribing), isSSEStreaming: \(isSSEStreaming), chunks: \(sseStreamingChunks.count)")
        
        if let error = transcriptionError ?? summaryError {
            processingState = .error(error)
            print("🚨 Set state to error: \(error)")
            
            // Switch to appropriate tab based on error type
            if transcriptionError != nil {
                selectedTab = .transcription
            } else if summaryError != nil {
                selectedTab = .summary
            }
        } else if isTranscribing {
            // Use streaming state if SSE is active and we have chunks
            if isSSEStreaming && !sseStreamingChunks.isEmpty {
                processingState = .streamingTranscription(sseStreamingChunks)
                print("🌊 Set state to streamingTranscription with \(sseStreamingChunks.count) chunks")
            } else {
                processingState = .transcribing
                print("📝 Set state to transcribing (no SSE or no chunks)")
            }
        } else if isSummarizing {
            processingState = .summarizing
            print("📋 Set state to summarizing")
        } else if isAutomaticMode && record.hasTranscription && record.summaryText == nil {
            // In automatic mode, show summarizing between transcription and summarization
            processingState = .summarizing
            print("🤖 Set state to summarizing (automatic mode)")
        } else if record.hasTranscription && record.summaryText != nil {
            processingState = .completed
            print("✅ Set state to completed")
        } else {
            processingState = .idle
            print("💤 Set state to idle")
        }
    }

    private func startEditingTitle() {
        editingTitle = record.name
        isEditingTitle = true
        // Focus immediately - SwiftUI will handle timing properly
        isTitleFieldFocused = true
        print("Started editing title for record: \(record.name)")
    }

    private func saveTitle() {
        if !editingTitle.isEmpty && editingTitle != record.name {
            print("Saving new title: \(editingTitle) for record ID: \(record.id)")
            record.name = editingTitle
        } else {
            print("Title unchanged or empty, reverting.")
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func cancelEditingTitle() {
        print("Cancelled editing title for record: \(record.name)")
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func copyTranscription() {
        if let text = record.transcriptionText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("Transcription copied to clipboard.")
        }
    }
    
    private func copySummary() {
        if let text = record.summaryText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("Summary copied to clipboard.")
        }
    }
    
    // Function to start transcription
    private func startTranscription() {
        guard let fileURL = record.fileURL, !isTranscribing else { return }
        
        isTranscribing = true
        transcriptionError = nil
        isSSEStreaming = false
        sseStreamingChunks.removeAll()
        sseFullText = ""
        
        Logger.info("Starting transcription for: \(record.name)", category: .transcription)
        Logger.debug("Using Whisper API at URL: \(settings.whisperBaseURL) with model: \(settings.whisperModel)", category: .transcription)
        
        let whisperManager = WhisperTranscriptionManager.shared
        
        // Try real-time streaming first for better UX
        whisperManager.transcribeAudioRealTime(audioURL: fileURL, settings: settings)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("✅ SSE Transcription completed successfully")
                    
                    // Save the final accumulated text from SSE full text BEFORE clearing
                    if !self.sseFullText.isEmpty {
                        print("💾 Saving final SSE transcription result: \(self.sseFullText.count) characters")
                        print("📝 Final text preview: \(self.sseFullText.prefix(100))...")
                        
                        self.record.transcriptionText = self.sseFullText
                        self.record.hasTranscription = true
                        
                        print("🔍 BEFORE SAVE - record.transcriptionText: '\(self.record.transcriptionText?.prefix(100) ?? "nil")'")
                        print("🔍 BEFORE SAVE - record.transcriptionText FULL LENGTH: \(self.record.transcriptionText?.count ?? 0)")
                        print("🔍 BEFORE SAVE - record.hasTranscription: \(self.record.hasTranscription)")
                        
                        do {
                            try self.modelContext.save()
                            print("✅ Final SSE transcription saved successfully")
                            
                            // Verify what was actually saved
                            print("🔍 AFTER SAVE - record.transcriptionText: '\(self.record.transcriptionText?.prefix(100) ?? "nil")'")
                            print("🔍 AFTER SAVE - record.transcriptionText FULL LENGTH: \(self.record.transcriptionText?.count ?? 0)")
                            print("🔍 AFTER SAVE - record.hasTranscription: \(self.record.hasTranscription)")
                        #if DEBUG
                        Logger.debug("After save: preview of transcriptionText computed property", category: .transcription)
                        #endif
                        } catch {
                            print("❌ Error saving final SSE transcription: \(error.localizedDescription)")
                            self.transcriptionError = "Error saving transcription: \(error.localizedDescription)"
                        }
                    } else {
                        print("⚠️ SSE transcription resulted in empty text")
                        self.transcriptionError = "Error: Empty transcription received from SSE. Please try again with different model or check your audio quality."
                        
                        // Still mark as having transcription attempt so UI shows properly
                        self.record.hasTranscription = true
                        self.record.transcriptionText = "" // Store empty string
                        
                        do {
                            try self.modelContext.save()
                            print("💾 Saved empty SSE transcription result with error state")
                        } catch {
                            print("❌ Error saving empty SSE transcription state: \(error.localizedDescription)")
                        }
                    }
                    
                    // Clear state AFTER saving
                    self.isTranscribing = false
                    self.isSSEStreaming = false
                    self.sseStreamingChunks.removeAll()
                    self.sseFullText = ""
                    
                    // In automatic mode, start summarization after transcription completes
                    if self.isAutomaticMode {
                        print("🔄 Automatic mode: Starting summarization after transcription completion")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startSummarization()
                        }
                    }
                case .failure(let error):
                    // Clear state on error too
                    self.isTranscribing = false
                    self.isSSEStreaming = false
                    self.sseStreamingChunks.removeAll()
                    self.sseFullText = ""
                    
                    if case .streamingNotSupported = error {
                        print("⚠️ SSE not supported, falling back to regular transcription")
                        // Fallback to regular transcription
                        self.startRegularTranscription()
                    } else {
                        self.transcriptionError = "Error: \(error.description)"
                        print("❌ SSE Transcription error: \(error.description)")
                        self.isAutomaticMode = false // Stop automatic mode on error
                    }
                }
            },
            receiveValue: { update in
                if update.isPartial {
                    print("🔄 Partial SSE update: \(update.text.prefix(50))...")
                    
                    // Mark as SSE streaming
                    self.isSSEStreaming = true
                    
                    // Clean the text
                    let cleanText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("🧹 Cleaned text length: \(cleanText.count), content: '\(cleanText.prefix(100))'")
                    
                    if !cleanText.isEmpty && cleanText.count > 5 {
                        // 1. Accumulate full text (this is what we'll save)
                        self.sseFullText += cleanText
                        print("💾 Accumulated full text: \(self.sseFullText.count) characters")
                        
                        // 2. For UI preview, extract last few words as a chunk
                        let words = cleanText.split(separator: " ")
                        let recentWords = Array(words.suffix(12)) // Last 12 words for preview
                        let chunkText = recentWords.joined(separator: " ")
                        
                        print("📝 Preview chunk text: '\(chunkText)'")
                        print("🔍 Current preview chunks count: \(self.sseStreamingChunks.count)")
                        print("🔍 Last preview chunk: '\(self.sseStreamingChunks.last ?? "none")'")
                        
                        // Add preview chunk if it's different from the last one
                        if self.sseStreamingChunks.last != chunkText {
                            self.sseStreamingChunks.append(chunkText)
                            print("✅ Added preview chunk! Total preview chunks: \(self.sseStreamingChunks.count)")
                            print("📋 All preview chunks so far: \(self.sseStreamingChunks)")
                            
                            // Limit preview chunks to prevent memory issues (keep last 10 for UI)
                            if self.sseStreamingChunks.count > 10 {
                                self.sseStreamingChunks.removeFirst()
                                print("🗑️ Removed oldest preview chunk, now have: \(self.sseStreamingChunks.count)")
                            }
                        } else {
                            print("⚠️ Preview chunk skipped - same as last one")
                        }
                    } else {
                        print("⚠️ Chunk skipped - too short or empty")
                    }
                    
                    print("🎯 isSSEStreaming: \(self.isSSEStreaming), preview chunks: \(self.sseStreamingChunks.count), full text: \(self.sseFullText.count) chars")
                } else {
                    print("✅ Final SSE transcription chunk received: \(update.text.count) characters")
                    print("📝 Final chunk preview: \(update.text.prefix(100))...")
                    
                    // This is the final chunk - it contains complete transcription
                    let cleanText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanText.isEmpty {
                        // Final chunk contains complete transcription, so replace
                        self.sseFullText = cleanText
                        print("💾 Set complete transcription from final chunk: \(self.sseFullText.count) characters")
                        
                        // Also add final preview chunk for UI
                        if cleanText.count > 5 {
                            let words = cleanText.split(separator: " ")
                            let recentWords = Array(words.suffix(12))
                            let chunkText = recentWords.joined(separator: " ")
                            
                            if self.sseStreamingChunks.last != chunkText {
                                self.sseStreamingChunks.append(chunkText)
                                print("✅ Added final preview chunk! Total preview chunks: \(self.sseStreamingChunks.count)")
                                print("📋 All preview chunks including final: \(self.sseStreamingChunks)")
                            }
                        }
                    }
                    
                    // Don't save here - let receiveCompletion handle the final save from full text
                    print("🔄 Final chunk processed, waiting for completion to save full text")
                }
            }
        )
        .store(in: &cancellables)
    }
    
    // Fallback method for regular transcription when SSE is not supported
    private func startRegularTranscription() {
        guard let fileURL = record.fileURL, !isTranscribing else { return }
        
        isTranscribing = true
        transcriptionError = nil
        
        print("🔄 Starting regular (non-streaming) transcription")
        
        let whisperManager = WhisperTranscriptionManager.shared
        
        // Use regular transcription API with settings parameter  
        whisperManager.transcribeAudio(audioURL: fileURL, settings: settings)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                self.isTranscribing = false
                
                switch completion {
                case .finished:
                    print("✅ Regular transcription completed successfully")
                    
                    // In automatic mode, start summarization after transcription completes
                    if self.isAutomaticMode {
                        print("🔄 Automatic mode: Starting summarization after transcription completion")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.startSummarization()
                        }
                    }
                case .failure(let error):
                    self.transcriptionError = "Error: \(error.description)"
                    print("❌ Regular transcription error: \(error.description)")
                    self.isAutomaticMode = false // Stop automatic mode on error
                }
            },
            receiveValue: { transcription in
                print("📝 Received regular transcription of length: \(transcription.count) characters")
                
                // Check that transcription is not empty
                if transcription.isEmpty {
                    self.transcriptionError = "Error: Empty transcription received. Please try again with different model or check your audio quality."
                    print("❌ Error: Empty transcription received")
                    
                    // Still mark as having transcription attempt so UI shows properly
                    self.record.hasTranscription = true
                    self.record.transcriptionText = "" // Store empty string
                    
                    do {
                        try self.modelContext.save()
                        print("💾 Saved empty transcription result with error state")
                    } catch {
                        print("❌ Error saving empty transcription state: \(error.localizedDescription)")
                    }
                    return
                }
                
                // Always save original result
                print("💾 Saving regular transcription result")
                
                // Save only if text is not empty
                self.record.transcriptionText = transcription
                self.record.hasTranscription = true
                do {
                    try self.modelContext.save()
                    print("✅ Regular transcription saved successfully")
                } catch {
                    print("❌ Error saving regular transcription: \(error.localizedDescription)")
                    self.transcriptionError = "Error saving transcription: \(error.localizedDescription)"
                }
            }
        )
        .store(in: &cancellables)
    }
    
    // Function to start summarization
    private func startSummarization() {
        guard let transcriptionText = record.transcriptionText, // Can be either SRT or plain text
              !transcriptionText.isEmpty,
              !isSummarizing else { return }

        print("🔍 startSummarization - raw transcriptionText length: \(transcriptionText.count)")
        print("🔍 startSummarization - raw transcriptionText preview: '\(transcriptionText.prefix(200))...'")
        print("🔍 startSummarization - raw transcriptionText suffix: '...\(transcriptionText.suffix(100))'")

        // Determine if this is SRT format or plain text and extract accordingly
        let cleanText: String
        if transcriptionText.contains("-->") && transcriptionText.contains("\n\n") {
            // This looks like SRT format - extract text from it
            print("📋 Detected SRT format, extracting clean text...")
            cleanText = WhisperTranscriptionManager.shared.extractTextFromSRT(transcriptionText)
        } else {
            // This is already plain text (from SSE streaming)
            print("📝 Detected plain text format, using as-is...")
            cleanText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("🔍 startSummarization - cleanText length: \(cleanText.count)")
        print("🔍 startSummarization - cleanText preview: '\(cleanText.prefix(200))...'")
        print("🔍 startSummarization - cleanText suffix: '...\(cleanText.suffix(100))'")

        guard !cleanText.isEmpty else {
            print("Error: Clean text is empty for record: \(record.name)")
            summaryError = "Error: Transcription text is empty after processing."
            isSummarizing = false
            isAutomaticMode = false // Stop automatic mode
            return
        }
        
        print("📊 Starting summarization with \(cleanText.count) characters of clean text")
        
        isSummarizing = true
        summaryError = nil
        
        print("Starting summarization for: \(record.name), using OpenAI compatible API at URL: \(settings.openAIBaseURL)")
        
        // Check if we should chunk the text based on settings
        if settings.useChunking {
            print("📊 Chunking enabled - splitting text (\(cleanText.count) characters) into chunks")
            let chunks = TextChunker.chunkText(cleanText, maxChunkSize: settings.chunkSize, forceChunking: false)
            print("Split text into \(chunks.count) chunks using intelligent boundaries")
            processSummaryWithChunks(chunks)
        } else {
            print("📊 Chunking disabled - processing text (\(cleanText.count) characters) as single text")
            processSummaryAsSingleText(cleanText)
            return
        }
    }
    
    // Process summary with chunking
    private func processSummaryWithChunks(_ chunks: [String]) {
        // Create array to store chunk summaries
        var chunkSummaries = [String]()
        let group = DispatchGroup()
        
        // Summarize each chunk
        for (index, chunk) in chunks.enumerated() {
            group.enter()
            
            summarizeChunk(chunk, index: index).sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Chunk \(index) summarization completed")
                    case .failure(let error):
                        print("Chunk \(index) summarization error: \(error.localizedDescription)")
                        self.summaryError = "Error summarizing chunk \(index): \(error.localizedDescription)"
                        self.isAutomaticMode = false // Stop automatic mode on error
                    }
                    group.leave()
                },
                receiveValue: { summary in
                    chunkSummaries.append(summary)
                }
            ).store(in: &cancellables)
        }
        
        // When all chunks are summarized, combine them
        group.notify(queue: .main) {
            if chunkSummaries.isEmpty {
                self.isSummarizing = false
                if self.summaryError == nil {
                    self.summaryError = "Failed to generate chunk summaries"
                }
                self.isAutomaticMode = false // Stop automatic mode on error
                return
            }
            
            // If there's only one chunk, use it as the final summary
            if chunkSummaries.count == 1 {
                self.record.summaryText = chunkSummaries[0]
                try? self.modelContext.save()
                self.isSummarizing = false
                
                // In automatic mode, switch to summary tab after completion
                if self.isAutomaticMode {
                    print("Automatic mode: Switching to summary tab after completion")
                    self.isAutomaticMode = false // Reset automatic mode
                }
                return
            }
            
            // If there are multiple chunks, combine them
            self.combineSummaries(chunkSummaries).sink(
                receiveCompletion: { completion in
                    self.isSummarizing = false
                    switch completion {
                    case .finished:
                        print("Combined summary completed")
                    case .failure(let error):
                        print("Combined summary error: \(error.localizedDescription)")
                        self.summaryError = "Error combining summaries: \(error.localizedDescription)"
                        self.isAutomaticMode = false // Stop automatic mode on error
                    }
                },
                receiveValue: { finalSummary in
                    self.record.summaryText = finalSummary
                    try? self.modelContext.save()
                    
                    // In automatic mode, switch to summary tab after completion
                    if self.isAutomaticMode {
                        print("Automatic mode: Switching to summary tab after combined summary completion")
                        self.isAutomaticMode = false // Reset automatic mode
                    }
                }
            ).store(in: &self.cancellables)
        }
    }
    
    // Process summary as single text (no chunking)
    private func processSummaryAsSingleText(_ text: String) {
        // Use the summary prompt directly for single text
        let prompt = settings.chunkPrompt.replacingOccurrences(of: "{transcription}", with: text)
        
        callOpenAIAPI(prompt: prompt, url: settings.openAIBaseURL).sink(
            receiveCompletion: { completion in
                isSummarizing = false
                switch completion {
                case .finished:
                    print("Single text summarization completed successfully")
                    if isAutomaticMode {
                        print("Automatic mode: Switching to summary tab after single text completion")
                        isAutomaticMode = false
                    }
                case .failure(let error):
                    summaryError = "Error: \(error.localizedDescription)"
                    print("Single text summarization failed: \(error.localizedDescription)")
                    isAutomaticMode = false
                }
            },
            receiveValue: { summary in
                record.summaryText = summary
                // Note: hasSummary is automatically set when summaryText is assigned
                do {
                    try modelContext.save()
                    print("Single text summary saved successfully")
                } catch {
                    summaryError = "Error saving summary: \(error.localizedDescription)"
                    print("Error saving single text summary: \(error.localizedDescription)")
                }
            }
        ).store(in: &cancellables)
    }
    
    // Summarize one chunk
    private func summarizeChunk(_ chunk: String, index: Int) -> AnyPublisher<String, Error> {
        let prompt = settings.chunkPrompt.replacingOccurrences(of: "{transcription}", with: chunk)
        
        return callOpenAIAPI(
            prompt: prompt,
            url: settings.openAIBaseURL
        )
    }
    
    // Combine chunk summaries
    private func combineSummaries(_ summaries: [String]) -> AnyPublisher<String, Error> {
        let combinedSummaries = summaries.joined(separator: "\n\n")
        let prompt = settings.summaryPrompt.replacingOccurrences(of: "{transcription}", with: combinedSummaries)
        
        return callOpenAIAPI(
            prompt: prompt,
            url: settings.openAIBaseURL
        )
    }
    
    // Call OpenAI-compatible API
    private func callOpenAIAPI(prompt: String, url: String) -> AnyPublisher<String, Error> {
        return Future<String, Error> { promise in
            // Form complete URL
            guard let url = APIURLBuilder.buildURL(baseURL: url, endpoint: "chat/completions") else {
                promise(.failure(NSError(domain: "Invalid URL", code: -1)))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 0  // No timeout for LLM requests
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add API Key if provided
            let maskedAPIKey = settings.openAIAPIKey.isEmpty ? "None" : SecurityUtils.maskAPIKey(settings.openAIAPIKey)
            if !settings.openAIAPIKey.isEmpty {
                request.setValue("Bearer \(settings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
            }
            
            // Form request body
            let requestBody: [String: Any] = [
                "model": settings.openAIModel,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
            
            // 🚀 LOG FULL REQUEST DETAILS
            Logger.info("🤖 LLM API Request Details:", category: .llm)
            Logger.info("📍 Endpoint: \(url.absoluteString)", category: .llm)
            Logger.info("🔑 API Key: \(maskedAPIKey)", category: .llm) 
            Logger.info("🧠 Model: \(settings.openAIModel)", category: .llm)
            Logger.info("📜 User Prompt (Length: \(prompt.count) chars):", category: .llm)
            Logger.info("═══════════════════════════════════════", category: .llm)
            Logger.info(prompt, category: .llm)
            Logger.info("═══════════════════════════════════════", category: .llm)
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                promise(.failure(error))
                return
            }
            
            // Send request with custom session that has no timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 0
            config.timeoutIntervalForResource = 0
            let session = URLSession(configuration: config)
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.error("❌ LLM API Network Error: \(error.localizedDescription)", category: .llm)
                    promise(.failure(error))
                    return
                }
                
                // Log HTTP response details
                if let httpResponse = response as? HTTPURLResponse {
                    Logger.info("📡 LLM API HTTP Response Status: \(httpResponse.statusCode)", category: .llm)
                    if httpResponse.statusCode >= 400 {
                        Logger.error("❌ LLM API HTTP Error: \(httpResponse.statusCode)", category: .llm)
                    }
                }
                
                guard let data = data else {
                    Logger.error("❌ No data received from LLM API", category: .llm)
                    promise(.failure(NSError(domain: "No data received", code: -1)))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        // 🚀 LOG RESPONSE DETAILS
                        Logger.info("✅ LLM API Response received:", category: .llm)
                        Logger.info("📊 Response Length: \(content.count) chars", category: .llm)
                        Logger.info("📝 Response Content:", category: .llm)
                        Logger.info("═══════════════════════════════════════", category: .llm)
                        Logger.info(content, category: .llm)
                        Logger.info("═══════════════════════════════════════", category: .llm)
                        
                        // Log usage info if available
                        if let usage = json["usage"] as? [String: Any] {
                            let promptTokens = usage["prompt_tokens"] as? Int ?? 0
                            let completionTokens = usage["completion_tokens"] as? Int ?? 0
                            let totalTokens = usage["total_tokens"] as? Int ?? 0
                            Logger.info("📈 Token Usage - Prompt: \(promptTokens), Completion: \(completionTokens), Total: \(totalTokens)", category: .llm)
                        }
                        
                        promise(.success(content))
                    } else {
                        let jsonStr = String(data: data, encoding: .utf8) ?? "Invalid UTF-8 data"
                        Logger.error("❌ LLM API unexpected response format:", category: .llm)
                        Logger.error("Raw response: \(jsonStr)", category: .llm)
                        promise(.failure(NSError(domain: "Invalid response format", code: -1)))
                    }
                } catch {
                    Logger.error("❌ LLM API JSON parsing error: \(error.localizedDescription)", category: .llm)
                    if let jsonStr = String(data: data, encoding: .utf8) {
                        Logger.error("Raw response: \(jsonStr)", category: .llm)
                    }
                    promise(.failure(error))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }
    
    // Function to start automatic pipeline
    private func startAutomaticPipeline() {
        guard isAutomaticMode else { return }
        
        print("Starting automatic pipeline for record: \(record.name)")
        
        // Start transcription first
        startTranscription()
    }
} 
