//
//  ContentView.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI

// Define a simple structure for a record
struct Record: Identifiable, Hashable {
    let id = UUID()
    let name: String
    // Add sample date and duration for UI display (can be replaced with real data later)
    let date: Date = Date()
    let duration: TimeInterval = Double.random(in: 30...300) // Random duration between 30s and 5m
    let hasTranscription: Bool = Bool.random() // Randomly decide if transcription is ready
}

// Helper to format duration
func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration) ?? "0s"
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedRecord: Record? = nil // State to manage which detail view to show

    // Sample data for the list
    @State private var records = [
        Record(name: "Meeting Notes 2024-04-21"),
        Record(name: "Idea Brainstorm"),
        Record(name: "Lecture Recording"),
        Record(name: "Quick Memo"),
        Record(name: "Project Update")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Picker for top navigation
            Picker("View", selection: $selectedTab) {
                Text("Records").tag(0) // Using simple text as Label in Picker tag is not standard
                Text("Settings").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 10) // Add slight top padding
            .padding(.bottom, 5) // Add padding below picker

            Divider()

            // Content based on selection
            if selectedTab == 0 {
                RecordsListView(records: records, selectedRecord: $selectedRecord)
            } else {
                SettingsView()
            }

            // Divider is removed from here as it's above the Quit button now

            // Quit button
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding([.horizontal, .bottom]) // Adjusted padding
            }
            .padding(.top, 5) // Add padding above the Quit button area
            .background(Color(NSColor.windowBackgroundColor)) // Ensure background matches window
        }
        // Using .sheet to present the detail view modally
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(record: record)
                // Set a minimum frame for the sheet
                .frame(minWidth: 400, minHeight: 450)
        }
        // Ensure the main VStack takes up available space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Separate view for the list of records
struct RecordsListView: View {
    let records: [Record]
    @Binding var selectedRecord: Record? // Binding to control the sheet presentation

    var body: some View {
        // Use a Group to switch between List and Empty State
        Group {
            if records.isEmpty {
                VStack {
                    Spacer() // Pushes content to center
                    Image(systemName: "list.bullet.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)
                    Text("No recordings yet.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Your recordings will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer() // Pushes content to center
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack fills space
            } else {
                List {
                    ForEach(records) { record in
                        RecordRow(record: record)
                            .contentShape(Rectangle()) // Make the whole row tappable
                            .onTapGesture {
                                selectedRecord = record // Set the selected record to show the sheet
                            }
                    }
                }
                .listStyle(InsetListStyle()) // A slightly more modern list style
                // Removed top padding here, handled by Picker container now
            }
        }
    }
}

// View for a single row in the records list
struct RecordRow: View {
    let record: Record

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.name).font(.headline)
                HStack {
                    Text(record.date, style: .date)
                    Text("-")
                    Text(formatDuration(record.duration))
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            if record.hasTranscription {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.blue)
                    .help("Transcription available")
            } else {
                Image(systemName: "text.bubble")
                    .foregroundColor(.gray)
                    .help("Transcription pending")
            }
        }
        .padding(.vertical, 4)
    }
}

// Separate view for Settings
struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings content would go here")
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding() // Add padding to the content
        // Ensure SettingsView fills the space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Detail view for a single record (remains largely the same)
struct RecordDetailView: View {
    let record: Record
    @Environment(\.dismiss) var dismiss // Environment value to dismiss the sheet

    var body: some View {
        VStack(alignment: .leading) {
            // Header with Title and Close button
            HStack {
                Text(record.name).font(.title2)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle()) // Remove button chrome
            }
            .padding(.bottom)
            
            // Play Button
            Button {
                // Action for playing audio (to be implemented)
                print("Play button clicked for \(record.name)")
            } label: {
                Label("Play Recording", systemImage: "play.circle")
            }
            .padding(.bottom, 5)
            
            // Duration Info
            Text("Duration: \(formatDuration(record.duration))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider().padding(.vertical, 5)
            
            Text("Transcription:")
                .font(.headline)
            
            ScrollView {
                Text(record.hasTranscription ? "This is the placeholder for the transcription text. It would appear here once the audio is processed...\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua." : "Transcription not available yet.")
                    .foregroundColor(record.hasTranscription ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
            }
            .frame(maxHeight: .infinity) // Allow scroll view to expand
            .border(Color.gray.opacity(0.5))
            
            Spacer() // Pushes content to the top, but ScrollView now expands
        }
        .padding()
        // Removed navigationTitle as it's presented in a sheet
    }
}

#Preview {
    ContentView()
}
