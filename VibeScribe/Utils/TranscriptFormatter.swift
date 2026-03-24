import Foundation

struct TranscriptToken: Sendable {
    let token: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct TranscriptTimestamp: Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval?

    var label: String {
        let startSeconds = max(0, Int(startTime.rounded(.down)))
        return TranscriptFormatter.clockString(from: TimeInterval(startSeconds))
    }

    var prefix: String {
        "[\(label)]"
    }
}

struct TranscriptTimestampLine: Sendable, Equatable {
    let timestamp: TranscriptTimestamp
    let remainder: String
}

private struct TranscriptTimedSegment: Sendable {
    let timestamp: TranscriptTimestamp
    var text: String
}

enum TranscriptFormatter {
    static func formattedText(rawText: String, tokens: [TranscriptToken]) -> String {
        let fallback = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !tokens.isEmpty else {
            return fallback
        }

        var segments = buildSegments(from: tokens)
        guard !segments.isEmpty else {
            return fallback
        }

        segments = reconcileTrailingRawText(in: segments, rawText: rawText)

        let formatted = segments
            .map { "\($0.timestamp.prefix) \($0.text)" }
            .joined(separator: "\n")

        let expectedFloor = max(fallback.count / 2, tokens.count / 4)
        if formatted.count < expectedFloor, !fallback.isEmpty {
            Logger.warning(
                "Formatted transcript shorter than expected; using raw text instead (formatted=\(formatted.count), raw=\(fallback.count), tokens=\(tokens.count))",
                category: .transcription
            )
            return fallback
        }

        return formatted
    }

    static func parseTimestampPrefix(from line: String) -> TranscriptTimestampLine? {
        let pattern = #"^\[(\d{2}):(\d{2}):(\d{2})(?:-(\d{2}):(\d{2}):(\d{2}))?\]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              match.numberOfRanges == 8,
              let startHourRange = Range(match.range(at: 1), in: line),
              let startMinuteRange = Range(match.range(at: 2), in: line),
              let startSecondRange = Range(match.range(at: 3), in: line),
              let remainderRange = Range(match.range(at: 7), in: line) else {
            return nil
        }

        let startTime = timeInterval(
            hours: String(line[startHourRange]),
            minutes: String(line[startMinuteRange]),
            seconds: String(line[startSecondRange])
        )

        let endTime: TimeInterval?
        if match.range(at: 4).location != NSNotFound,
           match.range(at: 5).location != NSNotFound,
           match.range(at: 6).location != NSNotFound,
           let endHourRange = Range(match.range(at: 4), in: line),
           let endMinuteRange = Range(match.range(at: 5), in: line),
           let endSecondRange = Range(match.range(at: 6), in: line) {
            let parsedEnd = timeInterval(
                hours: String(line[endHourRange]),
                minutes: String(line[endMinuteRange]),
                seconds: String(line[endSecondRange])
            )
            endTime = parsedEnd > startTime ? parsedEnd : nil
        } else {
            endTime = nil
        }

        return TranscriptTimestampLine(
            timestamp: TranscriptTimestamp(startTime: startTime, endTime: endTime),
            remainder: String(line[remainderRange])
        )
    }

    static func clockString(from time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func buildSegments(from tokens: [TranscriptToken]) -> [TranscriptTimedSegment] {
        guard let first = tokens.first else {
            return []
        }

        let gapThreshold: TimeInterval = 1.6
        let minSentenceGap: TimeInterval = 0.55
        let preferredMaxDuration: TimeInterval = 12
        let hardMaxDuration: TimeInterval = 16

        var segments: [TranscriptTimedSegment] = []
        var currentTokens: [TranscriptToken] = [first]
        var currentStart = first.startTime
        var lastPunctuationIndex: Int? = isSentenceEnding(token: first) ? 0 : nil
        var lastWordBoundaryIndex: Int? = isWordBoundary(token: first) ? 0 : nil

        func finalizeSegment(upTo index: Int) {
            guard index < currentTokens.count else {
                return
            }

            let slice = Array(currentTokens.prefix(index + 1))
            if let text = buildText(from: slice), let last = slice.last {
                segments.append(
                    .init(
                        timestamp: TranscriptTimestamp(
                            startTime: currentStart,
                            endTime: max(currentStart, last.endTime)
                        ),
                        text: text
                    )
                )
            }

            currentTokens = Array(currentTokens.dropFirst(index + 1))
            if let firstRemaining = currentTokens.first {
                currentStart = firstRemaining.startTime
            }
            lastPunctuationIndex = nil
            lastWordBoundaryIndex = nil
            for (tokenIndex, token) in currentTokens.enumerated() {
                if isSentenceEnding(token: token) {
                    lastPunctuationIndex = tokenIndex
                }
                if isWordBoundary(token: token) {
                    lastWordBoundaryIndex = tokenIndex
                }
            }
        }

        for token in tokens.dropFirst() {
            // After a finalization that consumed all buffered tokens, currentTokens is empty.
            // Start a fresh segment rather than skipping this token (and all that follow).
            if currentTokens.isEmpty {
                currentTokens = [token]
                currentStart = token.startTime
                lastPunctuationIndex = isSentenceEnding(token: token) ? 0 : nil
                lastWordBoundaryIndex = isWordBoundary(token: token) ? 0 : nil
                continue
            }

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
            let preferredBoundary = lastPunctuationIndex ?? lastWordBoundaryIndex
            let preferredIndex = preferredBoundary ?? currentIndex

            let shouldSplitOnPause = gap >= gapThreshold
            let shouldSplitOnSentence = lastPunctuationIndex != nil && gap >= minSentenceGap
            let shouldSplitOnLength = duration >= preferredMaxDuration && preferredBoundary != nil
            let shouldSplitOnHardLimit = duration >= hardMaxDuration

            if shouldSplitOnPause || shouldSplitOnSentence || shouldSplitOnLength || shouldSplitOnHardLimit {
                finalizeSegment(upTo: preferredIndex)
            }
        }

        if !currentTokens.isEmpty,
           let text = buildText(from: currentTokens),
           let last = currentTokens.last {
            segments.append(
                .init(
                    timestamp: TranscriptTimestamp(
                        startTime: currentStart,
                        endTime: max(currentStart, last.endTime)
                    ),
                    text: text
                )
            )
        }

        return segments
    }

    private static func reconcileTrailingRawText(
        in segments: [TranscriptTimedSegment],
        rawText: String
    ) -> [TranscriptTimedSegment] {
        guard !segments.isEmpty else { return segments }

        let normalizedRawText = normalizeDisplayText(rawText)
        guard !normalizedRawText.isEmpty else { return segments }

        var reconciled = segments
        var searchStart = normalizedRawText.startIndex
        var matchedAllSegments = true

        for segment in reconciled {
            guard !segment.text.isEmpty else { continue }
            guard let range = normalizedRawText.range(of: segment.text, range: searchStart..<normalizedRawText.endIndex) else {
                matchedAllSegments = false
                break
            }
            searchStart = range.upperBound
        }

        guard matchedAllSegments, searchStart < normalizedRawText.endIndex else {
            return reconciled
        }

        let trailingText = String(normalizedRawText[searchStart...])
        guard !trailingText.isEmpty else { return reconciled }

        reconciled[reconciled.count - 1].text += trailingText
        return reconciled
    }

    private static func buildText(from tokens: [TranscriptToken]) -> String? {
        guard !tokens.isEmpty else {
            return nil
        }

        let raw = tokens.map(\.token).joined()
        let condensed = normalizeDisplayText(raw)
        return condensed.isEmpty ? nil : condensed
    }

    private static func normalizeDisplayText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([.,!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSentenceEnding(token: TranscriptToken) -> Bool {
        guard let last = token.token.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return [".", "!", "?"].contains(last)
    }

    private static func isWordBoundary(token: TranscriptToken) -> Bool {
        let trimmed = token.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1,
           let scalar = trimmed.unicodeScalars.first,
           CharacterSet.punctuationCharacters.contains(scalar) {
            return true
        }
        return token.token.hasPrefix(" ")
    }

    private static func timeInterval(hours: String, minutes: String, seconds: String) -> TimeInterval {
        let parsedHours = Int(hours) ?? 0
        let parsedMinutes = Int(minutes) ?? 0
        let parsedSeconds = Int(seconds) ?? 0
        return TimeInterval(parsedHours * 3600 + parsedMinutes * 60 + parsedSeconds)
    }
}
