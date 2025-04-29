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
            .padding(.horizontal) // Padding for the whole tab bar
            .padding(.top, 10)    // Padding above the tab bar
            .padding(.bottom, 5) // Space between tabs and divider

            Divider()
                .padding(.horizontal) // Keep divider padding

            // Content Area with Animation
            ZStack { // Use ZStack for smooth transitions
                if selectedTab == 0 {
                    RecordsListView(
                        records: records,
                        selectedRecord: $selectedRecord,
                        showRecordingSheet: $isShowingRecordingSheet,
                        onDelete: deleteRecord
                    )
                        .transition(.opacity) // Fade transition
                } else {
                    SettingsView()
                        .transition(.opacity) // Fade transition
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab) // Apply animation to content switching
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure content fills space

            // Footer Area
            VStack(spacing: 0) { // Use VStack for Divider + Button row
                Divider()
                    .padding(.horizontal) // Match top divider padding

                // Quit button row
                HStack {
                    Spacer() // Push button to the right
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    // Add specific padding for the button if needed, or rely on HStack padding
                    // .padding(.trailing)
                }
                .padding(.vertical, 10) // Padding for the quit button row
                .padding(.horizontal)    // Horizontal padding for the row
                .background(Color(NSColor.windowBackgroundColor)) // Ensure background matches window
            }
            // Ensure Footer doesn't absorb extra space meant for content
            .layoutPriority(0) // Lower priority than the content ZStack
        }
        // Sheet for Record Detail
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(record: record)
                .frame(minWidth: 400, minHeight: 450)
        }
        // Sheet for Recording
        .sheet(isPresented: $isShowingRecordingSheet) {
            // Pass the model context to RecordingView
             RecordingView() 
                 .frame(minWidth: 350, minHeight: 300)
        }
    }

    // --- Record Management Functions ---

    // Function to delete a record
    private func deleteRecord(recordToDelete: Record) {
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
        
        // Optional: Explicitly save changes, though autosave is common
        // do {
        //     try modelContext.save()
        //     print("Record deleted and context saved.")
        // } catch {
        //     print("Error saving context after deleting record: \(error)")
        //     // Handle error - maybe show an alert
        // }

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
        let schema = Schema([Record.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true) // Use in-memory for preview
        let container = try ModelContainer(for: schema, configurations: [config])
        
        // Optional: Add sample data to the preview container
        let sampleRecord = Record(name: "Preview Record", fileURL: nil, duration: 65.0)
        container.mainContext.insert(sampleRecord)

        return ContentView()
            .modelContainer(container) // Provide the container to the preview
    } catch {
        // Handle error creating the preview container
        return Text("Failed to create preview: \(error.localizedDescription)")
    }
} 