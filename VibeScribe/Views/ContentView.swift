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
    @State private var isShowingRecordingSheet = false
    @State private var isShowingSettings = false
    @State private var shouldScrollToSelectedRecord = false
    @StateObject private var importManager = AudioFileImportManager()
    @State private var isDragOver = false

    @Query(sort: \Record.date, order: .reverse) private var records: [Record]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("All Recordings")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                
                Button {
                    presentRecordingOverlay()
                } label: {
                    Label("New Recording", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.horizontal, 12)

            // Main content
            NavigationSplitView {
                recordsList
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
            if let recordId = notification.userInfo?["recordId"] as? UUID {
                // Fetch the record directly from the model context to ensure it's found
                let fetchDescriptor = FetchDescriptor<Record>(predicate: #Predicate { record in record.id == recordId })
                do {
                    let matchingRecords = try modelContext.fetch(fetchDescriptor)
                    if let newRecord = matchingRecords.first {
                        shouldScrollToSelectedRecord = true // Set flag to scroll for new records
                        selectedRecord = newRecord
                        print("ContentView: Auto-selected new record by fetching ID: \(newRecord.id) Name: \(newRecord.name)")
                    } else {
                        // This case should ideally not happen if the record was saved successfully
                        print("ContentView ERROR: New record with ID \(recordId) not found via fetch immediately after creation.")
                    }
                } catch {
                    print("ContentView ERROR: Failed to fetch new record by ID \(recordId): \(error.localizedDescription)")
                }
            }
        }
        .onChange(of: records) { _, newRecords in
            if selectedRecord == nil && !newRecords.isEmpty {
                // Don't scroll when auto-selecting first record on app launch
                selectedRecord = newRecords.first
                print("ContentView: Auto-selected first record without scrolling")
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
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var recordsList: some View {
        if records.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                List(selection: $selectedRecord) {
                    ForEach(records) { record in
                        RecordRow(record: record)
                            .tag(record)
                            .id(record.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: selectedRecord) { oldValue, newValue in
                    if let recordToScrollTo = newValue, shouldScrollToSelectedRecord {
                        print("ContentView: selectedRecord changed to \(recordToScrollTo.name) (ID: \(recordToScrollTo.id)), scrolling to new record.")
                        withAnimation {
                            proxy.scrollTo(recordToScrollTo.id, anchor: .top)
                        }
                        shouldScrollToSelectedRecord = false // Reset flag after scrolling
                    } else if newValue != nil {
                        print("ContentView: selectedRecord changed to \(newValue!.name) (ID: \(newValue!.id)), not scrolling (user selection).")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
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
    
    @ViewBuilder
    private var recordDetail: some View {
        if let selectedRecord = selectedRecord {
            RecordDetailView(record: selectedRecord) { _ in
                self.selectedRecord = nil
            }
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
            print("Main window assigned to AppDelegate.")
        } else if let anyWindow = NSApplication.shared.windows.first {
            (NSApplication.shared.delegate as? AppDelegate)?.mainWindow = anyWindow
            print("Fallback window assigned to AppDelegate.")
        } else {
            print("ContentView onAppear: No window found to assign to AppDelegate.")
        }
    }
    
    private func selectFirstRecordIfNeeded() {
        if selectedRecord == nil && !records.isEmpty {
            // Don't scroll when auto-selecting first record on app launch
            selectedRecord = records.first
            print("ContentView: selectFirstRecordIfNeeded - Auto-selected first record without scrolling")
        }
    }

    private func deleteRecord(_ recordToDelete: Record) {
        if let fileURL = recordToDelete.fileURL {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("Successfully deleted audio file: \(fileURL.path)")
            } catch {
                print("Error deleting audio file \(fileURL.path): \(error.localizedDescription)")
            }
        } else {
            print("Record \(recordToDelete.name) has no associated fileURL.")
        }

        modelContext.delete(recordToDelete)
        
        do {
            try modelContext.save()
            print("Record \(recordToDelete.name) deleted successfully.")
        } catch {
            print("Error deleting record: \(error.localizedDescription)")
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
