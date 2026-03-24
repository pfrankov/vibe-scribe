//
//  SpeakerDiarizationService.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 20.05.2025.
//

import Foundation
@preconcurrency import FluidAudio

struct SpeakerSnapshot: Sendable {
    let id: String
    let name: String
    let embedding: [Float]
    let duration: Float
    let createdAt: Date
    let updatedAt: Date
    let isPermanent: Bool
}

struct SpeakerDiarizationOutput: Sendable {
    let segments: [TimedSpeakerSegment]
    let speakers: [String: DiarizedSpeakerSnapshot]
}

struct DiarizedSpeakerSnapshot: Sendable {
    let id: String
    let name: String
    let embedding: [Float]
    let duration: Float
    let createdAt: Date
    let updatedAt: Date
    let updateCount: Int
    let isPermanent: Bool
}

/// Off-main-actor worker that owns FluidAudio diarization state and executes heavy work.
actor SpeakerDiarizationService {
    static let shared = SpeakerDiarizationService()

    private var diarizer: DiarizerManager?
    private var initializationTask: Task<Void, Error>?
    private let audioConverter = AudioConverter()

    func diarize(
        audioURL: URL,
        knownSpeakers: [SpeakerSnapshot]
    ) async throws -> SpeakerDiarizationOutput {
        let diarizer = try await prepareIfNeeded()

        diarizer.speakerManager.reset()
        let preparedSpeakers = knownSpeakers.compactMap { snapshot -> Speaker? in
            guard snapshot.embedding.count == SpeakerManager.embeddingSize else { return nil }
            let speaker = Speaker(
                id: snapshot.id,
                name: snapshot.name,
                currentEmbedding: snapshot.embedding,
                duration: snapshot.duration,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                isPermanent: snapshot.isPermanent
            )
            speaker.addRawEmbedding(
                RawEmbedding(
                    segmentId: UUID(),
                    embedding: snapshot.embedding,
                    timestamp: snapshot.updatedAt
                )
            )
            return speaker
        }
        diarizer.speakerManager.initializeKnownSpeakers(preparedSpeakers, mode: .merge, preserveIfPermanent: true)

        let samples = try audioConverter.resampleAudioFile(audioURL)
        let result = try diarizer.performCompleteDiarization(samples)
        let speakers = diarizer.speakerManager.getAllSpeakers().mapValues { speaker in
            DiarizedSpeakerSnapshot(
                id: speaker.id,
                name: speaker.name,
                embedding: speaker.currentEmbedding,
                duration: speaker.duration,
                createdAt: speaker.createdAt,
                updatedAt: speaker.updatedAt,
                updateCount: Int(speaker.updateCount),
                isPermanent: speaker.isPermanent
            )
        }

        return SpeakerDiarizationOutput(
            segments: result.segments,
            speakers: speakers
        )
    }

    // MARK: - Private

    private func prepareIfNeeded() async throws -> DiarizerManager {
        if let diarizer {
            return diarizer
        }

        if let task = initializationTask {
            try await task.value
            if let diarizer {
                return diarizer
            }
        }

        let task = Task {
            Logger.debug("Preparing FluidAudio diarization models...", category: .transcription)
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            Logger.info("FluidAudio diarization models ready", category: .transcription)
            self.diarizer = diarizer
        }

        initializationTask = task

        do {
            try await task.value
            initializationTask = nil
            guard let diarizer else {
                throw DiarizerError.notInitialized
            }
            return diarizer
        } catch {
            initializationTask = nil
            throw error
        }
    }
}
