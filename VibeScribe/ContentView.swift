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
    let hasTranscription: Bool = Bool.random() // Randomly decide if transcription is ready
}

struct ContentView: View {
    @State private var selectedTab = 0
    
    // Sample data for the list
    @State private var records = [
        Record(name: "Meeting Notes 2024-04-21"),
        Record(name: "Idea Brainstorm"),
        Record(name: "Lecture Recording")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("Records").tag(0)
                    Text("Settings").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top) // Add padding top
            }
            
            Divider()
            
            // Tab content
            TabView(selection: $selectedTab) {
                // Records Tab - Now with Navigation
                NavigationView {
                    List {
                        ForEach(records) { record in
                            NavigationLink(destination: RecordDetailView(record: record)) {
                                Text(record.name)
                            }
                        }
                    }
                    .listStyle(SidebarListStyle()) // Use a style suitable for navigation
                    .navigationTitle("Records") // Add a title to the navigation view
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(0)
                
                // Settings Tab
                VStack {
                    Text("Settings content would go here")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tag(1)
            }
            
            Divider()
            
            // Quit button
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding()
            }
        }
        // Adjust overall frame slightly if needed
        // .frame(width: 320, height: 400) // Optional: Adjust frame
    }
}

// Detail view for a single record (placeholder)
struct RecordDetailView: View {
    let record: Record
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(record.name).font(.title2)
            
            Button {
                // Action for playing audio (to be implemented)
                print("Play button clicked for \(record.name)")
            } label: {
                Label("Play Recording", systemImage: "play.circle")
            }
            
            Divider()
            
            Text("Transcription:")
                .font(.headline)
            
            ScrollView {
                Text(record.hasTranscription ? "This is the placeholder for the transcription text. It would appear here once the audio is processed..." : "Transcription not available yet.")
                    .foregroundColor(record.hasTranscription ? .primary : .secondary)
            }
            .frame(height: 100) // Limit height for the scroll view
            .border(Color.gray.opacity(0.5)) // Visual cue for the text area
            
            Spacer() // Pushes content to the top
        }
        .padding()
        .navigationTitle("Details") // Title for the detail view navigation bar
    }
}

#Preview {
    ContentView()
}
