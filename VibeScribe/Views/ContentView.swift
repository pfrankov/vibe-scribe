//
//  ContentView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRecord: Record? = nil
    @State private var isShowingRecordingSheet = false
    @State private var isShowingSettings = false
    @State private var shouldScrollToSelectedRecord = false

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
                    isShowingRecordingSheet = true
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
                isShowingRecordingSheet = true
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRecordCreated"))) { notification in
            if let recordId = notification.userInfo?["recordId"] as? UUID {
                // Fetch the record directly from the model context to ensure it's found
                let fetchDescriptor = FetchDescriptor<Record>(predicate: #Predicate { record in record.id == recordId })
                do {
                    let matchingRecords = try modelContext.fetch(fetchDescriptor)
                    if let newRecord = matchingRecords.first {
                        shouldScrollToSelectedRecord = true // Set flag to scroll for new records
                        selectedRecord = newRecord
                        print("ContentView: Auto-selected new record by fetching ID: \\(newRecord.id) Name: \\(newRecord.name)")
                    } else {
                        // This case should ideally not happen if the record was saved successfully
                        print("ContentView ERROR: New record with ID \\(recordId) not found via fetch immediately after creation.")
                    }
                } catch {
                    print("ContentView ERROR: Failed to fetch new record by ID \\(recordId): \\(error.localizedDescription)")
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
        .sheet(isPresented: $isShowingRecordingSheet) {
            RecordingView() 
                .frame(width: 350, height: 320)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .frame(width: 600, height: 500)
        }
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
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteRecord(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: selectedRecord) { oldValue, newValue in
                    if let recordToScrollTo = newValue, shouldScrollToSelectedRecord {
                        print("ContentView: selectedRecord changed to \\(recordToScrollTo.name) (ID: \\(recordToScrollTo.id)), scrolling to new record.")
                        withAnimation {
                            proxy.scrollTo(recordToScrollTo.id, anchor: .top)
                        }
                        shouldScrollToSelectedRecord = false // Reset flag after scrolling
                    } else if newValue != nil {
                        print("ContentView: selectedRecord changed to \\(newValue!.name) (ID: \\(newValue!.id)), not scrolling (user selection).")
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
            RecordDetailView(record: selectedRecord)
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