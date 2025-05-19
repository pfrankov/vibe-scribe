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
    @State private var selectedTab = 0
    @State private var selectedRecord: Record? = nil // State to manage which detail view to show
    @State private var isShowingRecordingSheet = false // State for the recording sheet

    // Fetch records from SwiftData, sorted by date descending
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]

    // Date formatter for default recording names
    private var recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        // Main container with adjusted spacing
        VStack(spacing: 0) { // Remove default VStack spacing, manage manually

            // Custom Tab Bar Area
            HStack(spacing: 0) { // No spacing between buttons
                TabBarButton(title: "Records", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabBarButton(title: "Settings", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal, 16) // Стандартный отступ macOS
            .padding(.top, 12)    // Стандартный отступ macOS
            .padding(.bottom, 4) // Уменьшенный отступ до разделителя

            Divider()
                .padding(.horizontal, 12) // Слегка уменьшенный отступ для разделителя

            // Content Area 
            ZStack { // Use ZStack for smooth transitions
                // Records view - только показываем когда выбрана эта вкладка
                if selectedTab == 0 {
                    VStack(spacing: 0) {
                        // Header with New Recording Button
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

                        // Split view with sidebar list and detail view
                        NavigationSplitView {
                            Group {
                                if records.isEmpty {
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
                                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                        }
                                    }
                                    .listStyle(.plain)
                                    .scrollDismissesKeyboard(.immediately)
                                }
                            }
                        } detail: {
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
                        .navigationSplitViewStyle(.balanced)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                    // Automatically select first record if available
                    .onAppear {
                        if selectedRecord == nil && !records.isEmpty {
                            selectedRecord = records.first
                        }
                    }
                    .onChange(of: records) { oldRecords, newRecords in
                        if selectedRecord == nil && !newRecords.isEmpty {
                            selectedRecord = newRecords.first
                        }
                    }
                } else {
                    SettingsView()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedTab) // Более быстрая анимация
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure content fills space

            // Footer Area
            VStack(spacing: 0) { // Use VStack for Divider only
                Divider()
                    .padding(.horizontal, 12) // Соответствует верхнему разделителю
            }
            // Ensure Footer doesn't absorb extra space meant for content
            .layoutPriority(0) // Lower priority than the content ZStack
        }
        // Sheet for Recording
        .sheet(isPresented: $isShowingRecordingSheet) {
            // Pass the model context to RecordingView
             RecordingView() 
                 .frame(width: 350, height: 320) // Фиксированный размер для единообразия
        }
    }

    // --- Record Management Functions ---

    // Function to delete a record
    private func deleteRecord(_ recordToDelete: Record) {
        // 1. Delete the associated audio file if it exists
        if let fileURL = recordToDelete.fileURL {
             do {
                 if FileManager.default.fileExists(atPath: fileURL.path) {
                     try FileManager.default.removeItem(at: fileURL)
                     print("Successfully deleted audio file: \(fileURL.path)")
                 } else {
                     print("Audio file not found, skipping deletion: \(fileURL.path)")
                 }
             } catch {
                 print("Error deleting audio file \(fileURL.path): \(error.localizedDescription)")
                 // Consider showing an error to the user
             }
         } else {
             print("Record \(recordToDelete.name) has no associated fileURL.")
         }

        // 2. Remove the record from the model context
        print("Deleting record from context: \(recordToDelete.name)")
        modelContext.delete(recordToDelete)
        
        // 3. If the deleted record was currently selected, deselect it
        if selectedRecord?.id == recordToDelete.id {
            selectedRecord = nil
        }
    }
}

#Preview {
    // --- Updated Preview ---
    // Need to provide a sample model container for the preview
    do {
        let schema = Schema([Record.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true) // Use in-memory for preview
        let container = try ModelContainer(for: schema, configurations: [config])
        
        // Optional: Add sample data to the preview container
        let sampleRecord = Record(name: "Preview Record", fileURL: nil, duration: 65.0)
        container.mainContext.insert(sampleRecord)
        
        // Add sample settings
        let settings = AppSettings()
        container.mainContext.insert(settings)

        return ContentView()
            .modelContainer(container) // Provide the container to the preview
    } catch {
        // Handle error creating the preview container
        return Text("Failed to create preview: \(error.localizedDescription)")
    }
} 