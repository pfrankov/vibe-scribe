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

    private static let preferredModelVersion: AsrModelVersion = .v3
    private static let preferredModelLabel = "v3"

    private let asrManager = AsrManager()
    private var initializationTask: Task<Void, Error>?

    func transcribeAudio(at fileURL: URL) async throws -> String {
        let fileName = fileURL.lastPathComponent
        let fileSize = formattedFileSize(for: fileURL)
        let startTime = Date()
        if let fileSize {
            Logger.info("Starting FluidAudio transcription for \(fileName) [\(fileSize)]", category: .transcription)
        } else {
            Logger.info("Starting FluidAudio transcription for \(fileName)", category: .transcription)
        }

        do {
            try await prepareIfNeeded()
            let result = try await asrManager.transcribe(fileURL, source: .system)
            let trimmed = formatTranscript(result)

            guard !trimmed.isEmpty else {
                Logger.warning("FluidAudio transcription returned empty text for \(fileName)", category: .transcription)
                throw TranscriptionError.processingFailed(
                    AppLanguage.localized("error.empty.transcription.received.please.try.again.with.a.different.model.or.check.your.audio.quality")
                )
            }

            let tokenCount = result.tokenTimings?.count ?? 0
            let elapsed = Date().timeIntervalSince(startTime)
            Logger.info(
                "Finished FluidAudio transcription for \(fileName) in \(formatElapsed(elapsed)); tokens: \(tokenCount); characters: \(trimmed.count)",
                category: .transcription
            )
            Logger.info("FluidAudio transcript for \(fileName): \(trimmed)", category: .transcription)

            return trimmed
        } catch let error as TranscriptionError {
            Logger.error("FluidAudio transcription failed for \(fileName)", error: error, category: .transcription)
            throw error
        } catch {
            Logger.error("FluidAudio transcription failed for \(fileName)", error: error, category: .transcription)
            throw TranscriptionError.processingFailed(error.localizedDescription)
        }
    }

    private func formatTranscript(_ result: ASRResult) -> String {
        let tokens = (result.tokenTimings ?? []).map {
            TranscriptToken(
                token: $0.token,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }
        return TranscriptFormatter.formattedText(rawText: result.text, tokens: tokens)
    }

    // MARK: - Private

    private func prepareIfNeeded() async throws {
        if let task = initializationTask {
            return try await task.value
        }

        let task = Task {
            Logger.debug(
                "Preparing FluidAudio ASR models (\(Self.preferredModelLabel))...",
                category: .transcription
            )
            let models = try await AsrModels.downloadAndLoad(version: Self.preferredModelVersion)
            try await asrManager.initialize(models: models)
            Logger.info(
                "FluidAudio ASR models ready (\(Self.preferredModelLabel))",
                category: .transcription
            )
        }

        initializationTask = task

        do {
            try await task.value
        } catch {
            initializationTask = nil
            throw error
        }
    }

    private func formattedFileSize(for url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        String(format: "%.2fs", interval)
    }
}
