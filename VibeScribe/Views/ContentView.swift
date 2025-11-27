//
//  ContentView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRecord: Record? = nil
    @State private var isShowingSettings = false
    @State private var shouldScrollToSelectedRecord = false
    @StateObject private var importManager = AudioFileImportManager()
    @State private var isDragOver = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var activeTagFilterName: String? = nil

@Query(sort: \Record.date, order: .reverse) private var records: [Record]
@Query(filter: #Predicate<AppSettings> { $0.id == "app_settings" })
private var appSettings: [AppSettings]
#if DEBUG
@AppStorage("debug.simulateEmptyRecordings") private var simulateEmptyRecordings = false
#endif
    @AppStorage("ui.language.code") private var appLanguageCode: String = ""

    private var appLocale: Locale {
        AppLanguage.locale(for: appLanguageCode)
    }

    private var settings: AppSettings {
        if let existing = appSettings.first {
            return existing
        }
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        return newSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RecordsSidebarView(
                    title: sidebarTitle,
                    isFiltering: activeTagFilterName != nil,
                    onClearFilter: { activeTagFilterName = nil },
                    records: filteredRecords,
                    selectedRecord: $selectedRecord,
                    shouldScrollToSelectedRecord: $shouldScrollToSelectedRecord,
                    onCreateRecording: presentRecordingOverlay
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 700)
            } detail: {
                recordDetail
            }
            .navigationSplitViewStyle(.balanced)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Footer
            Divider()
                .padding(.horizontal, 12)
        }
        .contextMenu {
            Button {
                isShowingSettings = true
            } label: {
                Label(AppLanguage.localized("settings"), systemImage: "gear")
            }
            
            Divider()
            
            Button {
                presentRecordingOverlay()
            } label: {
                Label(AppLanguage.localized("new.recording"), systemImage: "plus.circle.fill")
            }
        }
        .onAppear {
            assignMainWindow()
            selectFirstRecordIfNeeded()
            AppLanguage.applyPreferredLanguagesIfNeeded(code: appLanguageCode)
            // Keep AppStorage and SwiftData in sync on launch
            if settings.appLanguageCode != appLanguageCode {
                settings.appLanguageCode = appLanguageCode
                try? modelContext.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            isShowingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartRecording"))) { _ in
            presentRecordingOverlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRecordCreated"))) { notification in
            guard let recordId = notification.userInfo?["recordId"] as? UUID else { return }
            guard let newRecord = fetchRecord(with: recordId) else {
                Logger.error("New record with ID \(recordId) not found immediately after creation", category: .data)
                return
            }

            selectRecord(newRecord, shouldScroll: true)
            Logger.info("Auto-selected newly created record: \(newRecord.name)", category: .ui)
        }
        .onChange(of: records) { _, newRecords in
#if DEBUG
            guard !simulateEmptyRecordings else { return }
#endif
            guard selectedRecord == nil, let first = newRecords.first else { return }
            selectRecord(first, shouldScroll: false)
            Logger.debug("Auto-selected first record without scrolling", category: .ui)
        }
#if DEBUG
        .onChange(of: simulateEmptyRecordings) { _, isSimulating in
            if isSimulating {
                selectedRecord = nil
            } else {
                selectFirstRecordIfNeeded()
            }
        }
#endif
        .onChange(of: filteredRecords) { _, newFiltered in
            // Keep selection valid when filter changes
            if let selected = selectedRecord, !newFiltered.contains(where: { $0.id == selected.id }) {
                selectedRecord = newFiltered.first
            }
        }
        // Legacy sheet flow kept disabled; overlay replaces it
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .frame(width: 600, height: 500)
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isDragOver) { providers -> Bool in
            // Process provider objects on the main actor to avoid Sendable warnings
            Task { @MainActor in
                _ = handleDroppedFiles(providers: providers)
            }
            return true
        }
        .overlay(
            // Drag overlay
            isDragOver || importManager.isImporting ? 
            dragOverlay : nil
        )
        .environment(\.locale, appLocale)
    }
    
    private var effectiveRecords: [Record] {
#if DEBUG
        return simulateEmptyRecordings ? [] : records
#else
        return records
#endif
    }

    // Returns records filtered by the active tag name.
    // Comparison is case- and diacritic-insensitive to avoid surprising empty results
    // when tag names differ only by case or diacritics.
    private var filteredRecords: [Record] {
        guard let raw = activeTagFilterName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return effectiveRecords }
        let normalizedFilter = raw
        return effectiveRecords.filter { record in
            record.tags.contains { tag in
                tag.name.compare(normalizedFilter, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    private var sidebarTitle: String {
        if let name = activeTagFilterName, !name.isEmpty { return name }
        return AppLanguage.localized("all.recordings", comment: "Sidebar header title for all recordings")
    }

    // MARK: - Subviews
    
    @ViewBuilder
    private var recordDetail: some View {
        if effectiveRecords.isEmpty {
            WelcomeEmptyDetailView(
                onCreateRecording: presentRecordingOverlay,
                onImportAudio: presentImportPanel,
                onOpenSettings: { isShowingSettings = true }
            )
        } else if let selectedRecord = selectedRecord {
            RecordDetailView(
                record: selectedRecord,
                isSidebarCollapsed: columnVisibility == .detailOnly,
                onRecordDeleted: { _ in
                    self.selectedRecord = nil
                },
                onTagTapped: { tag in
                    self.activeTagFilterName = tag.name
                }
            )
            .id(selectedRecord.id)
        } else {
            VStack {
                Spacer()
                Text(AppLanguage.localized("select.a.recording.from.the.list"))
                    .font(.headline)
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
            }
        }
    }

    // MARK: - Helper Methods
    
    @MainActor
    private func assignMainWindow(retryCount: Int = 0) {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }

        if let primaryWindow = NSApplication.shared.mainWindow
            ?? NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible }) {
            guard appDelegate.mainWindow !== primaryWindow else { return }
            appDelegate.mainWindow = primaryWindow
            Logger.info("Assigned main window to AppDelegate", category: .ui)
            return
        }

        guard retryCount < 3 else {
            if let fallbackWindow = NSApplication.shared.windows.first {
                appDelegate.mainWindow = fallbackWindow
                Logger.info("Assigned fallback window to AppDelegate after retries", category: .ui)
            } else {
                Logger.error("No window found to assign to AppDelegate", category: .ui)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.assignMainWindow(retryCount: retryCount + 1)
        }
    }
    
    private func selectFirstRecordIfNeeded() {
#if DEBUG
        guard !simulateEmptyRecordings else { return }
#endif
        guard selectedRecord == nil, let first = records.first else { return }
        selectRecord(first, shouldScroll: false)
        Logger.debug("Auto-selected first record on appear", category: .ui)
    }

    private func deleteRecord(_ recordToDelete: Record) {
        if let fileURL = recordToDelete.fileURL {
            do {
                try FileManager.default.removeItem(at: fileURL)
                Logger.info("Deleted audio file: \(fileURL.lastPathComponent)", category: .data)
            } catch {
                Logger.error("Failed to delete audio file at \(fileURL.path)", error: error, category: .data)
            }
        } else {
            Logger.warning("Record \(recordToDelete.name) has no associated file URL", category: .data)
        }

        modelContext.delete(recordToDelete)
        
        do {
            try modelContext.save()
            Logger.info("Record \(recordToDelete.name) deleted", category: .data)
        } catch {
            Logger.error("Failed to delete record \(recordToDelete.name)", error: error, category: .data)
        }
    }

    private func selectRecord(_ record: Record, shouldScroll: Bool) {
        shouldScrollToSelectedRecord = shouldScroll
        selectedRecord = record
    }

    private func fetchRecord(with id: UUID) -> Record? {
        let descriptor = FetchDescriptor<Record>(predicate: #Predicate { record in record.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Logger.error("Failed to fetch record with ID \(id)", error: error, category: .data)
            return nil
        }
    }
    
    // MARK: - Drag and Drop Methods
    
    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        
        Task {
            do {
                let urls = try await loadURLsFromProviders(providers)
                
                await MainActor.run {
                    let supportedAudioFiles = AudioFileImportManager.filterSupportedAudioFiles(urls: urls)
                    
                    if !supportedAudioFiles.isEmpty {
                        Logger.info("Processing \(supportedAudioFiles.count) dropped audio files", category: .audio)
                        importManager.importAudioFiles(urls: supportedAudioFiles, modelContext: modelContext)
                    } else {
                        Logger.warning("No supported audio files found in dropped items", category: .audio)
                        // Show user feedback for unsupported files
                        showUnsupportedFilesAlert(totalCount: urls.count)
                    }
                }
            } catch {
                Logger.error("Failed to process dropped files", error: error, category: .general)
            }
        }
        
        return true
    }
    
    /// Loads URLs from NSItemProviders using modern async/await
    @MainActor
    private func loadURLsFromProviders(_ providers: [NSItemProvider]) async throws -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = try await self.loadURLFromProvider(provider) {
                urls.append(url)
            }
        }
        return urls
    }
    
    /// Loads a single URL from an NSItemProvider
    private func loadURLFromProvider(_ provider: NSItemProvider) async throws -> URL? {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: url)
            }
        }
    }
    
    /// Shows alert for unsupported files
    private func showUnsupportedFilesAlert(totalCount: Int) {
        Logger.info("Dropped \(totalCount) files but none were supported audio formats", category: .general)
    }
    
    private func presentRecordingOverlay() {
        // Present floating overlay window with recording controls
        OverlayWindowManager.shared.show(content: {
            AnyView(
                RecordingOverlayView()
                    .environment(\.modelContext, modelContext)
                    .environment(\.locale, appLocale)
            )
        })
    }
    
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFileImportManager.supportedContentTypes
        panel.prompt = AppLanguage.localized("import")
        panel.message = AppLanguage.localized("select.audio.youd.like.vibescribe.to.transcribe.and.summarize")
        
        panel.begin { response in
            guard response == .OK else { return }
            
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            
            let supportedAudioFiles = AudioFileImportManager.filterSupportedAudioFiles(urls: urls)
            
            if supportedAudioFiles.isEmpty {
                showUnsupportedFilesAlert(totalCount: urls.count)
                return
            }
            
            Logger.info("Importing \(supportedAudioFiles.count) audio files from picker", category: .audio)
            importManager.importAudioFiles(urls: supportedAudioFiles, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private var dragOverlay: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.1))
            .overlay(
                DragOverlayContent(
                    isImporting: importManager.isImporting,
                    importProgress: importManager.importProgress,
                    hasError: importManager.error != nil
                )
            )
            .animation(.easeInOut(duration: 0.3), value: isDragOver)
            .animation(.easeInOut(duration: 0.3), value: importManager.isImporting)
    }
}

// MARK: - Drag Overlay Content

private struct RecordsSidebarView: View {
    let title: String
    let isFiltering: Bool
    let onClearFilter: () -> Void
    let records: [Record]
    @Binding var selectedRecord: Record?
    @Binding var shouldScrollToSelectedRecord: Bool
    let onCreateRecording: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBlurView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SidebarHeader(
                    title: title,
                    isFiltering: isFiltering,
                    onClearFilter: onClearFilter
                )
                content
            }
        }
        .safeAreaInset(edge: .bottom) {
            sidebarBottomBar
        }
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            RecordingsEmptyState()
        } else {
            ScrollViewReader { proxy in
                List(selection: $selectedRecord) {
                    ForEach(groupedRecords) { section in
                        Section(header: sectionHeader(title: section.title)) {
                            ForEach(section.records) { record in
                                RecordRow(record: record)
                                    .tag(record)
                                    .id(record.id)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: selectedRecord) { _, newValue in
                    guard shouldScrollToSelectedRecord, let recordToScroll = newValue else { return }
                    withAnimation {
                        proxy.scrollTo(recordToScroll.id, anchor: .top)
                    }
                    shouldScrollToSelectedRecord = false
                }
            }
        }
    }

    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 0)
            HStack {
                Button(action: onCreateRecording) {
                    Label(AppLanguage.localized("new.recording"), systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .accessibilityHint(Text(AppLanguage.localized("start.a.new.recording")))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VisualEffectBlurView(material: .sidebar, blendingMode: .behindWindow)
            )
        }
    }

    private var groupedRecords: [RecordSection] {
        let localeIdentifier = Bundle.main.preferredLocalizations.first(where: { $0 != "Base" })
            ?? Locale.current.identifier
        let locale = Locale(identifier: localeIdentifier)

        let calculationCalendar = Calendar.autoupdatingCurrent

        let relativeFormatter = Self.makeRelativeFormatter(
            calendar: calculationCalendar,
            locale: locale
        )
        let now = Date()

        return records.reduce(into: [RecordSection]()) { sections, record in
            let title = sectionTitle(
                for: record.date,
                relativeTo: now,
                calendar: calculationCalendar,
                relativeFormatter: relativeFormatter,
                locale: locale
            )

            if let lastIndex = sections.indices.last, sections[lastIndex].title == title {
                sections[lastIndex].records.append(record)
            } else {
                sections.append(RecordSection(title: title, records: [record]))
            }
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(
                VisualEffectBlurView(material: .sidebar, blendingMode: .behindWindow)
                    .overlay(Color.clear)
            )
    }

    private func sectionTitle(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar,
        relativeFormatter: RelativeDateTimeFormatter,
        locale: Locale
    ) -> String {
        if calendar.isDateInToday(date) {
            return Self.styleRelativeTitle(
                relativeFormatter.localizedString(for: date, relativeTo: now),
                locale: locale
            )
        }

        if calendar.isDateInYesterday(date) {
            return Self.styleRelativeTitle(
                relativeFormatter.localizedString(for: date, relativeTo: now),
                locale: locale
            )
        }

        if let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
           let recordWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start {
            let weekDifference = calendar
                .dateComponents([.weekOfYear], from: currentWeekStart, to: recordWeekStart)
                .weekOfYear ?? 0

            if weekDifference == 0 {
                return AppLanguage.localized("this.week", comment: "Section title for records created this week")
            }

            if weekDifference == -1 {
                return AppLanguage.localized("last.week", comment: "Section title for records created in the previous week")
            }
        }

        if let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start,
           let recordMonthStart = calendar.dateInterval(of: .month, for: date)?.start {
            let monthDifference = calendar
                .dateComponents([.month], from: currentMonthStart, to: recordMonthStart)
                .month ?? 0

            if monthDifference == 0 {
                return Self.styleRelativeTitle(
                    relativeFormatter.localizedString(from: DateComponents(month: 0)),
                    locale: locale
                )
            }

            if monthDifference == -1 {
                return Self.styleRelativeTitle(
                    relativeFormatter.localizedString(from: DateComponents(month: -1)),
                    locale: locale
                )
            }
        }

        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let monthName = Self.monthString(from: date, locale: locale)
            let format = AppLanguage.localized(
                "in.arg1",
                comment: "Section title for records created earlier this year"
            )
            return String(
                format: format,
                locale: locale,
                monthName
            )
        }

        let monthAndYear = Self.monthYearString(from: date, locale: locale)
        let format = AppLanguage.localized(
            "in.arg1",
            comment: "Section title for records created in previous years"
        )
        return String(
            format: format,
            locale: locale,
            monthAndYear
        )
    }

    private static func makeRelativeFormatter(calendar: Calendar, locale: Locale) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter
    }()

    private static func monthString(from date: Date, locale: Locale) -> String {
        monthFormatter.locale = locale
        return monthFormatter.string(from: date)
    }

    private static func monthYearString(from date: Date, locale: Locale) -> String {
        monthYearFormatter.locale = locale
        return monthYearFormatter.string(from: date)
    }

    private static func styleRelativeTitle(_ string: String, locale: Locale) -> String {
        if let code = locale.language.languageCode?.identifier, code.lowercased().hasPrefix("en") {
            return string.capitalized(with: locale)
        }
        return string
    }
}

private struct RecordSection: Identifiable {
    let title: String
    var records: [Record]

    var id: String { title }
}

private struct SidebarHeader: View {
    let title: String
    let isFiltering: Bool
    let onClearFilter: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if isFiltering {
                    HStack(spacing: 0) {
                        Text("#")
                            .padding(.trailing, 1)
                        Text(title)
                    }
                    .foregroundColor(.accentColor)
                } else {
                    Text(title)
                        .foregroundColor(.primary)
                }
            }
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.tail)
            if isFiltering {
                Button(action: onClearFilter) {
                    Image(systemName: "xmark.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help(AppLanguage.localized("reset.filter"))
                .accessibilityLabel(Text(AppLanguage.localized("reset.filter")))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct RecordingsEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.circle")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
            
            Text(AppLanguage.localized("no.recordings.yet"))
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(AppLanguage.localized("start.a.capture.or.import.a.file.from.the.panel.on.the.right"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DragOverlayContent: View {
    let isImporting: Bool
    let importProgress: String
    let hasError: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            if isImporting {
                importingContent
            } else if hasError {
                errorContent
            } else {
                dropZoneContent
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .stroke(strokeColor, lineWidth: 2)
        )
    }
    
    @ViewBuilder
    private var importingContent: some View {
        ProgressView()
            .scaleEffect(1.2)
        
        Text(importProgress)
            .font(.headline)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
    }
    
    @ViewBuilder
    private var errorContent: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 48))
            .foregroundColor(.orange)
            .symbolRenderingMode(.hierarchical)
        
        Text(AppLanguage.localized("import.error"))
            .font(.headline)
            .foregroundColor(.primary)
        
        Text(AppLanguage.localized("check.file.format.and.try.again"))
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private var dropZoneContent: some View {
        Image(systemName: "waveform.and.arrow.down")
            .font(.system(size: 64))
            .foregroundColor(.accentColor)
            .symbolRenderingMode(.hierarchical)
        
        Text(AppLanguage.localized("drop.audio.files.here"))
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
        
        Text(AppLanguage.localized("supported.formats.mp3.wav.m4a.aac.ogg.flac"))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }
    
    private var strokeColor: Color {
        if hasError {
            return .orange
        } else if isImporting {
            return .blue
        } else {
            return .accentColor
        }
    }
}

private struct WelcomeEmptyDetailView: View {
    let onCreateRecording: () -> Void
    let onImportAudio: () -> Void
    let onOpenSettings: () -> Void
    
    private let whisperServerURL = URL(string: "https://github.com/pfrankov/whisper-server/releases")!
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                heroSection
                quickStartCard
                essentialsNote
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 10) {
            if let appIconImage {
                Image(nsImage: appIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.22))
            }

            Text(AppLanguage.localized("welcome.to.vibescribe"))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)

            Text(AppLanguage.localized("record.or.import.conversations.keep.processing.on.your.own.whisper.compatible.server.and.read.the.ai.summary.right.away"))
                .font(.title3.weight(.regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var appIconImage: NSImage? {
        if let assetIcon = NSImage(named: "AppIcon") {
            return assetIcon
        }
        if let bundleIcon = NSImage(named: NSImage.applicationIconName) {
            return bundleIcon
        }
        return NSApp?.applicationIconImage
    }

    @ViewBuilder
    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLanguage.localized("pick.your.first.step"))
                    .font(.headline)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    primaryRecordingButton
                    importButton
                }
                VStack(spacing: 12) {
                    primaryRecordingButton
                    importButton
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Link(AppLanguage.localized("install.whisperserver"), destination: whisperServerURL)
                Text(AppLanguage.localized("run.whisperserver.locally.or.on.your.own.host.to.keep.conversations.private"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpenSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.accentColor)
                        Text(AppLanguage.localized("connect.your.transcription.and.summary.services"))
                    }
                }
                .buttonStyle(.link)

                Text(AppLanguage.localized("add.your.whisper.compatible.audio.endpoint.and.chat.model.so.vibescribe.can.process.automatically"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var essentialsNote: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.accentColor)
                Text(AppLanguage.localized("the.recordings.transcriptions.and.summaries.stay.on.your.mac.and.only.you.determine.what.to.do.with.them"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryRecordingButton: some View {
        Button(action: onCreateRecording) {
            Label(AppLanguage.localized("start.recording.2"), systemImage: "mic.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint(Text(AppLanguage.localized("opens.the.floating.overlay.to.capture.mic.and.system.audio")))
    }

    private var importButton: some View {
        Button(action: onImportAudio) {
            Label(AppLanguage.localized("import.audio.file"), systemImage: "tray.and.arrow.down.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

#Preview {
    do {
        let schema = Schema([Record.self, Tag.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        
        let settings = AppSettings()
        container.mainContext.insert(settings)

        return ContentView()
            .modelContainer(container)
    } catch {
        return Text("Failed to create preview: \(error.localizedDescription)")
    }
} 
