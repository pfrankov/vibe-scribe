import Foundation

enum UITestMockPipeline {
    enum Scenario: String {
        case noSpeakersFullFlow = "no_speakers_full_flow"
        case twoSpeakersSuccess = "two_speakers_success"
        case twoSpeakersMerge = "two_speakers_merge"
        case diarizationError = "diarization_error"
        case transcriptionError = "transcription_error"
        case emptyTranscription = "empty_transcription"
        case autoSummaryErrorRecovery = "auto_summary_error_recovery"
        case manualSummaryError = "manual_summary_error"
        case threeSpeakersMerge = "three_speakers_merge"
        case providerMatrix = "provider_matrix"
    }

    struct SpeakerSegment: Equatable {
        let speakerID: String
        let speakerName: String
        let hue: Double
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    enum DiarizationResult: Equatable {
        case none
        case speakers([SpeakerSegment])
        case failure(String)
    }

    enum Outcome: Equatable {
        case success(String)
        case failure(String)
    }

    struct Config: Equatable {
        let whisperModels: [String]
        let summaryModels: [String]
        let defaultWhisperModel: String
        let defaultSummaryModel: String
        let transcription: Outcome
        let transcriptionOutcomesByProvider: [String: Outcome]
        let diarization: DiarizationResult
        let summaryOutcomesByModel: [String: Outcome]
        let fallbackSummaryOutcome: Outcome
        let summaryLabel: String
    }

    enum MockPipelineError: LocalizedError {
        case disabled
        case missingMockAudioPath
        case missingMockAudioFile(String)
        case transcriptionFailed(String)
        case summaryFailed(String)

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "[MOCK_PIPELINE_DISABLED]"
            case .missingMockAudioPath:
                return "[MOCK_AUDIO_PATH_MISSING]"
            case .missingMockAudioFile(let path):
                return "[MOCK_AUDIO_FILE_MISSING] \(path)"
            case .transcriptionFailed(let token):
                return token
            case .summaryFailed(let token):
                return token
            }
        }
    }

    private static let enabledEnvKey = "VIBESCRIBE_UI_USE_MOCK_PIPELINE"
    private static let scenarioEnvKey = "VIBESCRIBE_UI_SCENARIO"
    private static let mockAudioPathEnvKey = "VIBESCRIBE_UI_MOCK_AUDIO_PATH"
    private static let forcedWhisperProviderEnvKey = "VIBESCRIBE_UI_MOCK_WHISPER_PROVIDER"
    private static let dynamicSummaryToken = "__DYNAMIC_SUMMARY__"

    static var isEnabled: Bool {
        guard VibeScribeApp.isUITesting else { return false }
        return ProcessInfo.processInfo.environment[enabledEnvKey] == "1"
    }

    static var currentScenario: Scenario {
        guard
            let raw = ProcessInfo.processInfo.environment[scenarioEnvKey],
            let scenario = Scenario(rawValue: raw)
        else {
            return .noSpeakersFullFlow
        }
        return scenario
    }

    static var currentConfig: Config? {
        guard isEnabled else { return nil }
        return configuration(for: currentScenario)
    }

    static var mockWhisperModels: [String] {
        currentConfig?.whisperModels ?? []
    }

    static var mockSummaryModels: [String] {
        currentConfig?.summaryModels ?? []
    }

    static var defaultWhisperModel: String? {
        currentConfig?.defaultWhisperModel
    }

    static var defaultSummaryModel: String? {
        currentConfig?.defaultSummaryModel
    }

    static var minimumRecordingDuration: TimeInterval {
        24
    }

    static var processingDelayNanoseconds: UInt64 {
        180_000_000
    }

    static func sleepForProcessingStep() async throws {
        try await Task.sleep(nanoseconds: processingDelayNanoseconds)
    }

    static func makeMockRecordingCopyURL() throws -> URL {
        guard isEnabled else { throw MockPipelineError.disabled }
        guard let sourcePath = ProcessInfo.processInfo.environment[mockAudioPathEnvKey], !sourcePath.isEmpty else {
            throw MockPipelineError.missingMockAudioPath
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MockPipelineError.missingMockAudioFile(sourceURL.path)
        }

        let recordingsDir = try AudioUtils.getRecordingsDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension
        let destinationURL = recordingsDir.appendingPathComponent("mock_\(UUID().uuidString).\(ext)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func transcriptionText(providerRawValue: String, model: String) throws -> String {
        guard let config = currentConfig else { throw MockPipelineError.disabled }
        let normalizedProvider = resolveProviderRawValue(fallback: providerRawValue)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = normalizedModel // reserved for future model-specific branching
        let outcome = config.transcriptionOutcomesByProvider[normalizedProvider] ?? config.transcription

        switch outcome {
        case .success(let text):
            return text
        case .failure(let token):
            throw MockPipelineError.transcriptionFailed(token)
        }
    }

    static func transcriptionText() throws -> String {
        try transcriptionText(providerRawValue: "", model: "")
    }

    static func summaryText(model: String, transcription: String) throws -> String {
        guard let config = currentConfig else { throw MockPipelineError.disabled }

        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = normalizedModel.isEmpty ? config.defaultSummaryModel : normalizedModel
        let outcome = config.summaryOutcomesByModel[resolvedModel] ?? config.fallbackSummaryOutcome

        switch outcome {
        case .success(let template):
            if template == dynamicSummaryToken {
                return dynamicSummary(model: resolvedModel, transcription: transcription, label: config.summaryLabel)
            }
            return template
        case .failure(let token):
            throw MockPipelineError.summaryFailed(token)
        }
    }

    static func diarizationResult() -> DiarizationResult {
        currentConfig?.diarization ?? .none
    }

    private static func dynamicSummary(model: String, transcription: String, label: String) -> String {
        let snippet = transcription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(snippet.prefix(120))

        return """
## \(label) — \(model)

- Mock summary model: \(model)
- Transcript excerpt: \(excerpt)
- This summary is deterministic for UI automation.
"""
    }

    private static func resolveProviderRawValue(fallback providerRawValue: String) -> String {
        let envProvider = ProcessInfo.processInfo.environment[forcedWhisperProviderEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envProvider, !envProvider.isEmpty {
            return envProvider
        }
        return providerRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func twoSpeakerSegments() -> [SpeakerSegment] {
        [
            SpeakerSegment(speakerID: "speaker_alpha", speakerName: "Speaker Alpha", hue: 0.08, startTime: 0, endTime: 12),
            SpeakerSegment(speakerID: "speaker_beta", speakerName: "Speaker Beta", hue: 0.58, startTime: 12, endTime: 24),
        ]
    }

    private static func threeSpeakerSegments() -> [SpeakerSegment] {
        [
            SpeakerSegment(speakerID: "speaker_alpha", speakerName: "Speaker Alpha", hue: 0.08, startTime: 0, endTime: 8),
            SpeakerSegment(speakerID: "speaker_beta", speakerName: "Speaker Beta", hue: 0.58, startTime: 8, endTime: 16),
            SpeakerSegment(speakerID: "speaker_gamma", speakerName: "Speaker Gamma", hue: 0.34, startTime: 16, endTime: 24),
        ]
    }

    private static func baseConfig(
        transcription: Outcome,
        transcriptionOutcomesByProvider: [String: Outcome] = [:],
        diarization: DiarizationResult,
        summaryOutcomesByModel: [String: Outcome] = [:],
        fallbackSummaryOutcome: Outcome = .success(dynamicSummaryToken),
        summaryLabel: String
    ) -> Config {
        let whisperModels = ["mock-whisper-v1", "mock-whisper-v2"]
        let summaryModels = ["mock-summary-v1", "mock-summary-v2", "mock-summary-fail"]

        return Config(
            whisperModels: whisperModels,
            summaryModels: summaryModels,
            defaultWhisperModel: whisperModels[0],
            defaultSummaryModel: summaryModels[0],
            transcription: transcription,
            transcriptionOutcomesByProvider: transcriptionOutcomesByProvider,
            diarization: diarization,
            summaryOutcomesByModel: summaryOutcomesByModel,
            fallbackSummaryOutcome: fallbackSummaryOutcome,
            summaryLabel: summaryLabel
        )
    }

    private static func configuration(for scenario: Scenario) -> Config {
        switch scenario {
        case .noSpeakersFullFlow:
            return baseConfig(
                transcription: .success("The team discussed release readiness, QA blockers, and launch notes for the next sprint."),
                diarization: .none,
                summaryLabel: "No Speakers Happy Path"
            )

        case .twoSpeakersSuccess:
            return baseConfig(
                transcription: .success("[00:00:00] We aligned on project goals.\n[00:00:12] We agreed on next review date."),
                diarization: .speakers(twoSpeakerSegments()),
                summaryLabel: "Two Speakers Success"
            )

        case .twoSpeakersMerge:
            return baseConfig(
                transcription: .success("[00:00:00] Engineering update from speaker one.\n[00:00:12] Product update from speaker two."),
                diarization: .speakers(twoSpeakerSegments()),
                summaryLabel: "Two Speakers Merge"
            )

        case .diarizationError:
            return baseConfig(
                transcription: .success("Architecture review notes with action items and risk decisions."),
                diarization: .failure("[MOCK_DIARIZATION_ERROR]"),
                summaryLabel: "Diarization Error"
            )

        case .transcriptionError:
            return baseConfig(
                transcription: .failure("[MOCK_TRANSCRIPTION_ERROR]"),
                diarization: .none,
                summaryLabel: "Transcription Error"
            )

        case .emptyTranscription:
            return baseConfig(
                transcription: .success("   "),
                diarization: .none,
                summaryLabel: "Empty Transcription"
            )

        case .autoSummaryErrorRecovery:
            return baseConfig(
                transcription: .success("Weekly sync with budget and staffing decisions."),
                diarization: .none,
                summaryOutcomesByModel: [
                    "mock-summary-v1": .failure("[MOCK_AUTO_SUMMARY_ERROR]"),
                    "mock-summary-v2": .success(dynamicSummaryToken),
                ],
                fallbackSummaryOutcome: .failure("[MOCK_AUTO_SUMMARY_ERROR]"),
                summaryLabel: "Auto Summary Recovery"
            )

        case .manualSummaryError:
            return baseConfig(
                transcription: .success("Planning call notes with milestones and ownership."),
                diarization: .none,
                summaryOutcomesByModel: [
                    "mock-summary-v1": .success(dynamicSummaryToken),
                    "mock-summary-fail": .failure("[MOCK_MANUAL_SUMMARY_ERROR]"),
                ],
                fallbackSummaryOutcome: .success(dynamicSummaryToken),
                summaryLabel: "Manual Summary Error"
            )

        case .threeSpeakersMerge:
            return baseConfig(
                transcription: .success("[00:00:00] Intro from host.\n[00:00:08] Update from engineer.\n[00:00:16] Risk review from PM."),
                diarization: .speakers(threeSpeakerSegments()),
                summaryLabel: "Three Speakers Merge"
            )

        case .providerMatrix:
            return baseConfig(
                transcription: .success("[provider:default] Baseline transcript for provider matrix."),
                transcriptionOutcomesByProvider: [
                    "default": .success("[provider:default] Mock transcript via default provider."),
                    "speechAnalyzer": .success("[provider:speechAnalyzer] Mock transcript via native provider."),
                    "whisperServer": .success("[provider:whisperServer] Mock transcript via whisper server provider."),
                    "compatibleAPI": .success("[provider:compatibleAPI] Mock transcript via compatible API provider."),
                ],
                diarization: .none,
                summaryOutcomesByModel: [
                    "mock-summary-v1": .success(dynamicSummaryToken),
                    "mock-summary-v2": .success(dynamicSummaryToken),
                ],
                fallbackSummaryOutcome: .success(dynamicSummaryToken),
                summaryLabel: "Provider Matrix"
            )
        }
    }
}
