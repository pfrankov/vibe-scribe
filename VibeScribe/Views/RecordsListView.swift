//
//  RecordsListView.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
//

import SwiftUI
import SwiftData

// Separate view for the list of records
struct RecordsListView: View {
    // Use the actual Record model type
    let records: [Record]
    @Binding var selectedRecord: Record?
    @Binding var showRecordingSheet: Bool
    var onDelete: (Record) -> Void

    var body: some View {
        VStack {
            // Header with New Recording Button
            HStack {
                Text("All Recordings").font(.title2).bold()
                Spacer()
                Button {
                    showRecordingSheet = true
                } label: {
                    Label("New Recording", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PlainButtonStyle()) // Use plain style for consistency
                .labelStyle(.titleAndIcon) // Show both title and icon
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 5)

            // Use a Group to switch between List and Empty State
            Group {
                if records.isEmpty {
                    VStack {
                        Spacer() // Pushes content to center
                        Image(systemName: "mic.slash") // More relevant icon
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)
                        Text("No recordings yet.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap '+' to create your first recording.") // Actionable text
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer() // Pushes content to center
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack fills space
                } else {
                    List {
                        // Iterate over the fetched records
                        ForEach(records) { record in
                            RecordRow(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecord = record // Set the selected record to show the detail sheet
                                }
                                // Updated Context Menu (Removed Rename)
                                .contextMenu {
                                    // <<< Removed Rename Button >>>
                                    // Button { ... } label: { ... }

                                    Button(role: .destructive) {
                                        onDelete(record) // <<< Call the delete closure
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(InsetListStyle()) // A slightly more modern list style
                    // Removed top padding here, handled by VStack container now
                }
            }
        }
    }
} 