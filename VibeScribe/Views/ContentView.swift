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
        .onChange(of: records) { _, newRecords in
            if selectedRecord == nil && !newRecords.isEmpty {
                selectedRecord = newRecords.first
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
            List(selection: $selectedRecord) {
                ForEach(records) { record in
                    RecordRow(record: record)
                        .tag(record)
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
            selectedRecord = records.first
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