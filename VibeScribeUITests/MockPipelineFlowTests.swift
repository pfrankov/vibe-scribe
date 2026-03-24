import XCTest

private enum MockAID {
    static let welcomeView = "welcomeView"
    static let emptyStateView = "emptyStateView"
    static let newRecordingButton = "newRecordingButton"

    static let recordingTimer = "recordingTimer"
    static let recordingCloseButton = "recordingCloseButton"
    static let recordingStopButton = "recordingStopButton"
    static let recordingResumeButton = "recordingResumeButton"
    static let recordingSaveButton = "recordingSaveButton"

    static let recordRowName = "recordRowName"
    static let recordDetailView = "recordDetailView"
    static let recordTitle = "recordTitle"
    static let recordTitleEditField = "recordTitleEditField"
    static let playPauseButton = "playPauseButton"
    static let skipBackwardButton = "skipBackwardButton"
    static let skipForwardButton = "skipForwardButton"
    static let playbackSpeedButton = "playbackSpeedButton"
    static let waveformScrubber = "waveformScrubber"
    static let currentTimeLabel = "currentTimeLabel"
    static let durationLabel = "durationLabel"

    static let tabPicker = "tabPicker"
    static let transcriptionEditor = "transcriptionEditor"
    static let summaryEditor = "summaryEditor"
    static let transcribeButton = "transcribeButton"
    static let summarizeButton = "summarizeButton"
    static let transcriptionModelPicker = "transcriptionModelPicker"
    static let summaryModelPicker = "summaryModelPicker"

    static let processingProgress = "processingProgress"

    static let speakersSection = "speakersSection"
    static let speakerTimeline = "speakerTimeline"
    static let speakerTimelineSegmentPrefix = "speakerTimelineSegment_"
    static let speakerManageButton = "speakerManageButton"
    static let speakerMergeSheet = "speakerMergeSheet"
    static let speakerMergeCloseButton = "speakerMergeCloseButton"
    static let speakerMergeConfirmButton = "speakerMergeConfirmButton"
    static let speakerMergeCandidatePrefix = "speakerMergeCandidate_"
    static let speakerRenameFieldPrefix = "speakerRenameField_"

    static let settingsView = "settingsView"
    static let settingsCloseButton = "settingsCloseButton"
    static let settingsProviderPicker = "settingsProviderPicker"
    static let settingsDiarizationToggle = "settingsDiarizationToggle"
}
private let mockFirstRecordSpeakerNameEnvKey = "VIBESCRIBE_UI_MOCK_FIRST_RECORD_SPEAKER_NAME"

private enum MockScenario: String {
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
    case timedTranscriptFormatting = "timed_transcript_formatting"
    case timedTranscriptTailRecovery = "timed_transcript_tail_recovery"
    case timedTranscriptWithSpeakers = "timed_transcript_with_speakers"
    case singleSpeakerSuccess = "single_speaker_success"
    case speakerTimelineInteractions = "speaker_timeline_interactions"
}

private enum MockToken: String {
    case transcriptionError = "[MOCK_TRANSCRIPTION_ERROR]"
    case diarizationError = "[MOCK_DIARIZATION_ERROR]"
    case autoSummaryError = "[MOCK_AUTO_SUMMARY_ERROR]"
    case manualSummaryError = "[MOCK_MANUAL_SUMMARY_ERROR]"
}

final class MockPipelineFlowTests: VibeScribeUITestCase {
    private static var cachedMockFixturePaths: [Int: String] = [:]
    override func setUpWithError() throws {
        try super.setUpWithError()
        executionTimeAllowance = 240
    }

    func testMockFlow_NoSpeakers_EndToEndFromFirstLaunchToManualSummaryEdit() {
        launchMockScenario(.noSpeakersFullFlow)

        assertFirstLaunchEmptyState()
        performMockRecordingRoundTrip()
        assertPlaybackAndScrubRoundTrip()

        let initialTranscription = waitForNonEmptyTranscription()
        XCTAssertFalse(initialTranscription.isEmpty, "Automatic mock transcription should produce text")

        let initialSummary = waitForNonEmptySummary()
        XCTAssertFalse(initialSummary.isEmpty, "Automatic mock summary should produce text")

        XCTAssertTrue(
            !textValue(of: waitFor(MockAID.recordTitle, timeout: 2.5)).isEmpty,
            "Record title should remain available after playback and processing flow"
        )

        appendToTranscription("Manual transcript edit marker")
        selectSummaryModel("mock-summary-v2")
        triggerManualSummarization()
        let summaryAfterModelSwitch = waitForNonEmptySummary(contains: "mock-summary-v2")
        XCTAssertNotEqual(initialSummary, summaryAfterModelSwitch, "Switching summary model should change mocked summary output")
        waitForSummaryGenerationToComplete()

        appendToSummary("Manual summary edit marker")
        let persistedSummary = summaryTextAfterTabRoundTrip()
        XCTAssertTrue(
            persistedSummary.contains("Manual summary edit marker"),
            "Manual summary edits should persist after tab switches"
        )
    }

    func testMockFlow_WithSpeakers_EndToEndIncludesDiarization() {
        launchMockScenario(
            .twoSpeakersSuccess,
            extraEnvironment: [mockFirstRecordSpeakerNameEnvKey: "Architect Speaker"]
        )

        performMockRecordingRoundTrip()
        let transcription = waitForNonEmptyTranscription(contains: "Architect Speaker:")

        assertExists(MockAID.speakersSection, timeout: 2)
        assertExists(MockAID.speakerTimeline, timeout: 2)
        assertExists(MockAID.speakerManageButton, timeout: 2)
        XCTAssertTrue(
            transcription.contains("Architect Speaker:"),
            "Annotated transcription should include speaker labels from diarization"
        )
    }

    func testMockFlow_WithSpeakers_MergeSpeakersRoundTrip() {
        launchMockScenario(.twoSpeakersMerge)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()

        openSpeakerMergeSheet()
        let beforeMergeCount = speakerMergeCardCount()
        XCTAssertGreaterThanOrEqual(beforeMergeCount, 2, "Merge sheet should expose at least two speakers")
        assertExists(MockAID.speakerMergeCloseButton, timeout: 2.0)
        assertSpeakerMergePrimaryAction(isEnabled: false)

        selectFirstAdditionalSpeakerForMerge()
        assertSpeakerMergePrimaryAction(isEnabled: false)

        selectFirstAdditionalSpeakerForMerge()
        assertSpeakerMergePrimaryAction(isEnabled: true)
        confirmSpeakerMerge()
        closeSpeakerMergeSheetIfPresented()

        openSpeakerMergeSheet()
        let afterMergeCount = speakerMergeCardCount()
        XCTAssertLessThan(afterMergeCount, beforeMergeCount, "Speaker count should shrink after merge")
        closeSpeakerMergeSheetIfPresented()
    }

    func testMockFlow_DiarizationError_TranscriptionAndSummaryStillAvailable() {
        launchMockScenario(.diarizationError)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()
        _ = waitForNonEmptySummary()

        XCTAssertTrue(waitForToken(MockToken.diarizationError.rawValue), "Diarization mock error token should be visible")
        assertNotExists(MockAID.speakerTimeline, timeout: 1.0)
    }

    func testMockFlow_TranscriptionError_ShowsFailureAndBlocksSummary() {
        launchMockScenario(.transcriptionError)

        performMockRecordingRoundTrip()
        XCTAssertTrue(waitForToken(MockToken.transcriptionError.rawValue), "Transcription mock error token should be visible")

        XCTAssertTrue(waitUntil(timeout: 4) { self.trySwitchDetailTab(to: 1) })
        let summarizeButton = waitFor(MockAID.summarizeButton, timeout: 1.0)
        XCTAssertFalse(summarizeButton.isEnabled, "Summary should stay disabled when transcription failed")
    }

    func testMockFlow_EmptyTranscription_ShowsEmptyStateAndAllowsRetry() {
        launchMockScenario(.emptyTranscription)

        performMockRecordingRoundTrip()

        XCTAssertTrue(waitUntil(timeout: 5) { self.trySwitchDetailTab(to: 0) })
        let transcribeButton = waitFor(MockAID.transcribeButton, timeout: 1.0)
        XCTAssertTrue(transcribeButton.isEnabled, "Retry transcription should remain available for empty transcript")

        XCTAssertTrue(trySwitchDetailTab(to: 1))
        let summarizeButton = waitFor(MockAID.summarizeButton, timeout: 1.0)
        XCTAssertFalse(summarizeButton.isEnabled, "Summary should remain disabled for empty transcript")
    }

    func testMockFlow_AutoSummaryError_ManualRetryWithAnotherModelSucceeds() {
        launchMockScenario(.autoSummaryErrorRecovery)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()
        let summaryBeforeRetry = currentSummaryText()
        XCTAssertTrue(
            summaryBeforeRetry.isEmpty,
            "Automatic summary should fail and leave summary empty before manual retry"
        )

        selectSummaryModel("mock-summary-v2")
        triggerManualSummarization()
        let recoveredSummary = waitForNonEmptySummary(contains: "mock-summary-v2")
        XCTAssertFalse(recoveredSummary.isEmpty, "Manual summary retry with alternate model should recover")
    }

    func testMockFlow_ManualSummaryError_EditorPreservesPreviousSummary() {
        launchMockScenario(.manualSummaryError)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()
        let baselineSummary = waitForNonEmptySummary()

        selectSummaryModel("mock-summary-fail")
        triggerManualSummarization()
        XCTAssertTrue(waitForToken(MockToken.manualSummaryError.rawValue), "Manual summary failure token should be visible")

        let currentSummary = currentSummaryText()
        XCTAssertEqual(currentSummary, baselineSummary, "Failed manual summarization should not overwrite existing summary")
    }

    func testMockFlow_ThreeSpeakers_MergeSubsetPreservesTimeline() {
        launchMockScenario(.threeSpeakersMerge)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()

        assertExists(MockAID.speakerTimeline, timeout: 2)
        openSpeakerMergeSheet()

        let beforeMergeCount = speakerMergeCardCount()
        XCTAssertGreaterThanOrEqual(beforeMergeCount, 3, "Three-speaker scenario should show at least three merge cards")
        assertSpeakerMergePrimaryAction(isEnabled: false)
        selectFirstAdditionalSpeakerForMerge()
        assertSpeakerMergePrimaryAction(isEnabled: false)
        selectFirstAdditionalSpeakerForMerge()
        assertSpeakerMergePrimaryAction(isEnabled: true)
        confirmSpeakerMerge()
        closeSpeakerMergeSheetIfPresented()

        assertExists(MockAID.speakerTimeline, timeout: 2)

        openSpeakerMergeSheet()
        let afterMergeCount = speakerMergeCardCount()
        XCTAssertLessThan(afterMergeCount, beforeMergeCount, "Subset merge should reduce speaker count")
        closeSpeakerMergeSheetIfPresented()
    }

    func testMockFlow_ProviderMatrix_TranscriptionReflectsSelectedProvider() {
        launchMockScenario(.providerMatrix)
        for (providerRawValue, expectedToken) in supportedProviderExpectations() {
            setWhisperProviderForProviderMatrix(providerRawValue)
            performMockRecordingRoundTrip()
            let text = waitForNonEmptyTranscription(contains: expectedToken, timeout: 12)
            XCTAssertTrue(
                text.contains(expectedToken),
                "Mock transcription should reflect provider '\(providerRawValue)'"
            )
        }
    }

    func testMockFlow_DefaultProvider_FormatsTranscriptionWithStartTimestamps() {
        launchMockScenario(.timedTranscriptFormatting)

        performMockRecordingRoundTrip()
        let transcription = waitForNonEmptyTranscription(contains: "[00:00:00]")

        XCTAssertTrue(
            transcription.contains("[00:00:00] Good morning team."),
            "First sentence should keep a start-time prefix"
        )
        XCTAssertTrue(
            transcription.contains("[00:00:05] We are ready to ship the next build today."),
            "Second sentence should keep a start-time prefix"
        )
    }

    func testMockFlow_DefaultProvider_PreservesTrailingTranscriptTailWhenTokenTimingsEndEarly() {
        launchMockScenario(.timedTranscriptTailRecovery)

        performMockRecordingRoundTrip()
        let transcription = waitForNonEmptyTranscription(contains: "[00:00:00]")

        XCTAssertTrue(
            transcription.contains("[00:00:00] We can make apple tea."),
            "Timed transcript should preserve the full raw-text tail when token timings stop early"
        )
        XCTAssertFalse(
            transcription.contains("apple te\n") || transcription.hasSuffix("apple te"),
            "Timed transcript should not truncate the final word to the incomplete token stream"
        )
    }

    func testMockFlow_WithSpeakers_PreservesStartTimestampsDuringAnnotation() {
        launchMockScenario(.timedTranscriptWithSpeakers)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription(contains: "[00:00:00]")

        assertExists(MockAID.speakersSection, timeout: 2)
        assertExists(MockAID.speakerTimeline, timeout: 2)
        let transcription = waitForNonEmptyTranscription(contains: ": We agreed on next review date.", timeout: 12)

        XCTAssertTrue(
            transcription.contains("[00:00:00]") &&
            transcription.contains(": We aligned on project goals.") &&
            !transcription.contains("[00:00:00] We aligned on project goals."),
            "First timed line should keep its start timestamp and insert a speaker label before the sentence"
        )
        XCTAssertTrue(
            transcription.contains("[00:00:08]") &&
            transcription.contains(": We agreed on next review date.") &&
            !transcription.contains("[00:00:08] We agreed on next review date."),
            "Second timed line should keep its start timestamp and insert a speaker label before the sentence"
        )
        XCTAssertFalse(
            transcription.contains(": 08]"),
            "Speaker annotation should not leak timestamp fragments into the transcript body"
        )
    }

    func testMockFlow_WithSpeakers_SpeakerRenamePersistsWithoutMerge() {
        launchMockScenario(.twoSpeakersSuccess)

        performMockRecordingRoundTrip()
        let initialTranscription = waitForNonEmptyTranscription(contains: "Speaker Alpha:")
        XCTAssertTrue(
            initialTranscription.contains("Speaker Alpha:"),
            "Baseline annotated transcription should contain the original first speaker label"
        )

        openSpeakerMergeSheet()
        assertSpeakerMergePrimaryAction(isEnabled: false)
        assertSpeakerModalLayoutIsBalanced()
        renameFirstSpeakerInMergeSheet(to: "Design Lead")
        closeSpeakerMergeSheetIfPresented()

        let renamedTranscription = waitForNonEmptyTranscription(contains: "Design Lead:")
        XCTAssertTrue(
            renamedTranscription.contains("Design Lead:"),
            "Rename-only flow should update the annotated transcription"
        )
        XCTAssertFalse(
            renamedTranscription.contains("Speaker Alpha:"),
            "Old speaker label should disappear after rename is persisted"
        )

        openSpeakerMergeSheet()
        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                self.anySpeakerRenameFieldContains("Design Lead")
            },
            "Renamed speaker should still be visible after reopening the shared rename/merge modal"
        )
        closeSpeakerMergeSheetIfPresented()
    }

    func testMockFlow_WithSpeakers_SpeakerRenameIsScopedToCurrentRecord() {
        launchMockScenario(
            .twoSpeakersSuccess,
            extraEnvironment: [mockFirstRecordSpeakerNameEnvKey: "Architect Speaker"]
        )

        performMockRecordingRoundTrip()
        let firstRecordTranscription = waitForNonEmptyTranscription(contains: "Architect Speaker:")
        XCTAssertTrue(
            firstRecordTranscription.contains("Architect Speaker:"),
            "First record should render the custom speaker name in annotated transcription"
        )

        performMockRecordingRoundTrip()
        let secondRecordTranscription = waitForNonEmptyTranscription()

        XCTAssertFalse(
            secondRecordTranscription.contains("Architect Speaker:"),
            "Speaker name from the first record should not leak into annotated transcription for a later record"
        )
    }

    func testMockFlow_DiarizationDisabled_TranscriptionStaysAvailableWithoutSpeakerUI() {
        launchMockScenario(.twoSpeakersSuccess, forcedWhisperProvider: "default")
        assertMockDiarizationToggleVisibility(expectedToExist: true)

        launchMockScenario(.twoSpeakersSuccess, forcedWhisperProvider: "compatibleAPI")
        assertMockDiarizationToggleVisibility(expectedToExist: false)

        launchMockScenario(.twoSpeakersSuccess, forcedWhisperProvider: "default")
        setMockDiarizationEnabled(false)

        performMockRecordingRoundTrip()
        let transcription = waitForNonEmptyTranscription(contains: "[00:00:00]")

        XCTAssertFalse(
            transcription.contains("Speaker Alpha:") || transcription.contains("Speaker Beta:"),
            "Transcript should remain unlabeled when diarization is disabled"
        )
        assertNotExists(MockAID.speakersSection, timeout: 1.0)
        assertNotExists(MockAID.speakerTimeline, timeout: 1.0)
    }

    func testMockFlow_WithSingleSpeaker_DoesNotInjectSpeakerLabelIntoTranscript() {
        launchMockScenario(.singleSpeakerSuccess)

        performMockRecordingRoundTrip()
        let transcription = waitForNonEmptyTranscription(contains: "[00:00:00]")

        XCTAssertTrue(
            transcription.contains("[00:00:00] Solo interview answer.") &&
            transcription.contains("[00:00:12] Follow-up detail from the same speaker."),
            "Single-speaker scenario should still render the expected transcript text"
        )
        XCTAssertFalse(
            transcription.contains("Speaker Alpha:") || transcription.contains("Speaker:"),
            "Transcript should stay unlabeled when diarization resolves to only one speaker"
        )
    }

    func testMockFlow_SpeakerTimeline_MergesShortSameSpeakerGapsAndSeeksOnClick() {
        launchMockScenario(.speakerTimelineInteractions)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription(contains: "[00:00:00]")

        assertExists(MockAID.speakerTimeline, timeout: 2.0)
        XCTAssertEqual(
            speakerTimelineSegmentCount(),
            4,
            "Timeline should merge same-speaker neighbors, but keep short blocks from different speakers separate"
        )

        let currentTimeBeforeClick = textValue(of: waitFor(MockAID.currentTimeLabel, timeout: 2.0))
        clickSpeakerTimelineSegment(at: 3)

        var lastObservedTime = currentTimeBeforeClick

        XCTAssertTrue(
            waitUntil(timeout: 3.0) {
                let now = self.textValue(of: self.waitFor(MockAID.currentTimeLabel, timeout: 1.0))
                lastObservedTime = now
                guard let seconds = self.clockLabelSeconds(now) else { return false }
                return (17...18).contains(seconds) && now != currentTimeBeforeClick
            },
            "Clicking a timeline block should seek playback to the beginning of that merged segment. Last observed time: \(lastObservedTime)"
        )
    }

    // MARK: - Scenario Launch

    private func launchMockScenario(
        _ scenario: MockScenario,
        forcedWhisperProvider: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) {
        let minimumFixtureDuration: UInt32 = scenario == .speakerTimelineInteractions ? 24 : 3
        let fixturePath = mockAudioFixturePath(minimumDurationSeconds: minimumFixtureDuration)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixturePath), "Missing test fixture at \(fixturePath)")

        Self.terminateRunningTargetApp()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--empty-state"]
        app.launchEnvironment["VIBESCRIBE_UI_TESTING"] = "1"
        app.launchEnvironment["VIBESCRIBE_UI_EMPTY_STATE"] = "1"
        app.launchEnvironment["VIBESCRIBE_UI_USE_MOCK_PIPELINE"] = "1"
        app.launchEnvironment["VIBESCRIBE_UI_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["VIBESCRIBE_UI_MOCK_AUDIO_PATH"] = fixturePath
        if let forcedWhisperProvider, !forcedWhisperProvider.isEmpty {
            app.launchEnvironment["VIBESCRIBE_UI_MOCK_WHISPER_PROVIDER"] = forcedWhisperProvider
        }
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }

        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
        _ = dismissInterferingDialogsIfNeeded()
    }

    private func mockAudioFixturePath(minimumDurationSeconds: UInt32 = 3) -> String {
        if let cachedPath = Self.cachedMockFixturePaths[Int(minimumDurationSeconds)],
           FileManager.default.fileExists(atPath: cachedPath) {
            return cachedPath
        }

        let candidateRoots: [URL] = [
            ProcessInfo.processInfo.environment["SRCROOT"].map { URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ].compactMap { $0 }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeScribeUITests/fixtures", isDirectory: true)
        let tempFixtureURL = tempDirectory.appendingPathComponent("mock_\(minimumDurationSeconds)s.wav")

        do {
            if !FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            for root in candidateRoots {
                let rootFixture = root.appendingPathComponent("jfk.wav")
                if FileManager.default.fileExists(atPath: rootFixture.path) {
                    if minimumDurationSeconds <= 3, !FileManager.default.fileExists(atPath: tempFixtureURL.path) {
                        try FileManager.default.copyItem(at: rootFixture, to: tempFixtureURL)
                    }
                    if minimumDurationSeconds <= 3 {
                        Self.cachedMockFixturePaths[Int(minimumDurationSeconds)] = tempFixtureURL.path
                        return tempFixtureURL.path
                    }
                }
            }

            if !FileManager.default.fileExists(atPath: tempFixtureURL.path) {
                try createSilentWAVFixture(at: tempFixtureURL, durationSeconds: minimumDurationSeconds)
            }
            Self.cachedMockFixturePaths[Int(minimumDurationSeconds)] = tempFixtureURL.path
            return tempFixtureURL.path
        } catch {
            XCTFail("Failed to prepare mock fixture in temporary directory: \(error.localizedDescription)")
            return tempFixtureURL.path
        }
    }

    private func createSilentWAVFixture(at url: URL, durationSeconds: UInt32) throws {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16

        let bytesPerSample = UInt32(channels) * UInt32(bitsPerSample / 8)
        let sampleCount = sampleRate * durationSeconds
        let dataSize = sampleCount * bytesPerSample
        let byteRate = sampleRate * bytesPerSample
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(riffChunkSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(count: Int(dataSize)))

        try data.write(to: url, options: .atomic)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(bytes.bindMemory(to: UInt8.self))
        }
    }

    // MARK: - Flow Helpers

    private func assertFirstLaunchEmptyState() {
        assertExists(MockAID.welcomeView, timeout: 2)
        assertExists(MockAID.emptyStateView, timeout: 2)
        let rows = app.staticTexts.matching(identifier: MockAID.recordRowName)
        XCTAssertEqual(rows.count, 0, "First launch mock scenario should start with empty recordings list")
    }

    private func performMockRecordingRoundTrip() {
        let existingRows = app.staticTexts.matching(identifier: MockAID.recordRowName)
        let existingCount = existingRows.count
        var existingNames: Set<String> = []
        if existingCount > 0 {
            for index in 0..<existingCount {
                let row = existingRows.element(boundBy: index)
                if row.exists {
                    existingNames.insert(row.label)
                }
            }
        }

        let createButton = waitFor(MockAID.newRecordingButton, timeout: 1.5)
        createButton.click()

        assertExists(MockAID.recordingTimer, timeout: 2)

        waitFor(MockAID.recordingStopButton, timeout: 3.0).click()
        assertExists(MockAID.recordingResumeButton, timeout: 3.0)
        assertExists(MockAID.recordingSaveButton, timeout: 3.0)

        waitFor(MockAID.recordingResumeButton, timeout: 3.0).click()
        assertExists(MockAID.recordingStopButton, timeout: 3.0)

        waitFor(MockAID.recordingStopButton, timeout: 3.0).click()
        waitFor(MockAID.recordingSaveButton, timeout: 3.0).click()

        XCTAssertTrue(
            waitUntil(timeout: 8.0) {
                self.app.staticTexts.matching(identifier: MockAID.recordRowName).count > existingCount
            },
            "Saved mock recording should appear in list"
        )

        let rows = app.staticTexts.matching(identifier: MockAID.recordRowName)
        var createdRow: XCUIElement?
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            guard row.exists else { continue }
            if !existingNames.contains(row.label) {
                createdRow = row
                break
            }
        }

        let targetRow = createdRow ?? rows.element(boundBy: 0)
        if targetRow.exists {
            targetRow.click()
        }

        assertExists(MockAID.recordDetailView, timeout: 5.0)
        assertExists(MockAID.tabPicker, timeout: 5.0)
    }

    private func selectRecordRow(named expectedTitle: String) {
        let rowPredicate = NSPredicate(format: "identifier == %@ AND label == %@", MockAID.recordRowName, expectedTitle)
        let row = app.staticTexts.matching(rowPredicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3.0), "Record row '\(expectedTitle)' should exist")
        row.click()
        assertExists(MockAID.recordDetailView, timeout: 3.0)
    }

    private func assertPlaybackAndScrubRoundTrip() {
        let playPauseButton = waitFor(MockAID.playPauseButton, timeout: 2.0)
        let skipBackwardButton = waitFor(MockAID.skipBackwardButton, timeout: 2.0)
        let skipForwardButton = waitFor(MockAID.skipForwardButton, timeout: 2.0)
        let playbackSpeedButton = waitFor(MockAID.playbackSpeedButton, timeout: 2.0)
        let currentTimeLabel = waitFor(MockAID.currentTimeLabel, timeout: 2.0)
        let scrubber = waitFor(MockAID.waveformScrubber, timeout: 2.0)

        XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled for recorded audio")
        XCTAssertTrue(playbackSpeedButton.isEnabled, "Playback speed button should be enabled for recorded audio")

        let timeBeforePlayback = textValue(of: currentTimeLabel)
        playPauseButton.click()

        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                skipBackwardButton.isEnabled && skipForwardButton.isEnabled
            },
            "Skip controls should become enabled while playback is active"
        )

        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                let now = self.textValue(of: currentTimeLabel)
                return now != timeBeforePlayback && now != "00:00"
            },
            "Scrubbing should move current playback time"
        )

        playPauseButton.click()
        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                !skipForwardButton.isEnabled
            },
            "Skip controls should disable after pausing playback"
        )
    }

    private func waitForNonEmptyTranscription(contains expectedSubstring: String? = nil, timeout: TimeInterval = 10) -> String {
        XCTAssertTrue(
            waitUntil(timeout: 8.0) {
                _ = self.trySwitchDetailTab(to: 0)
                return self.element(MockAID.transcriptionEditor).exists
            },
            "Transcription editor should appear in detail view"
        )
        let editor = waitFor(MockAID.transcriptionEditor, timeout: 2.0)

        var capturedText = ""
        let success = waitUntil(timeout: timeout) {
            let text = self.textValue(of: editor).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                capturedText = text
            }
            guard !text.isEmpty else { return false }
            if let expectedSubstring, !text.contains(expectedSubstring) {
                return false
            }
            return true
        }

        XCTAssertTrue(success, "Expected non-empty transcription text. Last observed text: \(capturedText)")
        return capturedText
    }

    private func waitForNonEmptySummary(contains expectedSubstring: String? = nil, timeout: TimeInterval = 10) -> String {
        XCTAssertTrue(
            waitUntil(timeout: 8.0) {
                _ = self.trySwitchDetailTab(to: 1)
                return self.element(MockAID.summaryEditor).exists
            },
            "Summary editor should appear in detail view"
        )
        let editor = waitFor(MockAID.summaryEditor, timeout: 2.0)

        var capturedText = ""
        let success = waitUntil(timeout: timeout) {
            let text = self.textValue(of: editor).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if let expectedSubstring, !text.contains(expectedSubstring) {
                return false
            }
            capturedText = text
            return true
        }

        XCTAssertTrue(success, "Expected non-empty summary text")
        return capturedText
    }

    private func currentSummaryText() -> String {
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available")
        let editor = waitFor(MockAID.summaryEditor, timeout: 2.5)
        return textValue(of: editor).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryTextAfterTabRoundTrip() -> String {
        XCTAssertTrue(trySwitchDetailTab(to: 0), "Transcription tab should be available")
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available")
        return currentSummaryText()
    }

    private func appendToTranscription(_ marker: String) {
        XCTAssertTrue(trySwitchDetailTab(to: 0), "Transcription tab should be available")
        let editor = focusTextEditor(identifier: MockAID.transcriptionEditor, timeout: 2.5)
        XCTAssertTrue(
            replaceFocusedFieldText(editor, with: marker, allowTypeTextFallback: true),
            "Transcription editor should accept manual edit marker"
        )
        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                self.textValue(of: editor).contains(marker)
            },
            "Transcription editor should contain manual marker after edit"
        )
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available after transcription edit")
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
    }

    private func appendToSummary(_ marker: String) {
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available")
        let editor = focusTextEditor(identifier: MockAID.summaryEditor, timeout: 2.5)
        let existing = textValue(of: editor).trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedSummary = existing.isEmpty ? marker : "\(existing)\n\(marker)"
        XCTAssertTrue(
            replaceFocusedFieldText(editor, with: updatedSummary, allowTypeTextFallback: true),
            "Summary editor should accept manual edit marker"
        )
        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                self.textValue(of: editor).contains(marker)
            },
            "Summary editor should contain manual marker after edit"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
    }

    private func selectSummaryModel(_ model: String) {
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available before model switch")
        let picker = waitFor(MockAID.summaryModelPicker, timeout: 2.0)

        for _ in 0..<3 {
            picker.click()
            let menuItem = app.menuItems[model]
            if menuItem.exists || menuItem.waitForExistence(timeout: 0.8) {
                menuItem.click()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
        }

        XCTFail("Could not select summary model '\(model)'")
    }

    private func triggerManualSummarization() {
        XCTAssertTrue(trySwitchDetailTab(to: 1), "Summary tab should be available before summarize")
        let summarizeButton = waitFor(MockAID.summarizeButton, timeout: 1.5)
        XCTAssertTrue(summarizeButton.isEnabled, "Summarize button should be enabled")
        summarizeButton.click()
    }

    private func waitForSummaryGenerationToComplete(timeout: TimeInterval = 20.0) {
        let didComplete = waitUntil(timeout: timeout) {
            let summarizeButton = self.element(MockAID.summarizeButton)
            let progress = self.element(MockAID.processingProgress)
            return summarizeButton.exists && summarizeButton.isEnabled && !progress.exists
        }
        XCTAssertTrue(didComplete, "Summary generation should finish before manual summary edits")
    }

    private func speakerTimelineSegmentCount() -> Int {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerTimelineSegmentPrefix
        )
        return app.descendants(matching: .any).matching(predicate).count
    }

    private func clickSpeakerTimelineSegment(at index: Int) {
        let identifier = "\(MockAID.speakerTimelineSegmentPrefix)\(index)"
        let segment = waitFor(identifier, timeout: 2.0)
        XCTAssertTrue(segment.isHittable, "Timeline segment \(index) should be hittable")
        segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func clockLabelSeconds(_ label: String) -> Int? {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return (parts[0] * 60) + parts[1]
        case 3:
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        default:
            return nil
        }
    }

    private func openSpeakerMergeSheet() {
        if isSpeakerMergeUIVisible() {
            stabilizeSpeakerMergeSheetViewport()
            return
        }

        // In mock mode the merge UI is rendered inline and auto-opened on appear.
        // Wait briefly before attempting to click the manage button.
        if waitUntil(timeout: 2.5, condition: { self.isSpeakerMergeUIVisible() }) {
            stabilizeSpeakerMergeSheetViewport()
            return
        }

        XCTAssertTrue(waitUntil(timeout: 5, condition: { self.element(MockAID.speakerManageButton).exists }))
        for _ in 0..<6 {
            let button = waitFor(MockAID.speakerManageButton, timeout: 1.5)
            _ = dismissInterferingDialogsIfNeeded()
            app.activate()
            prepareElementForReliableClick(button)

            if button.exists {
                clickElementAfterReveal(button)
            }

            if waitUntil(timeout: 2.0, condition: { self.isSpeakerMergeUIVisible() }) {
                stabilizeSpeakerMergeSheetViewport()
                return
            }

            // Keep the speakers section near the top viewport so inline merge UI
            // remains in the accessibility tree for deterministic querying.
            revealInMainDetailScroll(button)
            if waitUntil(timeout: 1.0, condition: { self.isSpeakerMergeUIVisible() }) {
                stabilizeSpeakerMergeSheetViewport()
                return
            }
        }

        XCTFail("Speaker merge sheet should open")
    }

    private func speakerMergeCardCount() -> Int {
        let candidateRows = speakerMergeCandidateRows()
        if candidateRows.count > 0 {
            return candidateRows.count
        }
        return speakerMergeCheckboxes().count
    }

    private func assertSpeakerModalLayoutIsBalanced() {
        let renameFieldPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerRenameFieldPrefix
        )
        let fields = speakerRenameFieldsInMergeSheet(matching: renameFieldPredicate)
        XCTAssertGreaterThanOrEqual(fields.count, 2, "Speaker modal should expose at least two rename fields")

        let firstField = fields.element(boundBy: 0)
        let secondField = fields.element(boundBy: 1)
        XCTAssertTrue(firstField.waitForExistence(timeout: 1.0), "First rename field should exist")
        XCTAssertTrue(secondField.waitForExistence(timeout: 1.0), "Second rename field should exist")

        let leadingDelta = abs(firstField.frame.minX - secondField.frame.minX)
        let widthDelta = abs(firstField.frame.width - secondField.frame.width)
        XCTAssertLessThanOrEqual(leadingDelta, 6.0, "Speaker rename fields should stay visually aligned")
        XCTAssertLessThanOrEqual(widthDelta, 12.0, "Speaker rename fields should keep comparable widths")

        let dismissButton = element(MockAID.speakerMergeCloseButton)
        XCTAssertTrue(
            dismissButton.exists || dismissButton.waitForExistence(timeout: 1.0),
            "Speaker sheet should expose a single header close action"
        )

        let mergeButton = speakerMergeConfirmButton()
        XCTAssertTrue(mergeButton.exists || mergeButton.waitForExistence(timeout: 1.0), "Footer merge button should exist")
        XCTAssertTrue(mergeButton.frame.width >= 96, "Footer merge button should keep a usable width")
        XCTAssertLessThan(
            dismissButton.frame.maxY,
            firstField.frame.minY,
            "Close action should live in the header above the editable rows"
        )
        XCTAssertGreaterThan(
            mergeButton.frame.minY,
            secondField.frame.maxY,
            "Primary merge action should stay in the footer below the editable rows"
        )
    }

    private func renameFirstSpeakerInMergeSheet(to newName: String) {
        openSpeakerMergeSheet()
        XCTAssertTrue(waitUntil(timeout: 2.0) { self.isSpeakerMergeUIVisible() }, "Speaker merge sheet should be visible")

        let firstField = firstSpeakerRenameFieldInMergeSheet()
        XCTAssertTrue(
            firstField.exists || firstField.waitForExistence(timeout: 1.0),
            "Speaker merge sheet should expose editable speaker names"
        )

        var replaced = replaceSpeakerRenameFieldText(firstField, with: newName)
        if !replaced {
            replaced = replaceSpeakerRenameFieldText(firstField, with: newName)
        }
        _ = replaced
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                self.anySpeakerRenameFieldContains(newName)
            },
            "Renamed speaker should be visible in merge sheet"
        )
    }

    private func isSpeakerMergeUIVisible() -> Bool {
        let mergeSheet = element(MockAID.speakerMergeSheet)
        if mergeSheet.exists {
            return true
        }

        let mergeButton = element(MockAID.speakerMergeConfirmButton)
        if mergeButton.exists {
            return true
        }

        let renameFieldPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerRenameFieldPrefix
        )
        if app.textFields.matching(renameFieldPredicate).count > 0 {
            return true
        }

        // Fallback for macOS accessibility trees that flatten custom identifiers:
        // merge UI always exposes checkbox toggles plus editable text fields.
        return app.checkBoxes.count > 0 && app.textFields.count > 0
    }

    private func firstSpeakerRenameFieldInMergeSheet() -> XCUIElement {
        let renameFieldPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerRenameFieldPrefix
        )
        let namedFields = speakerRenameFieldsInMergeSheet(matching: renameFieldPredicate)
        if let bestNamedField = preferredSpeakerRenameField(in: namedFields) {
            return bestNamedField
        }

        let genericFields = speakerRenameFieldsInMergeSheet()
        if let bestGenericField = preferredSpeakerRenameField(in: genericFields) {
            return bestGenericField
        }

        return app.textFields.firstMatch
    }

    private func speakerRenameFieldsInMergeSheet(matching predicate: NSPredicate? = nil) -> XCUIElementQuery {
        let mergeSheet = element(MockAID.speakerMergeSheet)
        let baseQuery: XCUIElementQuery
        if mergeSheet.exists {
            baseQuery = mergeSheet.descendants(matching: .textField)
        } else {
            baseQuery = app.textFields
        }

        if let predicate {
            return baseQuery.matching(predicate)
        }
        return baseQuery
    }

    private func preferredSpeakerRenameField(in query: XCUIElementQuery) -> XCUIElement? {
        guard query.count > 0 else { return nil }

        var bestVisible: XCUIElement?
        var bestVisibleY = CGFloat.greatestFiniteMagnitude
        var firstHittable: XCUIElement?
        var topmostField: XCUIElement?
        var topmostFieldY = CGFloat.greatestFiniteMagnitude

        for index in 0..<query.count {
            let candidate = query.element(boundBy: index)
            guard candidate.exists else { continue }

            let minY = candidate.frame.minY
            if minY < topmostFieldY {
                topmostFieldY = minY
                topmostField = candidate
            }

            if firstHittable == nil && candidate.isHittable {
                firstHittable = candidate
            }

            if isComfortablyVisibleInWindow(candidate, inset: 12), minY < bestVisibleY {
                bestVisibleY = minY
                bestVisible = candidate
            }
        }

        return bestVisible ?? firstHittable ?? topmostField
    }

    private func stabilizeSpeakerMergeSheetViewport() {
        let mergeSheet = element(MockAID.speakerMergeSheet)
        guard mergeSheet.exists || mergeSheet.waitForExistence(timeout: 0.4) else { return }

        let mainScrollView = app.scrollViews.firstMatch
        guard mainScrollView.exists || mainScrollView.waitForExistence(timeout: 0.3) else { return }

        for _ in 0..<3 where !isComfortablyVisibleInWindow(mergeSheet, inset: 120) {
            nudge(mainScrollView, direction: .down)
        }
    }

    private func isComfortablyVisibleInWindow(_ element: XCUIElement, inset: CGFloat = 32) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch
        guard window.exists || window.waitForExistence(timeout: 0.2) else { return false }

        let frame = element.frame
        let windowFrame = window.frame.insetBy(dx: 0, dy: inset)
        guard !frame.isEmpty, !windowFrame.isEmpty else { return false }

        return frame.minY >= windowFrame.minY && frame.maxY <= windowFrame.maxY
    }

    private func revealInMainDetailScroll(_ element: XCUIElement) {
        guard element.exists else { return }

        let mainScrollView = app.scrollViews.firstMatch
        guard mainScrollView.exists || mainScrollView.waitForExistence(timeout: 0.4) else { return }

        for _ in 0..<4 where !element.isHittable {
            nudge(mainScrollView, direction: .down)
        }
        for _ in 0..<4 where !element.isHittable {
            nudge(mainScrollView, direction: .up)
        }

        // Keep target away from title/toolbar overlap near the top edge.
        for _ in 0..<3 where element.isHittable && isNearTopEdge(element) {
            nudge(mainScrollView, direction: .down)
        }
    }

    private func prepareElementForReliableClick(_ element: XCUIElement) {
        guard element.exists else { return }

        let mainScrollView = app.scrollViews.firstMatch
        guard mainScrollView.exists || mainScrollView.waitForExistence(timeout: 0.3) else {
            revealInMainDetailScroll(element)
            return
        }

        // Always pre-scroll before click so controls pinned to the very top
        // are moved away from non-interactive chrome areas.
        nudge(mainScrollView, direction: .down)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        revealInMainDetailScroll(element)

        if element.isHittable && isNearTopEdge(element) {
            nudge(mainScrollView, direction: .down)
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            revealInMainDetailScroll(element)
        }
    }

    private func clickElementAfterReveal(_ element: XCUIElement) {
        guard element.exists else { return }

        if element.isHittable {
            if isNearTopEdge(element) {
                // Click lower inside bounds for controls near the top inset.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).click()
                return
            }
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).click()
            return
        }

        element.click()
    }

    private func isNearTopEdge(_ element: XCUIElement, inset: CGFloat = 84) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch
        guard window.exists || window.waitForExistence(timeout: 0.2) else { return false }
        return element.frame.minY <= window.frame.minY + inset
    }

    private enum ScrollDirection {
        case up
        case down
    }

    private func nudge(_ scrollView: XCUIElement, direction: ScrollDirection) {
        let startVector: CGVector
        let endVector: CGVector

        switch direction {
        case .up:
            startVector = CGVector(dx: 0.5, dy: 0.78)
            endVector = CGVector(dx: 0.5, dy: 0.22)
        case .down:
            startVector = CGVector(dx: 0.5, dy: 0.22)
            endVector = CGVector(dx: 0.5, dy: 0.78)
        }

        let start = scrollView.coordinate(withNormalizedOffset: startVector)
        let end = scrollView.coordinate(withNormalizedOffset: endVector)
        start.press(forDuration: 0.02, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    }

    private func anySpeakerRenameFieldContains(_ expectedName: String) -> Bool {
        let renameFieldPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerRenameFieldPrefix
        )
        let namedFields = speakerRenameFieldsInMergeSheet(matching: renameFieldPredicate)
        let query = namedFields.count > 0 ? namedFields : speakerRenameFieldsInMergeSheet()

        for index in 0..<query.count {
            let value = speakerFieldValue(of: query.element(boundBy: index))
            if value.contains(expectedName) {
                return true
            }
        }

        return false
    }

    private func speakerFieldValue(of field: XCUIElement) -> String {
        if let rawValue = field.value as? String, !rawValue.isEmpty {
            return rawValue
        }
        return textValue(of: field)
    }

    @discardableResult
    private func replaceSpeakerRenameFieldText(_ field: XCUIElement, with newName: String) -> Bool {
        guard field.exists || field.waitForExistence(timeout: 0.8) else { return false }

        var targetField = field
        if !targetField.isHittable {
            let fallbackField = firstSpeakerRenameFieldInMergeSheet()
            if fallbackField.exists {
                targetField = fallbackField
            }
        }

        if targetField.exists {
            app.activate()
            if targetField.isHittable {
                targetField.click()
            } else {
                targetField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
        }

        if replaceFocusedFieldText(
            targetField,
            with: newName,
            attempts: 2,
            timeout: 1.5,
            forceClickToFocus: false,
            allowTypeTextFallback: true
        ) {
            return waitUntil(timeout: 1.0, condition: {
                self.speakerFieldValue(of: targetField).contains(newName) || self.anySpeakerRenameFieldContains(newName)
            })
        }

        if targetField.exists {
            targetField.click()
        }

        // Fallback for cases where Cmd+V is swallowed by app-level shortcuts.
        if targetField.exists {
            targetField.doubleClick()
            clearFocusedFieldText(targetField, rounds: 2, forceClickToFocus: false)
            targetField.typeText(newName)
            return waitUntil(timeout: 1.2, condition: {
                self.speakerFieldValue(of: targetField).contains(newName) || self.anySpeakerRenameFieldContains(newName)
            })
        }

        return false
    }

    private func closeSpeakerMergeSheetIfPresented() {
        guard isSpeakerMergeUIVisible() else { return }
        let closeButton = element(MockAID.speakerMergeCloseButton)
        if closeButton.exists || closeButton.waitForExistence(timeout: 0.6) {
            if closeButton.isHittable {
                closeButton.click()
            } else {
                closeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        _ = waitUntil(timeout: 2.0) { !self.isSpeakerMergeUIVisible() }
    }

    private func supportedProviderExpectations() -> [(String, String)] {
        if #available(macOS 26, *) {
            return [
                ("default", "[provider:default]"),
                ("speechAnalyzer", "[provider:speechAnalyzer]"),
                ("whisperServer", "[provider:whisperServer]"),
                ("compatibleAPI", "[provider:compatibleAPI]"),
            ]
        }
        return [
            ("default", "[provider:default]"),
            ("whisperServer", "[provider:whisperServer]"),
            ("compatibleAPI", "[provider:compatibleAPI]"),
        ]
    }

    private func availableProviderOrder() -> [String] {
        if #available(macOS 26, *) {
            return ["default", "speechAnalyzer", "whisperServer", "compatibleAPI"]
        }
        return ["default", "whisperServer", "compatibleAPI"]
    }

    private func setWhisperProviderForProviderMatrix(_ providerRawValue: String) {
        let providerOrder = availableProviderOrder()
        guard let targetIndex = providerOrder.firstIndex(of: providerRawValue) else {
            XCTFail("Unknown provider raw value '\(providerRawValue)' for provider matrix")
            return
        }

        openSettings()
        assertExists(MockAID.settingsView, timeout: 1.2, "Settings should open before provider selection")
        switchSettingsTab(to: 0)

        let providerPicker = waitFor(MockAID.settingsProviderPicker, timeout: 1.2)
        XCTAssertTrue(providerPicker.isEnabled, "Provider picker should be enabled")
        providerPicker.click()
        XCTAssertTrue(app.menuItems.firstMatch.waitForExistence(timeout: 0.8), "Provider picker menu should open")

        for _ in 0..<8 {
            app.typeKey(.upArrow, modifierFlags: [])
        }
        for _ in 0..<targetIndex {
            app.typeKey(.downArrow, modifierFlags: [])
        }
        app.typeKey(.return, modifierFlags: [])
        _ = app.menuItems.firstMatch.waitForNonExistence(timeout: 0.8)

        let closeButton = element(MockAID.settingsCloseButton)
        if closeButton.exists || closeButton.waitForExistence(timeout: 0.5) {
            closeButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        assertNotExists(MockAID.settingsView, timeout: 1.2)
    }

    private func setMockDiarizationEnabled(_ isEnabled: Bool) {
        openSettings()
        assertExists(MockAID.settingsView, timeout: 1.2, "Settings should open before changing diarization setting")
        switchSettingsTab(to: 0)

        let toggle = waitFor(MockAID.settingsDiarizationToggle, timeout: 1.2)
        let currentValue = checkboxValue(MockAID.settingsDiarizationToggle)
        if currentValue != isEnabled {
            toggle.click()
        }

        let closeButton = element(MockAID.settingsCloseButton)
        if closeButton.exists || closeButton.waitForExistence(timeout: 0.5) {
            closeButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        assertNotExists(MockAID.settingsView, timeout: 1.2)
    }

    private func assertMockDiarizationToggleVisibility(expectedToExist: Bool) {
        openSettings()
        assertExists(MockAID.settingsView, timeout: 1.2, "Settings should open before checking diarization visibility")
        switchSettingsTab(to: 0)

        if expectedToExist {
            assertExists(MockAID.settingsDiarizationToggle, timeout: 1.2)
        } else {
            assertNotExists(MockAID.settingsDiarizationToggle, timeout: 1.2)
        }

        let closeButton = element(MockAID.settingsCloseButton)
        if closeButton.exists || closeButton.waitForExistence(timeout: 0.5) {
            closeButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        assertNotExists(MockAID.settingsView, timeout: 1.2)
    }

    private func waitForToken(_ token: String, timeout: TimeInterval = 8) -> Bool {
        return waitUntil(timeout: timeout) {
            let staticTextPredicate = NSPredicate(format: "label CONTAINS[c] %@", token)
            if self.app.staticTexts.containing(staticTextPredicate).firstMatch.exists {
                return true
            }

            if self.app.descendants(matching: .any).matching(staticTextPredicate).firstMatch.exists {
                return true
            }

            let textViewValuePredicate = NSPredicate(format: "value CONTAINS[c] %@", token)
            if self.app.textViews.containing(textViewValuePredicate).firstMatch.exists {
                return true
            }

            let textViewLabelPredicate = NSPredicate(format: "label CONTAINS[c] %@", token)
            if self.app.textViews.containing(textViewLabelPredicate).firstMatch.exists {
                return true
            }

            return false
        }
    }

    private func trySwitchDetailTab(to index: Int) -> Bool {
        let tabPicker = element(MockAID.tabPicker)
        guard tabPicker.exists || tabPicker.waitForExistence(timeout: 0.8) else { return false }
        let buttons = segments(of: tabPicker)
        guard buttons.count > index else { return false }
        let target = buttons.element(boundBy: index)
        guard target.exists || target.waitForExistence(timeout: 0.2) else { return false }
        target.click()
        return true
    }

    private func focusTextEditor(identifier: String, timeout: TimeInterval) -> XCUIElement {
        let editor = waitFor(identifier, timeout: timeout)
        for _ in 0..<4 {
            _ = dismissInterferingDialogsIfNeeded()
            app.activate()
            let target = actualTextInput(for: editor)
            if target.exists {
                if target.isHittable {
                    target.click()
                    return target
                }
                let center = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.click()
                return target
            }
            _ = editor.waitForExistence(timeout: 0.2)
        }
        XCTFail("Editor '\(identifier)' should exist and accept focus")
        return actualTextInput(for: editor)
    }

    private func actualTextInput(for editor: XCUIElement) -> XCUIElement {
        if editor.elementType == .textView || editor.elementType == .textField {
            return editor
        }

        let nestedTextView = editor.descendants(matching: .textView).firstMatch
        if nestedTextView.exists {
            return nestedTextView
        }

        let detailTextView = element(MockAID.recordDetailView).descendants(matching: .textView).firstMatch
        if detailTextView.exists {
            return detailTextView
        }

        let appTextView = app.textViews.firstMatch
        if appTextView.exists {
            return appTextView
        }

        return editor
    }

    private func confirmSpeakerMerge() {
        let mergeButton = speakerMergeConfirmButton()
        if mergeButton.exists || mergeButton.waitForExistence(timeout: 1.0) {
            if mergeButton.isEnabled {
                if mergeButton.isHittable {
                    mergeButton.click()
                    return
                }
                app.typeKey(.return, modifierFlags: [])
                return
            }
        }

        let localizedMergePredicate = NSPredicate(
            format: """
            label CONTAINS[c] 'merge' OR title CONTAINS[c] 'merge' OR
            label CONTAINS[c] 'объедин' OR title CONTAINS[c] 'объедин' OR
            label CONTAINS[c] 'zusammen' OR title CONTAINS[c] 'zusammen' OR
            label CONTAINS[c] '合并' OR title CONTAINS[c] '合并'
            """
        )
        let localizedMergeButton = app.buttons.matching(localizedMergePredicate).firstMatch
        if localizedMergeButton.exists || localizedMergeButton.waitForExistence(timeout: 1.0) {
            if localizedMergeButton.isEnabled {
                if localizedMergeButton.isHittable {
                    localizedMergeButton.click()
                    return
                }
                app.typeKey(.return, modifierFlags: [])
                return
            }
        }

        app.typeKey(.return, modifierFlags: [])
    }

    private func assertSpeakerMergePrimaryAction(isEnabled: Bool) {
        let mergeButton = speakerMergeConfirmButton()
        XCTAssertTrue(
            mergeButton.exists || mergeButton.waitForExistence(timeout: 1.5),
            "Speaker merge primary action should exist"
        )
        XCTAssertEqual(
            mergeButton.isEnabled,
            isEnabled,
            "Speaker merge primary action should \(isEnabled ? "" : "not ")be enabled"
        )
    }

    private func selectFirstAdditionalSpeakerForMerge() {
        let candidates = speakerMergeCandidateRows()
        if candidates.count > 0 {
            for i in 0..<candidates.count {
                let candidate = candidates.element(boundBy: i)
                guard candidate.exists else { continue }
                // Skip already-selected candidates — robust against re-render reordering
                if let value = candidate.value as? String, value == "selected" { continue }
                app.activate()
                candidate.click()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                return
            }
            XCTFail("No unselected merge candidate found")
            return
        }

        let checkboxes = speakerMergeCheckboxes()
        XCTAssertGreaterThanOrEqual(checkboxes.count, 1, "Merge sheet should provide at least one merge candidate checkbox")

        for index in 0..<checkboxes.count {
            let checkbox = checkboxAt(index: index, in: checkboxes)
            guard checkbox.exists else { continue }
            if !checkboxIsSelected(checkbox) {
                if checkbox.isHittable {
                    checkbox.click()
                } else {
                    checkbox.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                }
                return
            }
        }

        XCTFail("Expected at least one unchecked speaker merge candidate")
    }

    private func checkboxAt(index: Int, in query: XCUIElementQuery) -> XCUIElement {
        query.element(boundBy: index)
    }

    private func speakerMergeCheckboxes() -> XCUIElementQuery {
        let mergeSheet = element(MockAID.speakerMergeSheet)
        if mergeSheet.exists || mergeSheet.waitForExistence(timeout: 0.3) {
            return mergeSheet.descendants(matching: .checkBox)
        }
        return app.checkBoxes
    }

    private func speakerMergeConfirmButton() -> XCUIElement {
        let button = app.buttons[MockAID.speakerMergeConfirmButton]
        if button.exists {
            return button
        }
        return element(MockAID.speakerMergeConfirmButton)
    }

    private func speakerMergeCandidateRows() -> XCUIElementQuery {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            MockAID.speakerMergeCandidatePrefix
        )
        let mergeSheet = element(MockAID.speakerMergeSheet)
        if mergeSheet.exists || mergeSheet.waitForExistence(timeout: 0.3) {
            return mergeSheet.descendants(matching: .any).matching(predicate)
        }
        return app.descendants(matching: .any).matching(predicate)
    }

    private func checkboxIsSelected(_ checkbox: XCUIElement) -> Bool {
        if let boolValue = checkbox.value as? Bool {
            return boolValue
        }

        if let numberValue = checkbox.value as? NSNumber {
            return numberValue.intValue != 0
        }

        if let stringValue = checkbox.value as? String {
            let normalized = stringValue.lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
        }

        return false
    }

    private func renameRecordInline(to newName: String) {
        let titleLabel = waitFor(MockAID.recordTitle, timeout: 2.0)
        let titleField = element(MockAID.recordTitleEditField)
        var openedInlineEditor = false
        for _ in 0..<3 {
            _ = dismissInterferingDialogsIfNeeded()
            app.activate()
            if titleLabel.isHittable {
                titleLabel.doubleClick()
            } else {
                let center = titleLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.doubleClick()
            }

            if titleField.exists || titleField.waitForExistence(timeout: 1.0) {
                openedInlineEditor = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if !openedInlineEditor {
            renameSelectedRecord(to: newName)
            return
        }
        XCTAssertTrue(
            replaceFocusedFieldText(
                titleField,
                with: newName,
                preserveInitialSelection: true
            ),
            "Inline rename field should contain replacement text before submit"
        )
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitUntil(timeout: 4.0) {
                self.textValue(of: self.waitFor(MockAID.recordTitle, timeout: 0.4)).contains(newName)
            },
            "Record title should update after inline rename"
        )
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, interval: TimeInterval = 0.25, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
        return condition()
    }
}
