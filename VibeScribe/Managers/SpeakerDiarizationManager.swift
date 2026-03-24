//
//  SpeakerDiarizationManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 20.05.2025.
//

import Foundation
import SwiftData
import FluidAudio

@MainActor
final class SpeakerDiarizationManager: ObservableObject {
    struct State: Equatable {
        var isProcessing: Bool = false
        var error: String? = nil
        var lastRunAt: Date? = nil
    }

    static let shared = SpeakerDiarizationManager()

    @Published private(set) var states: [UUID: State] = [:]

    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    func state(for recordID: UUID) -> State {
        states[recordID] ?? State()
    }

    func diarize(record: Record, in context: ModelContext, force: Bool = false) {
        let recordID = record.id

        if let task = activeTasks[recordID] {
            if force {
                task.cancel()
            } else {
                return
            }
        }

        guard let fileURL = record.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            updateState(for: recordID) { state in
                state.error = AppLanguage.localized("audio.file.not.found.on.disk")
                state.isProcessing = false
            }
            return
        }

        if UITestMockPipeline.isEnabled {
            runMockDiarization(record: record, in: context, recordID: recordID)
            return
        }

        updateState(for: recordID) { state in
            state.isProcessing = true
            state.error = nil
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // When force re-running, only pass permanent (user-labeled) speakers so that
                // the diarizer can freely reorganize auto-detected speakers.
                let known = fetchKnownSpeakers(for: record, permanentOnly: force)
                let output = try await SpeakerDiarizationService.shared.diarize(
                    audioURL: fileURL,
                    knownSpeakers: known
                )
                try await MainActor.run {
                    try self.apply(output: output, to: record, in: context)
                    self.updateState(for: recordID) { state in
                        state.isProcessing = false
                        state.error = nil
                        state.lastRunAt = record.lastDiarizationAt
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.updateState(for: recordID) { state in
                        state.isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateState(for: recordID) { state in
                        state.isProcessing = false
                        state.error = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                self.activeTasks[recordID] = nil
            }
        }

        activeTasks[recordID] = task
    }

    func mergeSpeakers(
        target: SpeakerProfile,
        merging: [SpeakerProfile],
        for record: Record,
        in context: ModelContext
    ) {
        let mergingSet = Set(merging.map(\.id))
        guard !mergingSet.isEmpty else { return }

        // Reassign segments in this record
        for segment in record.speakerSegments {
            guard let speaker = segment.speaker, mergingSet.contains(speaker.id) else { continue }
            segment.speaker = target
        }

        // Update target aggregate data
        let totalMergedDuration = merging.reduce(TimeInterval(0)) { $0 + $1.totalDuration }
        target.totalDuration += totalMergedDuration
        target.lastSeenAt = Date()
        target.updatedAt = Date()

        // Average embeddings if sizes match
        if merging.allSatisfy({ $0.embedding.count == target.embedding.count }) {
            let count = target.embedding.count
            var accumulator = target.embedding
            for speaker in merging {
                for i in 0..<count {
                    accumulator[i] += speaker.embedding[i]
                }
            }
            let divisor = Float(merging.count + 1)
            target.embedding = accumulator.map { $0 / divisor }
        }

        // Remove merged profiles that have no remaining segments anywhere
        for speaker in merging {
            let remainingSegments = speaker.segments.filter { $0.speaker?.id == speaker.id }
            if remainingSegments.isEmpty {
                context.delete(speaker)
            }
        }

        record.lastDiarizationAt = Date()

        do {
            pruneOrphanedProfiles(in: context)
            try context.save()
        } catch {
            Logger.error("Failed to merge speakers", error: error, category: .general)
        }
    }

    func clearDiarization(for record: Record, in context: ModelContext) {
        if let task = activeTasks[record.id] {
            task.cancel()
            activeTasks[record.id] = nil
        }

        let existingSegments = Array(record.speakerSegments)
        guard !existingSegments.isEmpty || record.lastDiarizationAt != nil || states[record.id] != nil else {
            return
        }

        for segment in existingSegments {
            context.delete(segment)
        }
        record.speakerSegments.removeAll()
        record.lastDiarizationAt = nil

        do {
            pruneOrphanedProfiles(in: context)
            try context.save()
            updateState(for: record.id) { state in
                state.isProcessing = false
                state.error = nil
                state.lastRunAt = nil
            }
        } catch {
            Logger.error("Failed to clear diarization", error: error, category: .general)
        }
    }

    // MARK: - Private

    private func runMockDiarization(record: Record, in context: ModelContext, recordID: UUID) {
        updateState(for: recordID) { state in
            state.isProcessing = true
            state.error = nil
        }

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                try await UITestMockPipeline.sleepForProcessingStep()
                let mockResult = UITestMockPipeline.diarizationResult()

                try await MainActor.run {
                    switch mockResult {
                    case .none:
                        try self.applyMockSpeakerSegments([], to: record, in: context)
                        self.updateState(for: recordID) { state in
                            state.isProcessing = false
                            state.error = nil
                            state.lastRunAt = record.lastDiarizationAt
                        }
                    case .speakers(let segments):
                        try self.applyMockSpeakerSegments(segments, to: record, in: context)
                        self.updateState(for: recordID) { state in
                            state.isProcessing = false
                            state.error = nil
                            state.lastRunAt = record.lastDiarizationAt
                        }
                    case .failure(let token):
                        try self.applyMockSpeakerSegments([], to: record, in: context)
                        self.updateState(for: recordID) { state in
                            state.isProcessing = false
                            state.error = token
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.updateState(for: recordID) { state in
                        state.isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateState(for: recordID) { state in
                        state.isProcessing = false
                        state.error = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                self.activeTasks[recordID] = nil
            }
        }

        activeTasks[recordID] = task
    }

    private func fetchKnownSpeakers(for record: Record, permanentOnly: Bool = false) -> [SpeakerSnapshot] {
        speakerProfiles(for: record).compactMap { profile in
            if permanentOnly && !profile.isPermanent { return nil }
            guard profile.embedding.count == SpeakerManager.embeddingSize else { return nil }
            return SpeakerSnapshot(
                id: profile.speakerId,
                name: profile.displayName,
                embedding: profile.embedding,
                duration: Float(profile.totalDuration),
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt,
                isPermanent: profile.isPermanent
            )
        }
    }

    private func apply(output: SpeakerDiarizationOutput, to record: Record, in context: ModelContext) throws {
        let now = Date()

        let existingProfiles = speakerProfiles(for: record)
        var profilesByID: [String: SpeakerProfile] = [:]
        for profile in existingProfiles {
            profilesByID[profile.speakerId] = profile
        }

        // Update or create profiles from diarizer output
        for (_, speaker) in output.speakers {
            let profile: SpeakerProfile
            if let existing = profilesByID[speaker.id] {
                profile = existing
            } else {
                let hue = SpeakerProfile.defaultHue(for: speaker.id)
                profile = SpeakerProfile(
                    speakerId: speaker.id,
                    displayName: speaker.name,
                    colorHue: hue,
                    embedding: speaker.embedding,
                    totalDuration: TimeInterval(speaker.duration),
                    createdAt: speaker.createdAt,
                    updatedAt: speaker.updatedAt,
                    lastSeenAt: now,
                    updateCount: speaker.updateCount,
                    isPermanent: speaker.isPermanent,
                    isUserRenamed: false
                )
                context.insert(profile)
                profilesByID[speaker.id] = profile
            }

            if !profile.isUserRenamed {
                profile.displayName = speaker.name
            }

            profile.embedding = speaker.embedding
            profile.totalDuration = TimeInterval(speaker.duration)
            profile.updatedAt = speaker.updatedAt
            profile.lastSeenAt = now
            profile.updateCount = speaker.updateCount
            profile.isPermanent = speaker.isPermanent
            if profile.colorHue <= 0 || profile.colorHue > 1 {
                profile.colorHue = SpeakerProfile.defaultHue(for: profile.speakerId)
            }
        }

        // Remove old segments
        for segment in record.speakerSegments {
            context.delete(segment)
        }
        record.speakerSegments.removeAll()

        // Attach new segments
        for segment in output.segments {
            let profile = profilesByID[segment.speakerId] ??
                SpeakerProfile(
                    speakerId: segment.speakerId,
                    displayName: segment.speakerId,
                    colorHue: SpeakerProfile.defaultHue(for: segment.speakerId),
                    embedding: segment.embedding
                )
            if profilesByID[segment.speakerId] == nil {
                profilesByID[segment.speakerId] = profile
                context.insert(profile)
            }

            let newSegment = RecordSpeakerSegment(
                startTime: TimeInterval(segment.startTimeSeconds),
                endTime: TimeInterval(segment.endTimeSeconds),
                qualityScore: Double(segment.qualityScore),
                record: record,
                speaker: profile
            )
            context.insert(newSegment)
            record.speakerSegments.append(newSegment)
        }

        record.lastDiarizationAt = now

        pruneOrphanedProfiles(in: context)
        try context.save()
    }

    private func applyMockSpeakerSegments(
        _ mockSegments: [UITestMockPipeline.SpeakerSegment],
        to record: Record,
        in context: ModelContext
    ) throws {
        let existingProfiles = speakerProfiles(for: record)

        for segment in record.speakerSegments {
            context.delete(segment)
        }
        record.speakerSegments.removeAll()

        var profilesByID: [String: SpeakerProfile] = [:]
        for profile in existingProfiles {
            profilesByID[profile.speakerId] = profile
        }

        var durationsBySpeakerID: [String: TimeInterval] = [:]
        let now = Date()

        for mock in mockSegments {
            let profile: SpeakerProfile
            if let existing = profilesByID[mock.speakerID] {
                profile = existing
            } else {
                profile = SpeakerProfile(
                    speakerId: mock.speakerID,
                    displayName: mock.speakerName,
                    colorHue: mock.hue,
                    embedding: mockEmbedding(for: mock.speakerID),
                    totalDuration: 0,
                    createdAt: now,
                    updatedAt: now,
                    lastSeenAt: now,
                    updateCount: 1,
                    isPermanent: false,
                    isUserRenamed: false
                )
                context.insert(profile)
                profilesByID[mock.speakerID] = profile
            }

            if !profile.isUserRenamed {
                profile.displayName = mock.speakerName
            }
            profile.colorHue = mock.hue
            profile.updatedAt = now
            profile.lastSeenAt = now
            profile.updateCount += 1

            let clampedStart = max(0, min(mock.startTime, record.duration))
            let rawEnd = max(mock.endTime, clampedStart + 0.05)
            let maxEnd = record.duration > 0 ? record.duration : rawEnd
            let clampedEnd = max(clampedStart + 0.05, min(rawEnd, maxEnd))

            let segment = RecordSpeakerSegment(
                startTime: clampedStart,
                endTime: clampedEnd,
                qualityScore: 0.95,
                record: record,
                speaker: profile
            )
            context.insert(segment)
            record.speakerSegments.append(segment)
            durationsBySpeakerID[mock.speakerID, default: 0] += max(0, clampedEnd - clampedStart)
        }

        for (speakerID, duration) in durationsBySpeakerID {
            guard let profile = profilesByID[speakerID] else { continue }
            profile.totalDuration = max(profile.totalDuration, duration)
        }

        record.lastDiarizationAt = now
        pruneOrphanedProfiles(in: context)
        try context.save()
    }

    private func speakerProfiles(for record: Record) -> [SpeakerProfile] {
        var seen: Set<UUID> = []
        return record.speakerSegments.compactMap(\.speaker).filter { profile in
            seen.insert(profile.id).inserted
        }
    }

    private func pruneOrphanedProfiles(in context: ModelContext) {
        let descriptor = FetchDescriptor<SpeakerProfile>()
        let profiles = (try? context.fetch(descriptor)) ?? []
        for profile in profiles where profile.segments.isEmpty {
            context.delete(profile)
        }
    }

    private func mockEmbedding(for speakerID: String) -> [Float] {
        let normalized = Float(abs(speakerID.hashValue % 1000)) / 1000.0
        return Array(repeating: normalized, count: SpeakerManager.embeddingSize)
    }

    private func updateState(for recordID: UUID, mutate: (inout State) -> Void) {
        var state = states[recordID] ?? State()
        mutate(&state)
        states[recordID] = state
    }
}
