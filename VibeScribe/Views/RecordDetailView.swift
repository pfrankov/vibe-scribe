//
//  RecordDetailView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import MarkdownUI
import SwiftData
import AVFoundation
import AppKit
import UniformTypeIdentifiers
#if canImport(Speech)
import Speech
#endif

// Detail view for a single record
struct RecordDetailView: View {
    
    init(
        record: Record,
        isSidebarCollapsed: Bool = false,
        onRecordDeleted: ((UUID) -> Void)? = nil,
        onTagTapped: ((Tag) -> Void)? = nil
    ) {
        self.record = record
        self.isSidebarCollapsed = isSidebarCollapsed
        self.onRecordDeleted = onRecordDeleted
        self.onTagTapped = onTagTapped
        _transcriptionDraft = State(initialValue: record.transcriptionText ?? "")
        _summaryDraft = State(initialValue: record.summaryText ?? "")
    }

    // Use @Bindable for direct modification of @Model properties
    @Bindable var record: Record
    var onRecordDeleted: ((UUID) -> Void)? = nil
    var onTagTapped: ((Tag) -> Void)? = nil
    var isSidebarCollapsed: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var appSettings: [AppSettings]
    @Query(sort: [SortDescriptor(\Tag.name)]) private var availableTags: [Tag]

    @StateObject private var playerManager = AudioPlayerManager()
    @ObservedObject private var modelService = ModelService.shared
    @ObservedObject private var processingManager = RecordProcessingManager.shared
    @State private var selectedTab: Tab = .summary // Default to summary tab
    @State private var isAutomaticMode = false // Track if this is a new record that should auto-process

    @State private var selectedWhisperModel: String = ""
    @State private var selectedSummaryModel: String = ""
    @State private var selectedSpeechAnalyzerLocale: String = ""
    @State private var speechAnalyzerLocales: [Locale] = []

    @State private var transcriptionDraft: String
    @State private var summaryDraft: String
    @State private var summaryMarkdownContent: MarkdownContent?
    @State private var renderedSummarySnapshot: String = ""
    @State private var isSummaryEditing: Bool = false
    @State private var transcriptionSaveWorkItem: DispatchWorkItem?
    @State private var summarySaveWorkItem: DispatchWorkItem?

    // State for inline title editing - Renamed for clarity
    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @FocusState private var isTitleFieldFocused: Bool
    @FocusState private var focusedEditor: ActiveEditor?
    @FocusState private var isTagFieldFocused: Bool

    @State private var tagInput: String = ""
    @State private var highlightedSuggestionID: Tag.ID?
    
    @State private var showTranscriptionCopied: Bool = false
    @State private var showSummaryCopied: Bool = false

    private let tagManager = TagManager.shared

    // Action menu state
    @State private var isShowingDeleteConfirmation = false
    @State private var isDownloading = false
    // Layout constants for the audio controls
    private let speedControlColumnWidth: CGFloat = 68
    private let speedControlColumnSpacing: CGFloat = 12
    private let controlRowHeight: CGFloat = 28
    private let inlineSaveDebounceInterval: TimeInterval = 0.75
    private let copiedIndicationDuration: TimeInterval = 2.0
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
                        .foregroundStyle(Color.secondary)
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
                        .foregroundStyle(Color.primary)
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
                        .foregroundStyle(Color.secondary)
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

    // Enum to keep track of focused text editor
    private enum ActiveEditor: Hashable {
        case transcription
        case summary
    }
    
    // Reusable copy button component
    private struct CopyButton: View {
        let onCopy: () -> Void
        let showCopied: Bool
        
        var body: some View {
            Button(action: onCopy) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(showCopied ? .green : .primary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(showCopied ? "Copied!" : "Copy to clipboard")
        }
    }

    // Reusable inline editor to keep body lightweight for type-checker
    private struct InlineEditableTextArea: View {
        @Binding var text: String
        var placeholder: String
        var statusMessage: String?
        var focusBinding: FocusState<ActiveEditor?>.Binding
        var editor: ActiveEditor
        var onExit: (() -> Void)? = nil
        var onCopy: (() -> Void)? = nil
        var showCopied: Bool = false

        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))

                TextEditor(text: $text)
                    .font(.body)
                    .focused(focusBinding, equals: editor)
                    .disableAutocorrection(true)
                    .background(Color.clear)
                    .padding(8)
                    .padding(.trailing, 36) // Make room for copy button
                    .onExitCommand {
                        onExit?()
                    }

                if text.isEmpty {
                    Text(statusMessage ?? placeholder)
                        .font(.body)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                
                // Copy button overlay
                if !text.isEmpty, let copyAction = onCopy {
                    VStack {
                        HStack {
                            Spacer()
                            CopyButton(onCopy: copyAction, showCopied: showCopied)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
            )
            .frame(maxHeight: .infinity)
        }
    }

    private struct MarkdownSummaryPreview: View {
        var markdownContent: MarkdownContent?
        var plainText: String
        var placeholder: String
        var onActivateEditing: () -> Void
        var onCopy: (() -> Void)? = nil
        var showCopied: Bool = false

        private var trimmedText: String {
            plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            let preview = ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))

                ScrollView(.vertical) {
                    Group {
                        if let content = markdownContent {
                            Markdown(content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !trimmedText.isEmpty {
                            Markdown(plainText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(placeholder)
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(8)
                .padding(.trailing, 36) // Make room for copy button
                
                // Copy button overlay
                if !trimmedText.isEmpty, let copyAction = onCopy {
                    VStack {
                        HStack {
                            Spacer()
                            CopyButton(onCopy: copyAction, showCopied: showCopied)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
            )
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 6))

            return preview.modifier(SummaryPreviewActivationModifier(onActivateEditing: onActivateEditing))
        }
    }

    private struct DoubleClickCatchingView: NSViewRepresentable {
        var onDoubleClick: () -> Void

        final class Coordinator: NSObject, NSGestureRecognizerDelegate {
            let onDoubleClick: () -> Void

            init(onDoubleClick: @escaping () -> Void) {
                self.onDoubleClick = onDoubleClick
            }

            @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
                guard recognizer.state == .ended else { return }
                onDoubleClick()
            }

            func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
                true
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onDoubleClick: onDoubleClick)
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = false
            let gesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
            gesture.numberOfClicksRequired = 2
            gesture.delaysPrimaryMouseButtonEvents = false
            gesture.buttonMask = 0x1
            gesture.delegate = context.coordinator
            view.addGestureRecognizer(gesture)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let gesture = nsView.gestureRecognizers.first(where: { $0 is NSClickGestureRecognizer }) as? NSClickGestureRecognizer else {
                return
            }
            gesture.numberOfClicksRequired = 2
            gesture.delaysPrimaryMouseButtonEvents = false
            gesture.buttonMask = 0x1
        }
    }

    private struct SummaryPreviewActivationModifier: ViewModifier {
        var onActivateEditing: () -> Void

        func body(content: Content) -> some View {
            content
                .background(DoubleClickCatchingView(onDoubleClick: onActivateEditing))
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded(onActivateEditing)
                )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            tagsSection
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(record.sortedTags) { tag in
                    tagChip(for: tag)
                }

                tagInputField
            }
            .animation(.easeInOut(duration: 0.18), value: record.tags.count)
        }
        .padding(.bottom, tagSuggestionBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagChip(for tag: Tag) -> some View {
        HStack(spacing: 8) {
            // Make the tag label interactive via a Button so it is keyboard-focusable and accessible.
            Button(action: { onTagTapped?(tag) }) {
                Text(tag.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Filter by \(tag.name)")
            .accessibilityLabel("Filter recordings by \(tag.name)")

            // Keep remove as a separate plain button to avoid nesting buttons.
            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Remove tag")
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tagChipBackgroundColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tagChipBorderColor, lineWidth: 1)
        )
        .foregroundStyle(Color.accentColor)
        .shadow(color: tagChipShadowColor, radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(tag.name)")
    }

    private var tagInputField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 16, height: 16)
                .foregroundStyle(tagInputIconColor)

            TagComboBoxView(
                placeholder: "Add tag",
                options: availableTagNamesExcludingAssigned,
                usageCounts: tagUsageCounts,
                initialMinWidth: 72,
                trailingGap: 20,
                text: $tagInput,
                onCommit: { selected in
                    if let name = selected {
                        return commitTagByName(name)
                    } else {
                        return commitTagInput()
                    }
                },
                onFocusChange: { isFocused in
                    isTagFieldFocused = isFocused
                }
            )
            .frame(minWidth: 72, alignment: .leading)
            .frame(height: 16)
            // Keep horizontal hugging for content width but allow the
            // parent to enforce height so it matches tag chips exactly.
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tagInputBackgroundColor)
        )
        .overlay(
            // Keep the outer bounds identical to tag chips.
            // Thicken border on focus, inset inward to preserve outside size.
            Capsule(style: .continuous)
                .inset(by: isTagFieldFocused ? 0.5 : 0)
                .stroke(tagInputBorderColor, lineWidth: isTagFieldFocused ? 2 : 1)
        )
        .overlay(alignment: .bottomLeading) {
            if shouldShowTagSuggestions {
                suggestionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .offset(y: 8)
            }
        }
        .zIndex(shouldShowTagSuggestions ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isTagFieldFocused)
        .accessibilityLabel("Add a tag")
    }

    private var tagInputBorderColor: Color {
        if isTagFieldFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.7 : 0.5)
        }
        return Color(NSColor.separatorColor).opacity(colorScheme == .dark ? 0.5 : 0.35)
    }

    private var tagInputBackgroundColor: Color {
        let base = Color(NSColor.controlBackgroundColor)
        return isTagFieldFocused
            ? base.opacity(colorScheme == .dark ? 0.85 : 1.0)
            : base.opacity(colorScheme == .dark ? 0.65 : 0.85)
    }

    private var tagInputIconColor: Color {
        isTagFieldFocused ? Color.accentColor : Color(NSColor.secondaryLabelColor)
    }

    private var tagChipBackgroundColor: Color {
        colorScheme == .dark ? Color.accentColor.opacity(0.24) : Color.accentColor.opacity(0.14)
    }

    private var tagChipBorderColor: Color {
        colorScheme == .dark ? Color.accentColor.opacity(0.45) : Color.accentColor.opacity(0.26)
    }

    private var tagChipShadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08)
    }

    // NSComboBox-based suggestions: provide list of available tag names excluding already assigned
    private var availableTagNamesExcludingAssigned: [String] {
        let assigned = Set(record.tags.map { $0.name.lowercased() })
        let base = availableTags
            .filter { !assigned.contains($0.name.lowercased()) }
        let names = base.map { $0.name }
        // Sort by usage when empty query; dynamic sorting on input is handled inside TagComboBoxView
        return names.sorted { lhs, rhs in
            let lc = tagUsageCounts[lhs, default: 0]
            let rc = tagUsageCounts[rhs, default: 0]
            if lc != rc { return lc > rc }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var tagUsageCounts: [String: Int] {
        var dict: [String: Int] = [:]
        for tag in availableTags {
            dict[tag.name] = tag.records.count
        }
        return dict
    }

    private var filteredTagSuggestions: [Tag] {
        let trimmedInput = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return [] }

        let excludedIDs = assignedTagIDs
        let matches = availableTags.filter { tag in
            guard !excludedIDs.contains(tag.id) else { return false }
            return tag.name.range(of: trimmedInput, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let sorted = matches.sorted { a, b in
            let ra = matchRank(for: a.name, query: trimmedInput)
            let rb = matchRank(for: b.name, query: trimmedInput)
            if ra != rb { return ra < rb }
            let ua = a.records.count
            let ub = b.records.count
            if ua != ub { return ua > ub }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(8))
    }

    private var assignedTagIDs: Set<Tag.ID> { Set(record.tags.map(\.id)) }

    private var shouldShowTagSuggestions: Bool {
        isTagFieldFocused && !filteredTagSuggestions.isEmpty
    }

    private var tagSuggestionBottomPadding: CGFloat {
        guard shouldShowTagSuggestions else { return 0 }
        let rowHeight: CGFloat = 28
        let verticalInsets: CGFloat = 28
        let rows = CGFloat(filteredTagSuggestions.count)
        return rows * rowHeight + verticalInsets
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(filteredTagSuggestions) { suggestion in
                Button {
                    commitTagInput(using: suggestion)
                } label: {
                    HStack {
                        Text(suggestion.name)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if suggestion.records.count > 0 {
                            Text("\(suggestion.records.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(highlightedSuggestionID == suggestion.id ? Color.accentColor.opacity(0.14) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .frame(maxWidth: 240, alignment: .leading)
    }

    private func matchRank(for name: String, query: String) -> Int {
        let s = name.lowercased()
        let q = query.lowercased()
        if s.hasPrefix(q) { return 0 }
        if let r = s.range(of: q) {
            if r.lowerBound == s.startIndex { return 0 }
            let prev = s.index(before: r.lowerBound)
            let scalars = String(s[prev]).unicodeScalars
            if let u = scalars.first, CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains(u) { return 1 }
            return 2
        }
        return 3
    }

    @discardableResult
    private func commitTagInput(using suggestion: Tag? = nil) -> Bool {
        if let suggestion {
            if attach(tag: suggestion) {
                persistTagChanges(reason: "attach existing tag")
                return true
            }
            return false
        }

        let trimmedInput = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            clearTagInput()
            return false
        }

        do {
            if let tag = try tagManager.ensureTag(named: trimmedInput, in: modelContext) {
                if attach(tag: tag) {
                    persistTagChanges(reason: "create tag \(trimmedInput)")
                    return true
                }
            } else {
                clearTagInput()
                return false
            }
        } catch {
            Logger.error("Failed to create or attach tag", error: error, category: .data)
        }
        return false
    }

    @discardableResult
    private func attach(tag: Tag) -> Bool {
        let didChange = withAnimation(.easeInOut(duration: 0.2)) {
            tagManager.attach(tag, to: record)
        }

        clearTagInput()
        return didChange
    }

    private func removeTag(_ tag: Tag) {
        let didChange = withAnimation(.easeInOut(duration: 0.2)) {
            tagManager.detach(tag, from: record, in: modelContext)
        }

        if didChange {
            persistTagChanges(reason: "remove tag \(tag.name)")
        }
    }

    private func clearTagInput() {
        tagInput = ""
    }

    @discardableResult
    private func commitTagByName(_ name: String) -> Bool {
        // Prefer existing tag if present
        if let tag = availableTags.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            if attach(tag: tag) {
                persistTagChanges(reason: "attach existing tag by selection")
                return true
            }
            return false
        }

        // Otherwise create
        tagInput = name
        return commitTagInput()
    }

    private func persistTagChanges(reason: String) {
        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to persist tag changes (\(reason))", error: error, category: .data)
        }
    }

    private func handleTagInputChange(_ newValue: String) {
        guard !newValue.isEmpty else { return }
        if let last = newValue.last, tagDelimiterCharacters.contains(last) {
            tagInput = String(newValue.dropLast())
            _ = commitTagInput()
        }
    }

    private var tagDelimiterCharacters: Set<Character> {
        [",", ";"]
    }

    private var tabsSection: some View {
        guard shouldShowContent else {
            return AnyView(EmptyView())
        }

        let picker = Picker("", selection: $selectedTab) {
            Text("Transcription").tag(Tab.transcription)
            Text("Summary").tag(Tab.summary)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)

        let content: AnyView = {
            switch selectedTab {
            case .transcription:
                return AnyView(transcriptionTab)
            case .summary:
                return AnyView(summaryTab)
            }
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                picker
                content
            }
        )
    }

    private var transcriptionTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = transcriptionError {
                InlineMessageView(error)
                    .padding(.bottom, 4)
            }

        InlineEditableTextArea(
            text: $transcriptionDraft,
            placeholder: "Start typing transcription...",
            statusMessage: transcriptionStatusMessage,
            focusBinding: $focusedEditor,
            editor: .transcription,
            onCopy: {
                copyTranscription()
            },
            showCopied: showTranscriptionCopied
        )

        HStack(spacing: 12) {
            if settings.whisperProvider == .speechAnalyzer {
                let localeOptions = ["Automatic"] + speechAnalyzerLocales.map { localeDisplayName($0) }
                
                ComboBoxView(
                    placeholder: speechAnalyzerLocales.isEmpty ? "Loading languages..." : "Choose language",
                    options: localeOptions,
                    selectedOption: Binding(
                        get: {
                            if selectedSpeechAnalyzerLocale.isEmpty {
                                return "Automatic"
                            }
                            if let locale = speechAnalyzerLocales.first(where: { $0.identifier == selectedSpeechAnalyzerLocale }) {
                                return localeDisplayName(locale)
                            }
                            return "Automatic"
                        },
                        set: { newValue in
                            if newValue == "Automatic" {
                                selectedSpeechAnalyzerLocale = ""
                            } else if let locale = speechAnalyzerLocales.first(where: { localeDisplayName($0) == newValue }) {
                                selectedSpeechAnalyzerLocale = locale.identifier
                            }
                        }
                    ),
                    allowsCustomInput: false
                )
                .frame(width: 220, height: 32)
            } else if settings.whisperProvider != .speechAnalyzer {
                ComboBoxView(
                    placeholder: whisperModelOptions.isEmpty ? "Select transcription model" : "Choose model",
                    options: whisperModelOptions,
                    selectedOption: $selectedWhisperModel
                )
                .frame(width: 220, height: 32)
            }

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
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isTranscribing || record.fileURL == nil)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }
    }

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = summaryError {
                InlineMessageView(error)
                    .padding(.bottom, 4)
            }

            if isSummaryEditing {
                InlineEditableTextArea(
                    text: $summaryDraft,
                    placeholder: "No summary available yet.",
                    statusMessage: nil,
                    focusBinding: $focusedEditor,
                    editor: .summary,
                    onExit: { focusedEditor = nil },
                    onCopy: {
                        copySummary()
                    },
                    showCopied: showSummaryCopied
                )
            } else {
                MarkdownSummaryPreview(
                    markdownContent: summaryMarkdownContent,
                    plainText: summaryDraft,
                    placeholder: "No summary available yet.",
                    onActivateEditing: activateSummaryEditing,
                    onCopy: {
                        copySummary()
                    },
                    showCopied: showSummaryCopied
                )
            }

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
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSummarizing || !hasTranscriptionContent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
        .onAppear { updateSummaryMarkdownContentIfNeeded(force: true) }
        .onChange(of: summaryDraft) { _, _ in
            guard !isSummaryEditing else { return }
            updateSummaryMarkdownContentIfNeeded()
        }
        .onChange(of: focusedEditor) { _, newValue in
            if newValue != .summary {
                updateSummaryMarkdownContentIfNeeded()
            }
        }
    }

    private var processingSection: some View {
        Group {
            switch currentProcessingState {
            case .transcribing, .summarizing, .streamingTranscription:
                ProcessingProgressView(state: currentProcessingState)
                    .padding(.top, 8)
            default:
                EmptyView()
            }
        }
    }
    
    // Computed property for transcription text for easier access
    private var transcriptionStatusMessage: String? {
        if let text = record.transcriptionText, !text.isEmpty {
            return nil
        }

        if record.hasTranscription && record.transcriptionText != nil {
            return "Transcription resulted in empty text. Try again with a different model or check audio quality."
        }

        if record.hasTranscription {
            return "Transcription processing... Check back later."
        }

        return "Transcription not available yet."
    }

    private var trimmedTranscriptionDraft: String {
        transcriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSummaryDraft: String {
        summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTranscriptionContent: Bool {
        !trimmedTranscriptionDraft.isEmpty
    }

    private var hasSummaryContent: Bool {
        !trimmedSummaryDraft.isEmpty
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
        commitPendingInlineEdits()
        guard hasTranscriptionContent else { return }

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

    private var mainStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                headerSection
                playerControls
            }
            Divider()
            processingSection
            tabsSection
            Spacer()
        }
    }

    var body: some View {
        var view = AnyView(
            mainStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, isSidebarCollapsed ? 16 : 0)
        )

        view = AnyView(view.animation(.easeInOut(duration: 0.25), value: isSidebarCollapsed))
        view = AnyView(view.animation(.easeInOut(duration: 0.4), value: shouldShowContent))
        view = AnyView(view.onAppear {
            selectedWhisperModel = settings.whisperModel
            selectedSummaryModel = settings.openAIModel
            selectedSpeechAnalyzerLocale = settings.speechAnalyzerLocaleIdentifier
            
            loadSpeechAnalyzerLocales()

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

            updateSummaryMarkdownContentIfNeeded(force: true)
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRecordCreated"))) { notification in
            // If this view is showing the newly created record, start automatic processing
            if let recordId = notification.userInfo?["recordId"] as? UUID,
               recordId == record.id {
                Logger.debug("Received notification for new record creation: \(record.name)", category: .ui)
                isAutomaticMode = true
                startAutomaticPipeline()
            }
        })

        view = AnyView(view.onDisappear {
            commitPendingInlineEdits()
            unregisterSpacebarShortcut()
            playerManager.stopAndCleanup()
            isSummaryEditing = false
            focusedEditor = nil
        })
        // Detect focus changes for the title TextField
        view = AnyView(view.onChange(of: isTitleFieldFocused) { oldValue, newValue in
            if !newValue && isEditingTitle { // If focus is lost AND we were editing
                cancelEditingTitle()
            }
        })

        view = AnyView(view.onChange(of: tagInput) { _, newValue in
            handleTagInputChange(newValue)
        })

        view = AnyView(view.onChange(of: isTagFieldFocused) { _, newValue in
            if newValue {
                highlightedSuggestionID = filteredTagSuggestions.first?.id
            } else {
                clearTagInput()
            }
        })

        view = AnyView(view.onChange(of: selectedWhisperModel) { _, newValue in
            updateSettings(\.whisperModel, with: newValue, settingName: "Whisper model")
        })

        view = AnyView(view.onChange(of: selectedSummaryModel) { _, newValue in
            updateSettings(\.openAIModel, with: newValue, settingName: "Summary model")
        })

        view = AnyView(view.onChange(of: selectedTab) { _, newValue in
            guard newValue != .summary else { return }
            if focusedEditor == .summary {
                focusedEditor = nil
            }
            if isSummaryEditing {
                isSummaryEditing = false
                updateSummaryMarkdownContentIfNeeded()
            }
        })

        view = AnyView(view.onChange(of: transcriptionDraft) { _, newValue in
            let persistedValue = record.transcriptionText ?? ""
            if persistedValue == newValue {
                transcriptionSaveWorkItem?.cancel()
                transcriptionSaveWorkItem = nil
            } else {
                scheduleTranscriptionSave()
            }
        })

        view = AnyView(view.onChange(of: summaryDraft) { _, newValue in
            let persistedValue = record.summaryText ?? ""
            if persistedValue == newValue {
                summarySaveWorkItem?.cancel()
                summarySaveWorkItem = nil
            } else {
                scheduleSummarySave()
            }
        })

        view = AnyView(view.onChange(of: appSettings.first?.whisperModel ?? "") { _, newValue in
            if newValue != selectedWhisperModel {
                selectedWhisperModel = newValue
            }
        })
        
        view = AnyView(view.onChange(of: selectedWhisperModel) { _, newValue in
            updateSettings(\.whisperModel, with: newValue, settingName: "whisperModel")
        })

        view = AnyView(view.onChange(of: appSettings.first?.openAIModel ?? "") { _, newValue in
            if newValue != selectedSummaryModel {
                selectedSummaryModel = newValue
            }
        })
        
        view = AnyView(view.onChange(of: selectedSummaryModel) { _, newValue in
            updateSettings(\.openAIModel, with: newValue, settingName: "openAIModel")
        })
        
        view = AnyView(view.onChange(of: appSettings.first?.speechAnalyzerLocaleIdentifier ?? "") { _, newValue in
            if newValue != selectedSpeechAnalyzerLocale {
                selectedSpeechAnalyzerLocale = newValue
            }
        })
        
        view = AnyView(view.onChange(of: selectedSpeechAnalyzerLocale) { _, newValue in
            updateSettings(\.speechAnalyzerLocaleIdentifier, with: newValue, settingName: "speechAnalyzerLocale")
        })
        
        view = AnyView(view.onChange(of: settings.whisperProvider) { _, _ in
            loadSpeechAnalyzerLocales()
        })

        view = AnyView(view.onReceive(processingManager.$recordStates) { _ in
            handleProcessingStateChange()
        })

        view = AnyView(view.onChange(of: record.transcriptionText ?? "") { _, newValue in
            guard focusedEditor != .transcription else { return }
            if newValue != transcriptionDraft {
                transcriptionDraft = newValue
            }
        })

        view = AnyView(view.onChange(of: record.summaryText ?? "") { _, newValue in
            if focusedEditor != .summary, newValue != summaryDraft {
                summaryDraft = newValue
            }
            if isAutomaticMode && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedTab = .summary
                isAutomaticMode = false
            }
        })

        view = AnyView(view.onChange(of: focusedEditor) { oldValue, newValue in
            if oldValue == .transcription, newValue != .transcription {
                saveTranscriptionIfNeeded()
            }
            if oldValue == .summary, newValue != .summary {
                // Leaving summary editor: ensure preview reflects latest text
                isSummaryEditing = false
                updateSummaryMarkdownContentIfNeeded(force: true)
                saveSummaryIfNeeded()
            }
            if newValue == .summary {
                isSummaryEditing = true
            }
        })

        view = AnyView(view.alert("Delete Recording?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteCurrentRecord()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the recording, transcription, and summary. This action cannot be undone.")
        })

        return view
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
        copyToClipboard(
            text: trimmedTranscriptionDraft,
            showCopiedBinding: { showTranscriptionCopied = $0 },
            logMessage: "Transcription copied to clipboard."
        )
    }

    private func copySummary() {
        copyToClipboard(
            text: trimmedSummaryDraft,
            showCopiedBinding: { showSummaryCopied = $0 },
            logMessage: "Summary copied to clipboard."
        )
    }
    
    private func copyToClipboard(text: String, showCopiedBinding: @escaping (Bool) -> Void, logMessage: String) {
        guard !text.isEmpty else { return }
        
        commitPendingInlineEdits()
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.info(logMessage, category: .ui)
        
        // Show copied indication
        showCopiedBinding(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + copiedIndicationDuration) {
            showCopiedBinding(false)
        }
    }

    private func scheduleTranscriptionSave() {
        transcriptionSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            saveTranscriptionIfNeeded()
        }

        transcriptionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + inlineSaveDebounceInterval,
            execute: workItem
        )
    }

    private func saveTranscriptionIfNeeded() {
        transcriptionSaveWorkItem?.cancel()
        transcriptionSaveWorkItem = nil

        let newStoredValue: String? = hasTranscriptionContent ? transcriptionDraft : nil

        let shouldUpdateText = record.transcriptionText != newStoredValue
        let shouldUpdateFlag = record.hasTranscription != hasTranscriptionContent

        guard shouldUpdateText || shouldUpdateFlag else {
            return
        }

        record.transcriptionText = newStoredValue
        record.hasTranscription = hasTranscriptionContent

        do {
            try modelContext.save()
            Logger.debug("Transcription updated inline for record \(record.id)", category: .ui)
        } catch {
            Logger.error("Failed to persist edited transcription", error: error, category: .ui)
        }
    }

    private func scheduleSummarySave() {
        summarySaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            saveSummaryIfNeeded()
        }

        summarySaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + inlineSaveDebounceInterval,
            execute: workItem
        )
    }

    private func activateSummaryEditing() {
        guard !isSummaryEditing else { return }
        isSummaryEditing = true
        DispatchQueue.main.async {
            focusedEditor = .summary
        }
    }

    private func updateSummaryMarkdownContentIfNeeded(force: Bool = false) {
        let currentValue = summaryDraft
        guard force || currentValue != renderedSummarySnapshot else {
            return
        }

        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            summaryMarkdownContent = nil
        } else {
            summaryMarkdownContent = MarkdownContent(currentValue)
        }

        renderedSummarySnapshot = currentValue
    }

    private func saveSummaryIfNeeded() {
        summarySaveWorkItem?.cancel()
        summarySaveWorkItem = nil

        let newStoredValue: String? = hasSummaryContent ? summaryDraft : nil

        guard record.summaryText != newStoredValue else {
            return
        }

        record.summaryText = newStoredValue
        if focusedEditor != .summary {
            updateSummaryMarkdownContentIfNeeded(force: true)
        }

        do {
            try modelContext.save()
            Logger.debug("Summary updated inline for record \(record.id)", category: .ui)
        } catch {
            Logger.error("Failed to persist edited summary", error: error, category: .ui)
        }
    }

    private func commitPendingInlineEdits() {
        saveTranscriptionIfNeeded()
        saveSummaryIfNeeded()
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
        let associatedTags = record.tags
        for tag in associatedTags {
            _ = tagManager.detach(tag, from: record, in: modelContext)
        }

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
    
    // MARK: - Speech Analyzer Locale Support
    
    private func loadSpeechAnalyzerLocales() {
        guard settings.whisperProvider == .speechAnalyzer else { return }
        guard speechAnalyzerLocales.isEmpty else { return }
        
        Task {
            if #available(macOS 26, *) {
                #if canImport(Speech)
                let locales = await Speech.SpeechTranscriber.supportedLocales
                let sorted = locales.sorted {
                    localeDisplayName($0).localizedCaseInsensitiveCompare(localeDisplayName($1)) == .orderedAscending
                }
                await MainActor.run {
                    self.speechAnalyzerLocales = sorted
                }
                #endif
            }
        }
    }
    
    private func localeDisplayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
