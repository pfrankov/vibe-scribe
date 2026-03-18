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
    static let speakerManageButton = "speakerManageButton"
    static let speakerMergeSheet = "speakerMergeSheet"
    static let speakerMergeConfirmButton = "speakerMergeConfirmButton"
    static let speakerChip = "speakerChip"
    static let speakerRenameFieldPrefix = "speakerRenameField_"

    static let settingsView = "settingsView"
    static let settingsCloseButton = "settingsCloseButton"
    static let settingsProviderPicker = "settingsProviderPicker"
}

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
}

private enum MockToken: String {
    case transcriptionError = "[MOCK_TRANSCRIPTION_ERROR]"
    case diarizationError = "[MOCK_DIARIZATION_ERROR]"
    case autoSummaryError = "[MOCK_AUTO_SUMMARY_ERROR]"
    case manualSummaryError = "[MOCK_MANUAL_SUMMARY_ERROR]"
}

final class MockPipelineFlowTests: VibeScribeUITestCase {
    private static var cachedMockFixturePath: String?

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
        launchMockScenario(.twoSpeakersSuccess)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()

        assertExists(MockAID.speakersSection, timeout: 2)
        assertExists(MockAID.speakerTimeline, timeout: 2)
        assertExists(MockAID.speakerManageButton, timeout: 2)
        renameFirstSpeakerInMergeSheet(to: "Architect Speaker")
    }

    func testMockFlow_WithSpeakers_MergeSpeakersRoundTrip() {
        launchMockScenario(.twoSpeakersMerge)

        performMockRecordingRoundTrip()
        _ = waitForNonEmptyTranscription()

        openSpeakerMergeSheet()
        let beforeMergeCount = speakerMergeCardCount()
        XCTAssertGreaterThanOrEqual(beforeMergeCount, 2, "Merge sheet should expose at least two speakers")

        ensureAtLeastTwoSpeakersSelectedForMerge()
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

        let checkboxes = app.checkBoxes
        if checkboxes.count >= 3 {
            let lastCheckbox = checkboxes.element(boundBy: checkboxes.count - 1)
            if lastCheckbox.exists && lastCheckbox.isHittable {
                lastCheckbox.click()
            }
        }

        ensureAtLeastTwoSpeakersSelectedForMerge()
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

    // MARK: - Scenario Launch

    private func launchMockScenario(_ scenario: MockScenario, forcedWhisperProvider: String? = nil) {
        let fixturePath = mockAudioFixturePath()
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

        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
        _ = dismissInterferingDialogsIfNeeded()
    }

    private func mockAudioFixturePath() -> String {
        if
            let cachedPath = Self.cachedMockFixturePath,
            FileManager.default.fileExists(atPath: cachedPath)
        {
            return cachedPath
        }

        let candidateRoots: [URL] = [
            ProcessInfo.processInfo.environment["SRCROOT"].map { URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ].compactMap { $0 }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeScribeUITests/fixtures", isDirectory: true)
        let tempFixtureURL = tempDirectory.appendingPathComponent("jfk.wav")

        do {
            if !FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            for root in candidateRoots {
                let rootFixture = root.appendingPathComponent("jfk.wav")
                if FileManager.default.fileExists(atPath: rootFixture.path) {
                    if !FileManager.default.fileExists(atPath: tempFixtureURL.path) {
                        try FileManager.default.copyItem(at: rootFixture, to: tempFixtureURL)
                    }
                    Self.cachedMockFixturePath = tempFixtureURL.path
                    return tempFixtureURL.path
                }
            }

            if !FileManager.default.fileExists(atPath: tempFixtureURL.path) {
                try createSilentWAVFixture(at: tempFixtureURL)
            }
            Self.cachedMockFixturePath = tempFixtureURL.path
            return tempFixtureURL.path
        } catch {
            XCTFail("Failed to prepare mock fixture in temporary directory: \(error.localizedDescription)")
            return tempFixtureURL.path
        }
    }

    private func createSilentWAVFixture(at url: URL) throws {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationSeconds: UInt32 = 3

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
        appendLittleEndian(UInt32(16), to: &data) // PCM fmt chunk size
        appendLittleEndian(UInt16(1), to: &data)  // PCM format
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(count: Int(dataSize))) // silence

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
                self.app.staticTexts.matching(identifier: MockAID.recordRowName).count > 0
            },
            "Saved mock recording should appear in list"
        )

        let rows = app.staticTexts.matching(identifier: MockAID.recordRowName)
        let latestRow = rows.element(boundBy: max(rows.count - 1, 0))
        if latestRow.exists {
            latestRow.click()
        }

        assertExists(MockAID.recordDetailView, timeout: 5.0)
        assertExists(MockAID.tabPicker, timeout: 5.0)
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
            guard !text.isEmpty else { return false }
            if let expectedSubstring, !text.contains(expectedSubstring) {
                return false
            }
            capturedText = text
            return true
        }

        XCTAssertTrue(success, "Expected non-empty transcription text")
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
            replaceFocusedFieldText(editor, with: marker),
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
            replaceFocusedFieldText(editor, with: updatedSummary),
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

    private func openSpeakerMergeSheet() {
        if isSpeakerMergeUIVisible() {
            return
        }

        // In mock mode the merge UI is rendered inline and auto-opened on appear.
        // Wait briefly before attempting to click the manage button.
        if waitUntil(timeout: 2.5, condition: { self.isSpeakerMergeUIVisible() }) {
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
                return
            }

            // Keep the speakers section near the top viewport so inline merge UI
            // remains in the accessibility tree for deterministic querying.
            revealInMainDetailScroll(button)
            if waitUntil(timeout: 1.0, condition: { self.isSpeakerMergeUIVisible() }) {
                return
            }
        }

        XCTFail("Speaker merge sheet should open")
    }

    private func speakerMergeCardCount() -> Int {
        let cardPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            "\(MockAID.speakerChip)_"
        )
        let cards = app.descendants(matching: .any).matching(cardPredicate)
        if cards.count > 0 {
            return cards.count
        }
        return app.checkBoxes.count
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

        let cardPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            "\(MockAID.speakerChip)_"
        )
        if app.descendants(matching: .any).matching(cardPredicate).count > 0 {
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
        let namedFields = app.textFields.matching(renameFieldPredicate)
        if namedFields.count > 0 {
            for index in 0..<namedFields.count {
                let candidate = namedFields.element(boundBy: index)
                if candidate.exists && candidate.isHittable {
                    return candidate
                }
            }
            return namedFields.element(boundBy: 0)
        }

        let genericFields = app.textFields
        if genericFields.count > 0 {
            for index in 0..<genericFields.count {
                let candidate = genericFields.element(boundBy: index)
                if candidate.exists && candidate.isHittable {
                    return candidate
                }
            }
            return genericFields.element(boundBy: 0)
        }

        return app.textFields.firstMatch
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
        let namedFields = app.textFields.matching(renameFieldPredicate)
        let query = namedFields.count > 0 ? namedFields : app.textFields

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
            revealInMainDetailScroll(targetField)
            let fallbackField = firstSpeakerRenameFieldInMergeSheet()
            if fallbackField.exists && fallbackField.isHittable {
                targetField = fallbackField
            }
        }

        if targetField.isHittable {
            targetField.click()
        }

        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        pasteIntoFocusedField(newName)

        if waitUntil(timeout: 1.2, condition: {
            self.speakerFieldValue(of: targetField).contains(newName) || self.anySpeakerRenameFieldContains(newName)
        }) {
            return true
        }

        // Fallback for cases where Cmd+V is swallowed by app-level shortcuts.
        if targetField.isHittable {
            targetField.doubleClick()
            targetField.typeText(newName)
            return waitUntil(timeout: 1.2, condition: {
                self.speakerFieldValue(of: targetField).contains(newName) || self.anySpeakerRenameFieldContains(newName)
            })
        }

        return false
    }

    private func closeSpeakerMergeSheetIfPresented() {
        guard isSpeakerMergeUIVisible() else { return }
        app.typeKey(.escape, modifierFlags: [])
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
            if editor.exists {
                if editor.isHittable {
                    editor.click()
                    return editor
                }
                let center = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.click()
                return editor
            }
            _ = editor.waitForExistence(timeout: 0.2)
        }
        XCTFail("Editor '\(identifier)' should exist and accept focus")
        return editor
    }

    private func confirmSpeakerMerge() {
        let mergeButton = element(MockAID.speakerMergeConfirmButton)
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

    private func ensureAtLeastTwoSpeakersSelectedForMerge() {
        let checkboxes = app.checkBoxes
        XCTAssertGreaterThanOrEqual(checkboxes.count, 2, "Merge sheet should provide at least two speaker checkboxes")

        var selectedCount = 0
        for index in 0..<checkboxes.count where checkboxAt(index: index, in: checkboxes).exists {
            if checkboxIsSelected(checkboxAt(index: index, in: checkboxes)) {
                selectedCount += 1
            }
        }

        guard selectedCount < 2 else { return }

        for index in 0..<checkboxes.count where selectedCount < 2 {
            let checkbox = checkboxAt(index: index, in: checkboxes)
            guard checkbox.exists else { continue }
            if !checkboxIsSelected(checkbox) {
                checkbox.click()
                if checkboxIsSelected(checkbox) {
                    selectedCount += 1
                }
            }
        }
    }

    private func checkboxAt(index: Int, in query: XCUIElementQuery) -> XCUIElement {
        query.element(boundBy: index)
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
