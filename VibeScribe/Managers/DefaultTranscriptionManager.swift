//
//  DefaultTranscriptionManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 05.02.2025.
//

import Foundation
import FluidAudio

actor DefaultTranscriptionManager {
    static let shared = DefaultTranscriptionManager()

    private let asrManager = AsrManager()
    private var initializationTask: Task<Void, Error>?

    func transcribeAudio(at fileURL: URL) async throws -> String {
        do {
            try await prepareIfNeeded()
            let result = try await asrManager.transcribe(fileURL, source: .system)
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                throw TranscriptionError.processingFailed(
                    AppLanguage.localized("error.empty.transcription.received.please.try.again.with.a.different.model.or.check.your.audio.quality")
                )
            }

            return trimmed
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.processingFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func prepareIfNeeded() async throws {
        if let task = initializationTask {
            return try await task.value
        }

        let task = Task {
            Logger.debug("Preparing FluidAudio ASR models...", category: .transcription)
            let models = try await AsrModels.downloadAndLoad()
            try await asrManager.initialize(models: models)
            Logger.info("FluidAudio ASR models ready", category: .transcription)
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
