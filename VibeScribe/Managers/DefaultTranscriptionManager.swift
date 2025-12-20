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
        let fallback = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            return fallback
        }

        let segments = buildSegments(from: tokenTimings)
        guard !segments.isEmpty else { return fallback }

        let formatted = segments
            .map { "[\(clockString(from: $0.startTime))] \($0.text)" }
            .joined(separator: "\n")

        // If FluidAudio returns timing metadata but the formatted text is implausibly short,
        // fall back to the raw text to avoid silently truncating the transcript.
        let tokenCount = tokenTimings.count
        let expectedFloor = max(fallback.count / 2, tokenCount / 4)
        if formatted.count < expectedFloor, !fallback.isEmpty {
            Logger.warning(
                "Formatted transcript shorter than expected; using raw text instead (formatted=\(formatted.count), raw=\(fallback.count), tokens=\(tokenCount))",
                category: .transcription
            )
            return fallback
        }

        return formatted
    }

    private func buildSegments(from tokenTimings: [TokenTiming]) -> [TranscriptSegment] {
        guard let first = tokenTimings.first else { return [] }

        // Split on natural pauses, sentence endings, or when segments get too long,
        // but bias cuts toward punctuation/word boundaries to avoid chopping words.
        let gapThreshold: TimeInterval = 1.6
        let minSentenceGap: TimeInterval = 0.55
        let preferredMaxDuration: TimeInterval = 12
        let hardMaxDuration: TimeInterval = 16

        var segments: [TranscriptSegment] = []
        var currentTokens: [TokenTiming] = [first]
        var currentStart = first.startTime
        var lastPunctuationIndex: Int? = isSentenceEnding(token: first) ? 0 : nil
        var lastWordBoundaryIndex: Int? = isWordBoundary(token: first) ? 0 : nil

        func finalizeSegment(upTo index: Int) {
            guard index < currentTokens.count else { return }
            let slice = Array(currentTokens.prefix(index + 1))
            if let text = buildText(from: slice) {
                segments.append(.init(startTime: currentStart, text: text))
            }

            let remaining = Array(currentTokens.dropFirst(index + 1))
            currentTokens = remaining
            if let first = remaining.first {
                currentStart = first.startTime
            }
            lastPunctuationIndex = nil
            lastWordBoundaryIndex = nil
            for (idx, token) in currentTokens.enumerated() {
                if isSentenceEnding(token: token) { lastPunctuationIndex = idx }
                if isWordBoundary(token: token) { lastWordBoundaryIndex = idx }
            }
        }

        for token in tokenTimings.dropFirst() {
            guard let last = currentTokens.last else { continue }

            currentTokens.append(token)
            let currentIndex = currentTokens.count - 1
            if isSentenceEnding(token: token) {
                lastPunctuationIndex = currentIndex
            }
            if isWordBoundary(token: token) {
                lastWordBoundaryIndex = currentIndex
            }

            let gap = token.startTime - last.endTime
            let duration = token.endTime - currentStart
            let hasPreferredBoundary = lastPunctuationIndex ?? lastWordBoundaryIndex
            let preferredIndex = hasPreferredBoundary ?? currentIndex

            let shouldSplitOnPause = gap >= gapThreshold
            let shouldSplitOnSentence = (lastPunctuationIndex != nil && gap >= minSentenceGap)
            let shouldSplitOnLength = (duration >= preferredMaxDuration && hasPreferredBoundary != nil)
            let shouldSplitOnHardLimit = duration >= hardMaxDuration

            if shouldSplitOnPause || shouldSplitOnSentence || shouldSplitOnLength || shouldSplitOnHardLimit {
                finalizeSegment(upTo: preferredIndex)
            }
        }

        if !currentTokens.isEmpty, let text = buildText(from: currentTokens) {
            segments.append(.init(startTime: currentStart, text: text))
        }

        return segments
    }

    private func buildText(from tokens: [TokenTiming]) -> String? {
        guard !tokens.isEmpty else { return nil }

        let raw = tokens.map(\.token).joined()

        let condensed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([.,!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return condensed.isEmpty ? nil : condensed
    }

    private func isSentenceEnding(token: TokenTiming) -> Bool {
        guard let last = token.token.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return [".", "!", "?"].contains(last)
    }

    private func clockString(from time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func isWordBoundary(token: TokenTiming) -> Bool {
        let trimmed = token.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first, CharacterSet.punctuationCharacters.contains(scalar) {
            return true
        }
        return token.token.hasPrefix(" ")
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

private struct TranscriptSegment {
    let startTime: TimeInterval
    let text: String
}
