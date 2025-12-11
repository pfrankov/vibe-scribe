//
//  RecordSpeakerSegment.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 20.05.2025.
//

import Foundation
import SwiftData

@Model
final class RecordSpeakerSegment: Identifiable {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var qualityScore: Double
    @Relationship var record: Record?
    @Relationship var speaker: SpeakerProfile?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        qualityScore: Double,
        record: Record? = nil,
        speaker: SpeakerProfile? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.qualityScore = qualityScore
        self.record = record
        self.speaker = speaker
    }
}

extension RecordSpeakerSegment {
    var duration: TimeInterval {
        endTime - startTime
    }
}
