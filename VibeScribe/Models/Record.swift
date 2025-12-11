//
//  Record.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import SwiftData

// --- SwiftData Model ---
@Model
final class Record: Identifiable {
    var id: UUID
    var name: String
    var fileURL: URL?
    var date: Date
    var duration: TimeInterval
    var hasTranscription: Bool
    var transcriptionText: String?
    var summaryText: String?
    var includesSystemAudio: Bool?
    @Relationship(deleteRule: .nullify, inverse: \Tag.records) var tags: [Tag]
    @Relationship(deleteRule: .cascade, inverse: \RecordSpeakerSegment.record) var speakerSegments: [RecordSpeakerSegment]
    var lastDiarizationAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        fileURL: URL?,
        date: Date = Date(),
        duration: TimeInterval,
        hasTranscription: Bool = false,
        transcriptionText: String? = nil,
        summaryText: String? = nil,
        includesSystemAudio: Bool = false,
        tags: [Tag] = [],
        speakerSegments: [RecordSpeakerSegment] = [],
        lastDiarizationAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.fileURL = fileURL // Store the URL object
        self.date = date
        self.duration = duration
        self.hasTranscription = hasTranscription
        self.transcriptionText = transcriptionText
        self.summaryText = summaryText
        self.includesSystemAudio = includesSystemAudio
        self.tags = tags
        self.speakerSegments = speakerSegments
        self.lastDiarizationAt = lastDiarizationAt
    }
}

// MARK: - Extensions

extension Record {
    /// Computed property to handle system audio flag with fallback
    var hasSystemAudio: Bool {
        return includesSystemAudio ?? false
    }

    /// Indicates whether the record already has a non-empty summary
    var hasSummary: Bool {
        guard let summaryText, !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    /// Indicates whether diarization has been performed for this record
    var hasDiarization: Bool {
        !speakerSegments.isEmpty
    }
    
    /// Formatted duration string for display purposes
    var formattedDuration: String {
        duration.clockString
    }
    
    /// Check if the record has a valid file
    var hasValidFile: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Safe file size calculation
    var fileSize: Int64 {
        guard let url = fileURL else { return 0 }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Tags sorted using localized, case-insensitive comparison so UI chips appear predictable
    var sortedTags: [Tag] {
        tags.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
