# VibeScribe UI Test Cases

> **34 automated UI tests** across 8 test classes.
> Platform: macOS (XCUITest).
> Modes: seeded library (`--uitesting`) + empty onboarding + mock end-to-end pipeline (`--uitesting --empty-state` + mock env).
>
> **Source of truth**: this file is the canonical contract for UI-test inventory and fast UI automation coverage.
> If it diverges from UI test sources or attached `AccessibilityID` controls, fix both in the same commit.
>
> **Sync rule**: every `func test*` in `VibeScribeUITests/*.swift` must have a case below.
> Check before commit: `grep -Rho 'func test[A-Za-z0-9_]*' VibeScribeUITests/*.swift | wc -l` must equal **34**.
> Validation command: `./scripts/validate_ui_test_cases.sh`.

## Test Class Matrix

| Class | Launch mode | State | Tests |
|---|---|---|---:|
| `PopulatedStateTests` | Shared launch | Seeded data | 9 |
| `EmptyStateTests` | Shared launch | Empty state (`--empty-state`) | 2 |
| `LanguageRestartTests` | Per-test launch | Seeded data (destructive) | 1 |
| `AppLaunchPerformanceTests` | Per-test launch | Seeded data | 1 |
| `DemoScreenshotTests` | Per-test launch | Executive demo screenshot state (`--uitesting` + screenshot env) | 1 |
| `DeleteFlowTests` | Per-test launch | Seeded data (destructive) | 1 |
| `StateTransitionTests` | Per-test launch | Seeded data (destructive) | 1 |
| `MockPipelineFlowTests` | Per-test launch | First-run empty state + mocked recording/transcription/summary/diarization | 18 |

## Optimized Run Profiles (Coverage per Launch)

1. `ui-smoke` (high-coverage smoke, low relaunch budget)
- Scope: `PopulatedStateTests` (all 9), `EmptyStateTests` (all 2), `VS-MOCK-001`.
- Relaunch budget: 3 app launches total (2 shared classes + 1 mock flow).
- Goal: maximize baseline coverage without destructive transitions.

2. `ui-core` (main non-mock product safety)
- Scope: populated + empty + language restart + delete + state transition classes.
- Relaunch budget: 5 app launches (+ in-test restart confirmations in `VS-LANG-001`).
- Goal: primary UX safety net for merge checks.

3. `ui-mock` (full mocked pipeline)
- Scope: all `MockPipelineFlowTests` including provider matrix and timed transcript coverage.
- Relaunch budget: 18 mock launches (one per scenario test); `VS-MOCK-010` runs in a single mock session.
- Goal: pipeline and failure-recovery regression coverage.

4. `ui-screenshot` (demo capture)
- Scope: `VS-DEMO-001`.
- Relaunch budget: 1 app launch in executive demo screenshot mode.
- Goal: deterministic window capture with leadership-oriented sample data for product/demo assets.

## Interactive Coverage (Path-Based)

| Interactive element / control | Covered in flow(s) |
|---|---|
| `sidebarHeader`, `sidebarRecordsList`, `newRecordingButton` | `VS-POP-001`, `VS-EMP-001`, `VS-MOCK-001` |
| `recordRowName`, `recordRowDuration` | `VS-POP-001`, `VS-POP-002`, `VS-MOCK-001` |
| `recordDetailView`, `recordTitle`, `recordTitleEditField` | `VS-POP-001`, `VS-POP-005`, `VS-MOCK-001` |
| `playPauseButton`, `skipBackwardButton`, `skipForwardButton`, `playbackSpeedButton`, `waveformScrubber`, `currentTimeLabel`, `durationLabel` | `VS-POP-002`, `VS-MOCK-001` |
| `tabPicker`, `transcribeButton`, `summarizeButton` | `VS-POP-002`, `VS-POP-003`, `VS-MOCK-001` |
| `transcriptionEditor`, `summaryEditor` | `VS-MOCK-001`, `VS-MOCK-007`, `VS-MOCK-009`, `VS-MOCK-011`, `VS-MOCK-012` |
| `transcriptionModelPicker`, `summaryModelPicker` | `VS-POP-007`, `VS-MOCK-001`, `VS-MOCK-007` |
| `recordingTimer`, `recordingStopButton`, `recordingResumeButton`, `recordingSaveButton`, `recordingCloseButton` | `VS-MOCK-001`, `VS-MOCK-002`, `VS-MOCK-005` |
| `processingProgress` | `VS-MOCK-001`, `VS-MOCK-004`, `VS-MOCK-008` |
| `speakersSection`, `speakerTimeline`, `speakerTimelineSegment_*`, `speakerManageButton`, `speakerMergeSheet`, `speakerMergeCloseButton`, `speakerMergeTargetSelector`, `speakerMergePreview`, `speakerMergeConfirmButton`, `speakerMergeCandidate_*`, `speakerRenameField_*` | `VS-MOCK-002`, `VS-MOCK-003`, `VS-MOCK-009`, `VS-MOCK-012`, `VS-MOCK-016`, `VS-MOCK-019` |
| `tagsSection` + clickable tag chips + `clearFilterButton` | `VS-POP-004` |
| `moreActionsMenu` + menu actions (`Rename`, `Download audio`, `Delete`) | `VS-POP-005`, `VS-DEL-001`, `VS-STATE-001`, `VS-MOCK-001` |
| `openSettingsContextButton`, `settingsView`, `settingsTabPicker`, `settingsProviderPicker`, `settingsLanguagePicker`, `settingsTitleToggle`, `settingsChunkToggle`, `settingsDiarizationToggle`, `settingsCloseButton` | `VS-POP-006`, `VS-EMP-002`, `VS-LANG-001`, `VS-MOCK-014` |
| Restart confirmation alert (`Restart Now`) and relaunch behavior | `VS-LANG-001` |
| `welcomeView`, `welcomeStartRecordingButton`, `welcomeImportAudioButton`, `welcomeSettingsLink`, `emptyStateView` | `VS-EMP-001`, `VS-EMP-002`, `VS-STATE-001`, `VS-MOCK-001` |

Deterministic test probes:
| Probe | Covered in flow(s) |
|---|---|
| `uiTestAppRootRefreshStatus` | `VS-POP-008` |
| `uiTestLaunchPermissionStatus` | `VS-POP-009` |

Elements intentionally out of fast UI automation scope:
1. `dragOverlay` — requires real drag-and-drop interactions from Finder / external files.
2. `mainSplitView`, `selectRecordPlaceholder` — structural anchors (non-interactive containers/placeholders), not action controls.

## 1. PopulatedStateTests — 9 cases

### VS-POP-001 — Workspace Launch and Core Layout
- Method: `testWorkspaceFlow_ShowsSidebarSeededRecordsAndActiveDetail`
- Preconditions:
1. App launched with `--uitesting`.
- Steps:
1. Verify main window is visible.
2. Verify sidebar header, records list, and `New recording` button are visible.
3. Verify detail panel is open for selected record.
4. Verify at least 3 seeded records exist.
5. Verify first record row has non-empty title and visible duration.
- Expected result:
1. Workspace opens in populated mode with stable sidebar + detail split layout.

### VS-POP-002 — Record Browsing Flow
- Method: `testRecordExplorationFlow_SwitchAcrossAllRecordsAndVerifyCoreSections`
- Preconditions:
1. App launched with seeded records.
- Steps:
1. Iterate all records in sidebar and select each.
2. For every selected record, validate: title, player controls, tabs, tags section, speakers section.
- Expected result:
1. Switching records keeps detail screen functional and complete.

### VS-POP-003 — Transcription/Summary Mode Switching Flow
- Method: `testContentModeFlow_SwitchTabsAndValidateActionAvailability`
- Preconditions:
1. App launched with seeded records.
- Steps:
1. Iterate all records in sidebar.
2. For each record switch to Summary tab and capture summarize button state.
3. Switch to Transcription tab and verify transcribe is disabled for seeded no-audio data.
4. Confirm that at least one record has summarize enabled and at least one has summarize disabled.
- Expected result:
1. Tab switching is stable across the whole list, and summarize availability reflects content differences.

### VS-POP-004 — Tags Clickability and Filter Flow
- Method: `testTagFlow_ShowsExistingTagsForDifferentRecordTypes`
- Preconditions:
1. App launched with seeded records and tags.
- Steps:
1. Open `Team Standup`.
2. Verify `meeting` tag exists and click it.
3. If filter-clear control appears, clear active filter.
4. Open `Voice Note`.
5. Verify `personal` tag exists and click it.
6. If filter-clear control appears, clear active filter.
- Expected result:
1. Tags are not only visible but interactive; clicking chips does not break list/detail state.

### VS-POP-005 — More Actions Menu + Rename Round Trip
- Method: `testMoreActionsFlow_ShowsRenameDownloadAndDeleteOptionsAndPerformsRenameRoundTrip`
- Preconditions:
1. `Voice Note` record is selectable.
- Steps:
1. Open `More actions` menu and verify `Rename`, `Download audio`, and `Delete` are present.
2. Close menu with Escape.
3. Trigger `Rename`, update title to temporary value, and submit.
   The inline title editor should select the current name so replacement input overwrites it deterministically.
4. Verify new title in detail and sidebar.
5. Trigger `Rename` again and restore original title.
6. Verify original title is restored.
- Expected result:
1. Menu actions are discoverable and rename flow fully replaces the title end-to-end with rollback, without leaving a partial truncated name.

### VS-POP-006 — Settings Flow from Main Workspace
- Method: `testSettingsFlow_OpenSwitchAllTabsToggleOptionsAndClose`
- Preconditions:
1. Any record is selected in populated state.
- Steps:
1. Open Settings from sidebar gear.
2. On Speech-to-Text tab verify provider and app-language pickers are enabled.
3. Click provider picker and language picker menus to confirm they open.
4. Switch to Summary tab and toggle `Auto title` and `Chunking` once.
5. Switch back to Speech-to-Text tab.
6. Close settings via close button.
7. Verify previously selected record remains selected.
- Expected result:
1. Settings controls are interactive and the settings round trip preserves selection context.

### VS-POP-007 — Non-Mock Model Picker Isolation
- Method: `testModelPickerIsolation_NonMockSessionDoesNotExposeMockModels`
- Preconditions:
1. App launched with seeded non-mock data (`--uitesting`, without mock env flags).
- Steps:
1. Iterate seeded records and open available model pickers in detail tabs.
2. If transcription model picker is present, verify `mock-whisper-v1` / `mock-whisper-v2` are absent.
3. If summary model picker is present, verify `mock-summary-v1` / `mock-summary-v2` / `mock-summary-fail` are absent.
4. Ensure at least one model picker was validated in the non-mock session.
- Expected result:
1. Non-mock sessions never leak mock model entries into model pickers.

### VS-POP-008 — Forced App Root Refresh Keeps Selected Detail Stable
- Method: `testLaunchStabilityFlow_ForcedAppRootRefreshKeepsSelectedRecordUsable`
- Preconditions:
1. App launched with seeded records.
2. Populated UI-test launch enables one forced root `App` body refresh after initial detail render.
- Steps:
1. Verify detail panel is visible and capture the selected record title.
2. Wait for deterministic root-refresh probe to report completion.
3. Verify detail panel is still visible and selected title is unchanged.
4. Switch detail tabs once to confirm the selected record remains fully usable after refresh.
- Expected result:
1. Recomputing the root app scene does not invalidate the selected SwiftData model or crash the app.

### VS-POP-009 — Launch Permission Policy Defers System Audio Prompt
- Method: `testLaunchPermissionFlow_StartUpDefersSystemAudioPreflight`
- Preconditions:
1. App launched with `--uitesting`.
2. Shared populated-state launch exposes a deterministic launch-permission probe.
- Steps:
1. Wait for the launch-permission probe to appear after startup.
2. Verify the probe reports `microphone_only`.
3. Verify populated workspace remains visible after reading the probe.
- Expected result:
1. App startup keeps microphone preflight as the only launch permission action and defers system-audio permission until an explicit recording start.

## 2. EmptyStateTests — 2 cases

### VS-EMP-001 — Empty Onboarding Surface
- Method: `testEmptyOnboardingFlow_ShowsWelcomeAndNoRecords`
- Preconditions:
1. App launched with `--uitesting --empty-state`.
- Steps:
1. Verify empty sidebar state and welcome panel are visible.
2. Verify no record rows exist.
3. Verify onboarding actions (`Start recording`, `Import audio`, sidebar `New recording`) are enabled.
4. Verify detail-only elements (`record detail`, tabs, player controls) are absent.
- Expected result:
1. Empty state is explicit and ready for first user action.

### VS-EMP-002 — Empty State Settings Round Trip
- Method: `testEmptyOnboardingSettingsFlow_OpenSwitchTabsAndReturnToWelcome`
- Preconditions:
1. Empty onboarding screen is visible.
- Steps:
1. Open Settings from welcome link.
2. Verify Speech-to-Text tab content.
3. Switch to Summary tab and verify summary toggles.
4. Switch back to Speech-to-Text tab.
5. Close settings.
6. Verify return to welcome screen.
- Expected result:
1. User can configure app before first recording and safely return to onboarding.

## 3. LanguageRestartTests — 1 case

### VS-LANG-001 — App Language Switch Requires Restart and Rollback
- Method: `testLanguageSwitchFlow_ChangeLanguageRequiresRestartAndRestoreSystemLanguage`
- Preconditions:
1. App launched in populated UI-test mode.
- Steps:
1. Open Settings and normalize baseline to system language (if change occurs, confirm restart).
2. Select the first non-system language in language picker.
3. Verify restart confirmation appears and click `Restart Now`.
4. Verify app terminates and relaunches.
5. Open Settings again, switch back to system language.
6. Verify restart confirmation appears again and click `Restart Now`.
7. Verify app terminates and relaunches with populated UI still accessible.
- Expected result:
1. Language change always requires restart; restart path works; final state is returned to system language.

## 4. AppLaunchPerformanceTests — 1 case

### VS-PERF-001 — Launch Performance Baseline
- Method: `testLaunchPerformance`
- Preconditions:
1. Performance test environment available.
- Steps:
1. Measure app launch with `XCTApplicationLaunchMetric`.
- Expected result:
1. Launch metric is captured for regression tracking.

## 5. DemoScreenshotTests — 1 case

### VS-DEMO-001 — Executive Demo Summary Screenshot
- Method: `testExecutiveDemoScreenshot_CapturesSummaryTabWithLeadershipMeetingContent`
- Preconditions:
1. App launched with seeded executive-demo screenshot data.
2. UI-test launch forces English UI, a team-lead themed records list, a local summary model label (`gpt-oss-20b`), two speaker segments labeled with realistic human names, a speech-like waveform with varied phrases and pauses, and initial playback progress at exactly one-third while paused.
- Steps:
1. Wait for the populated demo workspace to appear.
2. Verify the selected record opens on the Summary tab with non-empty team-lead oriented Markdown content.
3. Verify the summary model picker shows `gpt-oss-20b`.
4. Verify the summary follows the app’s bullet-list prompt style instead of using an H1 heading.
5. Verify sidebar rows use thematic English meeting titles and meeting-type tags relevant to a typical engineering team lead.
6. Verify the selected record shows two named speakers in the speaker timeline rather than role-only labels.
7. Verify the player is paused, current time reflects one-third of the total duration, and the waveform looks like real conversation with varied bursts and pauses instead of synthetic repeated peaks.
8. Capture a window screenshot attachment.
- Expected result:
1. The test produces a deterministic English-language screenshot from the Summary tab that feels native to a local-first engineering team lead workflow: familiar meeting topics, `gpt-oss-20b` selected, high-signal bullet-style summary content, realistic meeting tags, two named speakers, and a paused one-third playback position with a conversation-like waveform. When launched through `./scripts/run_test_sets.sh ui-screenshot`, the exported PNG is copied to Desktop for easy manual reuse.

## 6. DeleteFlowTests — 1 case

### VS-DEL-001 — Delete Confirmation End-to-End
- Method: `testDeleteFlow_CancelThenConfirmRemovesExactlyOneRecord`
- Preconditions:
1. App launched with seeded records.
- Steps:
1. Trigger delete and cancel confirmation.
2. Verify record count remains unchanged.
3. Trigger delete again and confirm.
4. Verify exactly one record is removed.
- Expected result:
1. Both cancel and confirm branches of delete confirmation work as expected.

## 7. StateTransitionTests — 1 case

### VS-STATE-001 — Populated to Empty Transition
- Method: `testDeleteAllFlow_TransitionsFromPopulatedToWelcomeState`
- Preconditions:
1. App launched with seeded records.
- Steps:
1. Repeatedly delete records until list is empty.
2. Verify welcome view appears.
- Expected result:
1. App correctly transitions from populated workflow to empty onboarding workflow.

## 8. MockPipelineFlowTests — 18 cases

### VS-MOCK-001 — First-Run Full Flow, Playback/Scrub, Manual Re-Summary
- Method: `testMockFlow_NoSpeakers_EndToEndFromFirstLaunchToManualSummaryEdit`
- Preconditions:
1. App launched in empty state with mock pipeline enabled.
2. Mock recording source points to project-root `jfk.wav`.
- Steps:
1. Verify first launch empty onboarding state.
2. Start recording from `New recording`.
3. Verify overlay appears and timer is visible.
4. Pause recording.
5. Resume recording.
6. Pause again and save recording.
7. Verify new record appears in sidebar and becomes selected.
8. Verify mocked transcription auto-completes with non-empty text.
9. Verify mocked auto-summary appears.
10. Verify playback controls: play/pause, skip state, speed button.
11. Scrub recorded waveform and verify current time changes.
12. Verify record title remains visible in detail view.
13. Edit transcription, switch summary model, run summarize, verify summary changed for selected model.
14. Edit summary text and verify persisted value remains after tab switch.
- Expected result:
1. Full user journey from first launch to edited summary passes end-to-end on mocked pipeline, including audio playback/scrubbing.

### VS-MOCK-002 — Diarization Surface + Speaker Labels
- Method: `testMockFlow_WithSpeakers_EndToEndIncludesDiarization`
- Preconditions:
1. Mock scenario returns successful transcription + two speaker segments.
2. Mock diarization exposes a deterministic custom speaker name in the annotated transcript.
- Steps:
1. Complete recording save flow.
2. Wait for transcription+summary completion.
3. Verify speaker timeline appears and speaker management button is available.
4. Verify annotated transcription includes the speaker label injected by diarization.
- Expected result:
1. Successful diarization exposes speaker controls and inserts speaker labels into the visible transcript.

### VS-MOCK-003 — Diarization + Minimal Guided Merge
- Method: `testMockFlow_WithSpeakers_MergeSpeakersRoundTrip`
- Preconditions:
1. Mock scenario returns at least two speakers eligible for merge.
- Steps:
1. Complete recording and wait for diarization.
2. Open speaker merge sheet.
3. Verify the sheet shows an explicit close control and a scrollable list of speakers.
4. Verify merge confirmation starts disabled before any speakers are selected.
5. Select the first matching speaker and verify merge confirmation stays disabled while selection is still incomplete.
6. Select another matching speaker and verify the kept-speaker control appears for the selected subset.
7. Verify merge confirmation becomes enabled only after at least two speakers are selected.
8. Execute merge and close sheet.
9. Reopen sheet and verify speaker card count decreased.
- Expected result:
1. Merge flow follows the user’s natural sequence: first mark matching speakers, then optionally adjust which selected speaker stays, then confirm the merge.

### VS-MOCK-004 — Diarization Error with Successful Text Pipeline
- Method: `testMockFlow_DiarizationError_TranscriptionAndSummaryStillAvailable`
- Preconditions:
1. Mock scenario returns transcription+summary success but diarization error.
- Steps:
1. Complete recording and wait for processing.
2. Verify transcription and summary are available.
3. Verify speaker timeline is absent and speaker section shows diarization failure state.
- Expected result:
1. Diarization failure is isolated; core transcript/summary workflow remains usable.

### VS-MOCK-005 — Transcription Error Stops Auto-Pipeline
- Method: `testMockFlow_TranscriptionError_ShowsFailureAndBlocksSummary`
- Preconditions:
1. Mock scenario returns transcription error token.
- Steps:
1. Complete recording and wait for pipeline result.
2. Verify transcription error is shown.
3. Verify transcription remains empty.
4. Verify summarize action stays disabled due missing transcription.
- Expected result:
1. Transcription failure is visible and prevents invalid summary generation.

### VS-MOCK-006 — Empty Transcription Result Handling
- Method: `testMockFlow_EmptyTranscription_ShowsEmptyStateAndAllowsRetry`
- Preconditions:
1. Mock scenario returns empty transcription payload.
- Steps:
1. Complete recording and wait for pipeline result.
2. Verify empty-transcription state is shown.
3. Verify transcription action is enabled for retry.
4. Verify summarize action stays disabled.
- Expected result:
1. Empty transcript is handled as recoverable failure with consistent action gating.

### VS-MOCK-007 — Auto-Summary Error then Manual Recovery with Other Model
- Method: `testMockFlow_AutoSummaryError_ManualRetryWithAnotherModelSucceeds`
- Preconditions:
1. Mock scenario: transcription success, default summary model fails, alternate model succeeds.
- Steps:
1. Complete recording and wait for auto summary failure.
2. Verify summary error state.
3. Switch summary model to alternate mocked model.
4. Trigger manual summarize.
5. Verify new summary appears and differs from failed state.
- Expected result:
1. User can recover from automatic summary failure via model switch + manual retry.

### VS-MOCK-008 — Manual Summary Error Keeps Previous Summary Intact
- Method: `testMockFlow_ManualSummaryError_EditorPreservesPreviousSummary`
- Preconditions:
1. Mock scenario provides initial summary, then selected model returns summary error on manual run.
- Steps:
1. Complete recording and capture initial summary text.
2. Switch to failing summary model.
3. Trigger manual summarize and wait for failure.
4. Verify summary error appears.
5. Verify previous summary text is unchanged.
- Expected result:
1. Failed manual re-summarization does not overwrite existing valid summary.

### VS-MOCK-009 — Three-Speaker Diarization with Subset Merge
- Method: `testMockFlow_ThreeSpeakers_MergeSubsetPreservesTimeline`
- Preconditions:
1. Mock scenario returns three speakers.
- Steps:
1. Complete recording and wait for diarization.
2. Open merge sheet and verify three speaker cards.
3. Merge subset into one target speaker.
4. Verify sheet closes and timeline remains visible.
5. Reopen merge sheet and verify reduced speaker count.
- Expected result:
1. Partial merges are applied correctly without breaking speaker timeline rendering.

### VS-MOCK-010 — Provider Matrix Coverage
- Method: `testMockFlow_ProviderMatrix_TranscriptionReflectsSelectedProvider`
- Preconditions:
1. Mock provider-matrix scenario is available.
2. Provider can be switched in Settings without relaunch.
- Steps:
1. Launch provider-matrix mock scenario once.
2. Iterate supported providers (`default`, `speechAnalyzer` if available, `whisperServer`, `compatibleAPI`) by switching provider from Settings.
3. For each provider, complete recording and verify transcription contains provider-specific token.
- Expected result:
1. Mock transcription is provider-aware per selected provider in a single mock app session.

### VS-MOCK-011 — Timed Transcript Uses Start Timestamps
- Method: `testMockFlow_DefaultProvider_FormatsTranscriptionWithStartTimestamps`
- Preconditions:
1. Mock scenario returns deterministic token-timed transcription with no diarization.
- Steps:
1. Complete recording save flow.
2. Wait for transcription to appear in the editor.
3. Verify transcript contains multiple `[HH:MM:SS]` prefixes.
4. Verify each timestamp prefixes the expected sentence text.
- Expected result:
1. Time-aware transcription is rendered with stable start timestamps only, without showing end-of-range times in the editor.

### VS-MOCK-012 — Speaker Annotation Preserves Start Timestamps
- Method: `testMockFlow_WithSpeakers_PreservesStartTimestampsDuringAnnotation`
- Preconditions:
1. Mock scenario returns deterministic timed transcript ranges and diarization segments for two speakers.
- Steps:
1. Complete recording save flow.
2. Wait for transcription to appear in the editor.
3. Verify speakers section and timeline are visible.
4. Verify annotated transcript still contains the original start-time prefixes.
5. Verify speaker labels are inserted after the timestamp prefix without leftover timestamp fragments.
- Expected result:
1. Diarization augments the timed transcript without corrupting the visible timestamps or truncating sentence text.

### VS-MOCK-013 — Speaker Rename Does Not Leak Across Records
- Method: `testMockFlow_WithSpeakers_SpeakerRenameIsScopedToCurrentRecord`
- Preconditions:
1. Mock scenario returns deterministic two-speaker diarization for every newly created record in the same app session.
2. The first mock record is configured to expose a custom speaker name in annotated transcription.
- Steps:
1. Create the first mocked record and wait for diarization.
2. Verify annotated transcription for the first record contains the custom speaker name.
3. Create a second mocked record in the same session.
4. Verify annotated transcription for the second record does not contain the custom speaker name from the first record.
- Expected result:
1. Speaker names and profiles are scoped to the current record instead of leaking through a global speaker store.

### VS-MOCK-014 — Diarization Can Be Disabled
- Method: `testMockFlow_DiarizationDisabled_TranscriptionStaysAvailableWithoutSpeakerUI`
- Preconditions:
1. Mock scenario returns successful transcription and would normally return speaker diarization.
2. User can open Settings from the empty-state mock session before creating a recording.
- Steps:
1. Open Settings on the speech-to-text tab while `FluidAudio` is selected.
2. Verify the speaker-identification toggle is visible for `FluidAudio`.
3. Switch the transcription provider to a non-FluidAudio option and verify the speaker-identification toggle is hidden.
4. Switch back to `FluidAudio`, disable the speaker-identification toggle, and close Settings.
5. Create a mocked recording and wait for transcription.
6. Verify the transcription editor contains transcript text.
7. Verify the speakers section and speaker timeline are absent for that record.
8. Verify the visible transcript does not inject speaker labels.
- Expected result:
1. Speaker-identification stays scoped to `FluidAudio`, and turning diarization off still leaves a clean, unlabeled transcript path available.

### VS-MOCK-015 — Single Speaker Does Not Label Transcript
- Method: `testMockFlow_WithSingleSpeaker_DoesNotInjectSpeakerLabelIntoTranscript`
- Preconditions:
1. Mock scenario returns successful transcription and diarization with exactly one speaker.
- Steps:
1. Complete recording save flow.
2. Wait for transcription to appear in the editor.
3. Verify transcript contains the expected text.
4. Verify visible transcript does not inject `Speaker:` labels for the single-speaker case.
- Expected result:
1. When diarization finds only one speaker, transcript text stays clean and unlabeled instead of repeating the only speaker name on every line.

### VS-MOCK-016 — Timeline Merges Short Same-Speaker Gaps and Seeks Reliably
- Method: `testMockFlow_SpeakerTimeline_MergesShortSameSpeakerGapsAndSeeksOnClick`
- Preconditions:
1. Mock scenario returns timeline segments where two neighboring segments belong to the same speaker and the pause between them is under 3 seconds.
2. The same mock scenario also contains short segments from different speakers later in the file.
3. Timeline exposes deterministic segment targets for UI automation.
- Steps:
1. Complete recording save flow and wait for diarization.
2. Verify the speaker timeline is visible.
3. Verify same-speaker neighbors with pauses under 3 seconds are merged into one visible block.
4. Verify short segments from different speakers still remain separate visible blocks instead of being collapsed into one dominant color.
5. Click the later visible timeline block.
6. Verify playback time jumps to the start of that block.
- Expected result:
1. Same-speaker segments with gaps under 3 seconds are shown as one continuous block, different speakers remain visually separate, and clicking a timeline block seeks to the beginning of the represented audio span.

### VS-MOCK-017 — Timed Transcript Preserves Raw Tail Beyond Token Timings
- Method: `testMockFlow_DefaultProvider_PreservesTrailingTranscriptTailWhenTokenTimingsEndEarly`
- Preconditions:
1. Mock scenario returns a full raw transcript string, but its token timing stream is truncated before the final word is complete.
- Steps:
1. Complete recording save flow.
2. Wait for transcription to appear in the editor.
3. Verify transcript still contains the full trailing word from the raw transcript, not the truncated token-timing prefix.
- Expected result:
1. The visible timed transcript preserves the raw-text tail when `tokenTimings` end early, instead of cutting the last phrase mid-word.

### VS-MOCK-019 — Speaker Modal Supports Rename Without Merge
- Method: `testMockFlow_WithSpeakers_SpeakerRenamePersistsWithoutMerge`
- Preconditions:
1. Mock scenario returns deterministic two-speaker diarization for the current record.
2. Speaker management is presented through the shared rename/merge modal.
- Steps:
1. Complete recording save flow and wait for diarization.
2. Open the speaker management modal.
3. Verify merge confirmation stays disabled before any merge selection is made.
4. Verify the first two speaker rows keep aligned rename fields with consistent widths.
5. Verify the modal exposes a single close button in the header and does not duplicate it with a footer dismiss action.
6. Edit the first speaker name directly inside the modal without selecting speakers for merge.
7. Close the modal.
8. Verify the visible transcript updates to the renamed speaker label.
9. Reopen the modal and verify the edited speaker name persists.
- Expected result:
1. The same modal supports rename-only edits independently from merge selection, keeps a stable row layout, uses a single header close affordance without duplicated dismiss controls, persists the new name, and reflects it in the annotated transcript.
