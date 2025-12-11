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
    let speakers: [String: Speaker]
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
        try await prepareIfNeeded()
        guard let diarizer else {
            throw DiarizerError.notInitialized
        }

        diarizer.speakerManager.reset()
        let preparedSpeakers = knownSpeakers.compactMap { snapshot -> Speaker? in
            guard snapshot.embedding.count == SpeakerManager.embeddingSize else { return nil }
            return Speaker(
                id: snapshot.id,
                name: snapshot.name,
                currentEmbedding: snapshot.embedding,
                duration: snapshot.duration,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                isPermanent: snapshot.isPermanent
            )
        }
        diarizer.speakerManager.initializeKnownSpeakers(preparedSpeakers, mode: .merge, preserveIfPermanent: true)

        let samples = try audioConverter.resampleAudioFile(audioURL)
        let result = try diarizer.performCompleteDiarization(samples)
        let speakers = diarizer.speakerManager.getAllSpeakers()

        return SpeakerDiarizationOutput(
            segments: result.segments,
            speakers: speakers
        )
    }

    // MARK: - Private

    private func prepareIfNeeded() async throws {
        if diarizer != nil {
            return
        }

        if let task = initializationTask {
            return try await task.value
        }

        let task = Task {
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            self.diarizer = diarizer
        }

        initializationTask = task

        do {
            try await task.value
        } catch {
            initializationTask = nil
            throw error
        }
    }
}
