# VibeScribe UI Test Cases

> **23 automated UI tests** across 7 test classes.
> Platform: macOS (XCUITest).
> Modes: seeded library (`--uitesting`) + empty onboarding + mock end-to-end pipeline (`--uitesting --empty-state` + mock env).
>
> **Source of truth**: this file is the canonical contract for UI-test inventory and fast UI automation coverage.
> If it diverges from UI test sources or attached `AccessibilityID` controls, fix both in the same commit.
>
> **Sync rule**: every `func test*` in `VibeScribeUITests/*.swift` must have a case below.
> Check before commit: `grep -Rho 'func test[A-Za-z0-9_]*' VibeScribeUITests/*.swift | wc -l` must equal **23**.
> Validation command: `./scripts/validate_ui_test_cases.sh`.

## Test Class Matrix

| Class | Launch mode | State | Tests |
|---|---|---|---:|
| `PopulatedStateTests` | Shared launch | Seeded data | 7 |
| `EmptyStateTests` | Shared launch | Empty state (`--empty-state`) | 2 |
| `LanguageRestartTests` | Per-test launch | Seeded data (destructive) | 1 |
| `AppLaunchPerformanceTests` | Per-test launch | Seeded data | 1 |
| `DeleteFlowTests` | Per-test launch | Seeded data (destructive) | 1 |
| `StateTransitionTests` | Per-test launch | Seeded data (destructive) | 1 |
| `MockPipelineFlowTests` | Per-test launch | First-run empty state + mocked recording/transcription/summary/diarization | 10 |

## Optimized Run Profiles (Coverage per Launch)

1. `ui-smoke` (high-coverage smoke, low relaunch budget)
- Scope: `PopulatedStateTests` (all 7), `EmptyStateTests` (all 2), `VS-MOCK-001`.
- Relaunch budget: 3 app launches total (2 shared classes + 1 mock flow).
- Goal: maximize baseline coverage without destructive transitions.

2. `ui-core` (main non-mock product safety)
- Scope: populated + empty + language restart + delete + state transition classes.
- Relaunch budget: 5 app launches (+ in-test restart confirmations in `VS-LANG-001`).
- Goal: primary UX safety net for merge checks.

3. `ui-mock` (full mocked pipeline)
- Scope: all `MockPipelineFlowTests` including provider matrix.
- Relaunch budget: 10 mock launches (one per scenario test); `VS-MOCK-010` runs in a single mock session.
- Goal: pipeline and failure-recovery regression coverage.

## Interactive Coverage (Path-Based)

| Interactive element / control | Covered in flow(s) |
|---|---|
| `sidebarHeader`, `sidebarRecordsList`, `newRecordingButton` | `VS-POP-001`, `VS-EMP-001`, `VS-MOCK-001` |
| `recordRowName`, `recordRowDuration` | `VS-POP-001`, `VS-POP-002`, `VS-MOCK-001` |
| `recordDetailView`, `recordTitle`, `recordTitleEditField` | `VS-POP-001`, `VS-POP-005`, `VS-MOCK-001` |
| `playPauseButton`, `skipBackwardButton`, `skipForwardButton`, `playbackSpeedButton`, `waveformScrubber`, `currentTimeLabel`, `durationLabel` | `VS-POP-002`, `VS-MOCK-001` |
| `tabPicker`, `transcribeButton`, `summarizeButton` | `VS-POP-002`, `VS-POP-003`, `VS-MOCK-001` |
| `transcriptionEditor`, `summaryEditor` | `VS-MOCK-001`, `VS-MOCK-007`, `VS-MOCK-009` |
| `transcriptionModelPicker`, `summaryModelPicker` | `VS-POP-007`, `VS-MOCK-001`, `VS-MOCK-007` |
| `recordingTimer`, `recordingStopButton`, `recordingResumeButton`, `recordingSaveButton`, `recordingCloseButton` | `VS-MOCK-001`, `VS-MOCK-002`, `VS-MOCK-005` |
| `processingProgress` | `VS-MOCK-001`, `VS-MOCK-004`, `VS-MOCK-008` |
| `speakersSection`, `speakerTimeline`, `speakerManageButton`, `speakerMergeSheet`, `speakerMergeConfirmButton`, `speakerChip`, `speakerRenameField_*` | `VS-MOCK-002`, `VS-MOCK-003`, `VS-MOCK-009` |
| `tagsSection` + clickable tag chips + `clearFilterButton` | `VS-POP-004` |
| `moreActionsMenu` + menu actions (`Rename`, `Download audio`, `Delete`) | `VS-POP-005`, `VS-DEL-001`, `VS-STATE-001`, `VS-MOCK-001` |
| `openSettingsContextButton`, `settingsView`, `settingsTabPicker`, `settingsProviderPicker`, `settingsLanguagePicker`, `settingsTitleToggle`, `settingsChunkToggle`, `settingsCloseButton` | `VS-POP-006`, `VS-EMP-002`, `VS-LANG-001` |
| Restart confirmation alert (`Restart Now`) and relaunch behavior | `VS-LANG-001` |
| `welcomeView`, `welcomeStartRecordingButton`, `welcomeImportAudioButton`, `welcomeSettingsLink`, `emptyStateView` | `VS-EMP-001`, `VS-EMP-002`, `VS-STATE-001`, `VS-MOCK-001` |

Elements intentionally out of fast UI automation scope:
1. `dragOverlay` — requires real drag-and-drop interactions from Finder / external files.
2. `mainSplitView`, `selectRecordPlaceholder` — structural anchors (non-interactive containers/placeholders), not action controls.

## 1. PopulatedStateTests — 7 cases

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
4. Verify new title in detail and sidebar.
5. Trigger `Rename` again and restore original title.
6. Verify original title is restored.
- Expected result:
1. Menu actions are discoverable and rename flow works end-to-end with rollback.

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

## 5. DeleteFlowTests — 1 case

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

## 6. StateTransitionTests — 1 case

### VS-STATE-001 — Populated to Empty Transition
- Method: `testDeleteAllFlow_TransitionsFromPopulatedToWelcomeState`
- Preconditions:
1. App launched with seeded records.
- Steps:
1. Repeatedly delete records until list is empty.
2. Verify welcome view appears.
- Expected result:
1. App correctly transitions from populated workflow to empty onboarding workflow.

## 7. MockPipelineFlowTests — 10 cases

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

### VS-MOCK-002 — Diarization Surface + Speaker Rename
- Method: `testMockFlow_WithSpeakers_EndToEndIncludesDiarization`
- Preconditions:
1. Mock scenario returns successful transcription + two speaker segments.
- Steps:
1. Complete recording save flow.
2. Wait for transcription+summary completion.
3. Verify speaker timeline appears and speaker management button is available.
4. Open speaker management sheet, rename a speaker, close and reopen sheet.
5. Verify renamed speaker name persisted.
- Expected result:
1. Successful diarization exposes speaker controls, and speaker rename persists.

### VS-MOCK-003 — Diarization + Merge Speakers
- Method: `testMockFlow_WithSpeakers_MergeSpeakersRoundTrip`
- Preconditions:
1. Mock scenario returns at least two speakers eligible for merge.
- Steps:
1. Complete recording and wait for diarization.
2. Open speaker merge sheet.
3. Verify multiple speaker cards are present.
4. Execute merge and close sheet.
5. Reopen sheet and verify speaker card count decreased.
- Expected result:
1. Merge flow works and speaker set is actually consolidated.

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
