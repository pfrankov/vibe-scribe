//
//  Record.swift
//  VibeScribe
//
//  Created by System on 13.04.2025.
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

    init(id: UUID = UUID(), name: String, fileURL: URL?, date: Date = Date(), duration: TimeInterval, hasTranscription: Bool = false, transcriptionText: String? = nil) {
        self.id = id
        self.name = name
        self.fileURL = fileURL // Store the URL object
        self.date = date
        self.duration = duration
        self.hasTranscription = hasTranscription
        self.transcriptionText = transcriptionText
    }
}

// Helper to format duration
func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration) ?? "0s"
} 