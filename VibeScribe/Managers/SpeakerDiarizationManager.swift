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

        updateState(for: recordID) { state in
            state.isProcessing = true
            state.error = nil
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let known = fetchKnownSpeakers(in: context)
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
            try context.save()
        } catch {
            Logger.error("Failed to merge speakers", error: error, category: .general)
        }
    }

    // MARK: - Private

    private func fetchKnownSpeakers(in context: ModelContext) -> [SpeakerSnapshot] {
        let descriptor = FetchDescriptor<SpeakerProfile>()
        let profiles = (try? context.fetch(descriptor)) ?? []
        return profiles.compactMap { profile in
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

        // Cache existing profiles for quick lookup
        let descriptor = FetchDescriptor<SpeakerProfile>()
        let existingProfiles = (try? context.fetch(descriptor)) ?? []
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
                    embedding: speaker.currentEmbedding,
                    totalDuration: TimeInterval(speaker.duration),
                    createdAt: speaker.createdAt,
                    updatedAt: speaker.updatedAt,
                    lastSeenAt: now,
                    updateCount: Int(speaker.updateCount),
                    isPermanent: speaker.isPermanent,
                    isUserRenamed: false
                )
                context.insert(profile)
                profilesByID[speaker.id] = profile
            }

            if !profile.isUserRenamed {
                profile.displayName = speaker.name
            }

            profile.embedding = speaker.currentEmbedding
            profile.totalDuration = TimeInterval(speaker.duration)
            profile.updatedAt = speaker.updatedAt
            profile.lastSeenAt = now
            profile.updateCount = Int(speaker.updateCount)
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

        try context.save()
    }

    private func updateState(for recordID: UUID, mutate: (inout State) -> Void) {
        var state = states[recordID] ?? State()
        mutate(&state)
        states[recordID] = state
    }
}
