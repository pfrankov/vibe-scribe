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
                TextField(AppLanguage.localized("name"), text: $editingName)
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

            if !record.tags.isEmpty {
                Text(singleLineTags)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel(
                        Text(
                            String(
                                format: AppLanguage.localized("tags.arg1", comment: "Accessibility label listing tags"),
                                record.sortedTags.map { "#\($0.name)" }.joined(separator: "  ")
                            )
                        )
                    )
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

    private var singleLineTags: String {
        record.sortedTags.map { "#\($0.name)" }.joined(separator: "  ")
    }


    @ViewBuilder
    private var iconGroup: some View {
        let showsSummary = record.hasSummary
        let showsTranscription = !showsSummary && record.hasTranscription

        HStack(spacing: 6) {
            if record.hasSystemAudio {
                icon(systemName: "speaker.wave.2", helpText: AppLanguage.localized("includes.system.audio"))
            }

            if showsSummary {
                icon(systemName: "sparkles", helpText: AppLanguage.localized("summary.available"))
            } else if showsTranscription {
                icon(systemName: "text.alignleft", helpText: AppLanguage.localized("transcription.available"))
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
        // Trim whitespace and ensure the final name is non-empty
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.debug("Name empty after trimming, reverting", category: .ui)
            isEditing = false
            isNameFieldFocused = false
            return
        }

        if trimmed != record.name {
            Logger.info("Saving new name: \(trimmed) for record ID: \(record.id)", category: .data)
            record.name = trimmed
        } else {
            Logger.debug("Name unchanged, reverting", category: .ui)
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
    
    // Helper: single, shared DateFormatter to avoid allocations per row
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }
} 
