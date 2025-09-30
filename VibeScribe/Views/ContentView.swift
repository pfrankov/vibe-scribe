//
//  ContentView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRecord: Record? = nil
    @State private var isShowingSettings = false
    @State private var shouldScrollToSelectedRecord = false
    @StateObject private var importManager = AudioFileImportManager()
    @State private var isDragOver = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    @Query(sort: \Record.date, order: .reverse) private var records: [Record]

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RecordsSidebarView(
                    records: records,
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
                Label("Settings", systemImage: "gear")
            }
            
            Divider()
            
            Button {
                presentRecordingOverlay()
            } label: {
                Label("New Recording", systemImage: "plus.circle.fill")
            }
        }
        .onAppear {
            assignMainWindow()
            selectFirstRecordIfNeeded()
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
            guard selectedRecord == nil, let first = newRecords.first else { return }
            selectRecord(first, shouldScroll: false)
            Logger.debug("Auto-selected first record without scrolling", category: .ui)
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
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var recordDetail: some View {
        if let selectedRecord = selectedRecord {
            RecordDetailView(
                record: selectedRecord,
                isSidebarCollapsed: columnVisibility == .detailOnly,
                onRecordDeleted: { _ in
                    self.selectedRecord = nil
                }
            )
            .id(selectedRecord.id)
        } else {
            VStack {
                Spacer()
                Text("Select a recording from the list")
                    .font(.headline)
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
            }
        }
    }

    // MARK: - Helper Methods
    
    private func assignMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.isMainWindow }) {
            (NSApplication.shared.delegate as? AppDelegate)?.mainWindow = window
            Logger.info("Assigned main window to AppDelegate", category: .ui)
        } else if let anyWindow = NSApplication.shared.windows.first {
            (NSApplication.shared.delegate as? AppDelegate)?.mainWindow = anyWindow
            Logger.warning("Assigned fallback window to AppDelegate", category: .ui)
        } else {
            Logger.error("No window found to assign to AppDelegate", category: .ui)
        }
    }
    
    private func selectFirstRecordIfNeeded() {
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
            AnyView(RecordingOverlayView().environment(\.modelContext, modelContext))
        })
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
    let records: [Record]
    @Binding var selectedRecord: Record?
    @Binding var shouldScrollToSelectedRecord: Bool
    let onCreateRecording: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(onCreateRecording: onCreateRecording)
            Divider()
            content
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
                            }
                        }
                    }
                }
                .listStyle(.plain)
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
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
                return NSLocalizedString("This Week", comment: "Section title for records created this week")
            }

            if weekDifference == -1 {
                return NSLocalizedString("Last Week", comment: "Section title for records created in the previous week")
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
            let format = NSLocalizedString(
                "In %@",
                comment: "Section title for records created earlier this year"
            )
            return String(
                format: format,
                locale: locale,
                monthName
            )
        }

        let monthAndYear = Self.monthYearString(from: date, locale: locale)
        let format = NSLocalizedString(
            "In %@",
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
    let onCreateRecording: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("All Recordings")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()

            Button(action: onCreateRecording) {
                Label("New Recording", systemImage: "plus.circle.fill")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct RecordingsEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 40))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .padding(.bottom, 4)
            Text("No recordings yet")
                .font(.headline)
                .foregroundColor(Color(NSColor.labelColor))
            Text("Click + to create your first recording")
                .font(.subheadline)
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            Spacer()
        }
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
        
        Text("Import Error")
            .font(.headline)
            .foregroundColor(.primary)
        
        Text("Check file format and try again")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private var dropZoneContent: some View {
        Image(systemName: "waveform.and.arrow.down")
            .font(.system(size: 64))
            .foregroundColor(.accentColor)
            .symbolRenderingMode(.hierarchical)
        
        Text("Drop Audio Files Here")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
        
        Text("Supported formats: MP3, WAV, M4A, AAC, OGG, FLAC")
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

#Preview {
    do {
        let schema = Schema([Record.self, AppSettings.self])
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
