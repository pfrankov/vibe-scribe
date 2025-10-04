//
//  RecordRow.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData

// View for a single row in the records list
struct RecordRow: View {
    // Use @Bindable for direct modification of @Model
    @Bindable var record: Record 

    @State private var isEditing: Bool = false
    @State private var editingName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ZStack to overlay TextField on Text for editing
            ZStack(alignment: .leading) {
                // --- TextField (Visible when editing) ---
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain) // Standard plain style
                    .focused($isNameFieldFocused)
                    .onSubmit { // Handle Enter key press
                        saveName()
                    }
                    // Prevent clicks on TextField from selecting the row
                    .onTapGesture {}
                    // Apply same font/padding as Text for alignment
                    .font(.headline) // Standard headline
                    // Make TextField visible only when editing
                    .opacity(isEditing ? 1 : 0)
                    .disabled(!isEditing) // Disable when not editing

                // --- Text (Visible when not editing) ---
                Text(record.name)
                    .font(.headline) // Standard headline
                    .lineLimit(1) // Limit to one line
                    // Make Text visible only when *not* editing
                    .opacity(isEditing ? 0 : 1)
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .imageScale(.small)
                        Text(formattedDateTime(record.date))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .imageScale(.small)
                        Text(record.duration.clockString)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                iconGroup
            }
        }
        .padding(.vertical, 8) // Increase padding for better readability
        .contentShape(Rectangle()) // Ensures that the entire row is clickable
        // Detect when the text field loses focus to cancel editing
        .onChange(of: isNameFieldFocused) { oldValue, newValue in
            if !newValue && isEditing { // If focus is lost AND we were editing
                // This handles clicking away or pressing Esc (which also removes focus)
                cancelEditing()
            }
        }
    }

    @ViewBuilder
    private var iconGroup: some View {
        let showsSummary = record.hasSummary
        let showsTranscription = !showsSummary && record.hasTranscription

        HStack(spacing: 6) {
            if record.hasSystemAudio {
                icon(systemName: "speaker.wave.2", helpText: "Includes system audio")
            }

            if showsSummary {
                icon(systemName: "sparkles", helpText: "Summary available")
            } else if showsTranscription {
                icon(systemName: "text.alignleft", helpText: "Transcription available")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func icon(systemName: String, helpText: String) -> some View {
        Image(systemName: systemName)
            .imageScale(.small)
            .frame(width: 12, height: 12)
            .help(helpText)
            .accessibilityLabel(Text(helpText))
    }

    private func startEditing() {
        editingName = record.name // Initialize TextField with current name
        isEditing = true
        // Delay focus slightly to ensure TextField is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
             isNameFieldFocused = true
        }
        Logger.debug("Started editing record: \(record.name)", category: .ui)
    }

    private func saveName() {
        // Only save if the name is valid and actually changed
        if !editingName.isEmpty && editingName != record.name {
            Logger.info("Saving new name: \(editingName) for record ID: \(record.id)", category: .data)
            record.name = editingName
            // SwiftData @Bindable should handle the save automatically
        } else {
            Logger.debug("Name unchanged or empty, reverting", category: .ui)
        }
        isEditing = false // Exit editing mode
        isNameFieldFocused = false // Ensure focus is released
    }

    private func cancelEditing() {
        Logger.debug("Cancelled editing for record: \(record.name)", category: .ui)
        isEditing = false // Exit editing mode
        isNameFieldFocused = false // Ensure focus is released
        // No need to reset editingName, it will be re-initialized on next edit
    }
    
    // Helper function to format the date with time
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 
