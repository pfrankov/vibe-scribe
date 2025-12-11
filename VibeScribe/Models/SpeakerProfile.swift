//
//  SpeakerProfile.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 20.05.2025.
//

import Foundation
import SwiftData

@Model
final class SpeakerProfile: Identifiable {
    var id: UUID
    var speakerId: String
    var displayName: String
    var colorHue: Double
    var embedding: [Float]
    var totalDuration: TimeInterval
    var createdAt: Date
    var updatedAt: Date
    var lastSeenAt: Date
    var updateCount: Int
    var isPermanent: Bool
    var isUserRenamed: Bool
    @Relationship(inverse: \RecordSpeakerSegment.speaker) var segments: [RecordSpeakerSegment]

    init(
        id: UUID = UUID(),
        speakerId: String,
        displayName: String,
        colorHue: Double,
        embedding: [Float],
        totalDuration: TimeInterval = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSeenAt: Date = Date(),
        updateCount: Int = 1,
        isPermanent: Bool = false,
        isUserRenamed: Bool = false,
        segments: [RecordSpeakerSegment] = []
    ) {
        self.id = id
        self.speakerId = speakerId
        self.displayName = displayName
        self.colorHue = colorHue
        self.embedding = embedding
        self.totalDuration = totalDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.updateCount = updateCount
        self.isPermanent = isPermanent
        self.isUserRenamed = isUserRenamed
        self.segments = segments
    }
}

extension SpeakerProfile {
    static func defaultHue(for speakerId: String) -> Double {
        let hash = abs(speakerId.hashValue % 360)
        return Double(hash) / 360.0
    }

    /// Generates a stable but distinctive color index (0...1) from the speaker ID when no explicit hue is stored.
    var accentHue: Double {
        if colorHue > 0, colorHue <= 1 {
            return colorHue
        }
        return Self.defaultHue(for: speakerId)
    }
}
