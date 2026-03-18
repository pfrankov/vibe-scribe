# VibeScribe Agent Handbook

## App Overview
- VibeScribe is a macOS 15+ SwiftUI app that records microphone and optional system audio, transcribes it with Whisper-compatible servers, and generates AI summaries through OpenAI-style chat APIs.  
- Status bar integration plus a floating recording overlay keeps the workflow lightweight while SwiftData persists recordings, settings, and generated content.

## Code Layout
- `VibeScribe/Views/` – SwiftUI scenes and components (sidebar, detail view, recording overlay, settings).  
- `VibeScribe/Managers/` – Recording, playback, import, overlay window, transcription, summarization, and waveform caching services.  
- `VibeScribe/Models/` – SwiftData models (`Record`, `AppSettings`).  
- `VibeScribe/Utils/` – Logging, audio helpers, security helpers, chunking, URL builder.  
- `VibeScribe/Sources/` – Cross-cutting extensions (e.g., `TimeInterval.clockString`).  
- Recorded media and caches are written to Application Support via `AudioUtils`.

## Core Workflows
- **Recording pipeline** – `CombinedAudioRecorderManager` orchestrates mic + system capture, merges sources via `AudioUtils`, and drives the Recording Overlay UI.  
- **File import** – `AudioFileImportManager` handles drag-and-drop, format conversion, duration validation, SwiftData persistence, and UI notifications.  
- **Processing pipeline** – `RecordProcessingManager` enqueues transcription (prefers SSE streaming via `WhisperTranscriptionManager`, falls back to polling) and summarization (chunking through `TextChunker`, OpenAI-compatible chat calls, optional auto-title).  
- **Playback & review** – `AudioPlayerManager`, waveform caching, and `RecordDetailView` provide scrubber, speed cycling, inline rename/download, and manual retry controls.  
- **Settings & discovery** – `SettingsView` edits `AppSettings`, tests endpoints, and fetches model lists through `ModelService`.

## Build & Run
- Open `VibeScribe.xcodeproj` and run the **VibeScribe** scheme on macOS.  
- CLI build: `xcodebuild -scheme VibeScribe -configuration Debug -destination 'platform=macOS' build`.  
- UI tests live in `VibeScribeUITests/`; add unit XCTest targets under `VibeScribeTests/` when you introduce coverage.

## Coding Guidelines
- Swift 5+, four-space indentation, filenames match primary types.  
- Prefer idiomatic SwiftUI and async/Combine patterns already used in managers.  
- Use `Logger` for diagnostics instead of `print`; categories cover audio, UI, transcription, LLM, etc.  
- Follow existing data flow: interact with `Record` and `AppSettings` through SwiftData contexts, post `Notification` events when updating UI state.  
- Keep whitespace clean and stick to ASCII unless files already contain Unicode icons.

## Delivery Workflow (Mandatory)
- Any behavior change must start with **user-flow test-case design**, not code changes.
- Before implementation, describe the flow in `VibeScribeUITests/TEST_CASES.md` with:
  - Preconditions,
  - User steps,
  - Expected result,
  - Target UI test method name(s).
- Only after test-case update is done, implement or update UI tests, then implement production code.
- For UI behavior changes, **UI tests are mandatory**. A UI behavior task without UI-test delta is considered incomplete.
- New UI functionality must be designed for testability from day one:
  - stable `accessibilityIdentifier` for interactive controls,
  - deterministic states for UI testing (`VIBESCRIBE_UI_TESTING`, mock pipeline hooks),
  - no hidden timing-only dependencies when a deterministic signal can be exposed.

## Testing & Debugging Notes
- Add deterministic unit tests for pure logic (`AudioUtils`, `TextChunker`, URL building) first.  
- UI flows rely on SwiftData and AppKit status bar integration—use previews or lightweight harnesses where possible.  
- A debug toggle (`simulateEmptyRecordings`) lives in `AppStorage`; gate debug-only code with `#if DEBUG`.
- Use `./scripts/run_test_sets.sh` to run common UI test subsets:
  - `ui-smoke` (fast baseline),
  - `ui-core` (main non-mock flows),
  - `ui-mock` (mock pipeline flows),
  - `ui-all` (full UI suite),
  - `ui-class <ClassName>` / `ui-test <ClassName/testMethod>` for targeted runs.
- **UI test source of truth**: `VibeScribeUITests/TEST_CASES.md` is the canonical contract for UI test inventory, per-class counts, and accessibility coverage scope for fast UI automation.
- **Test case sync rule**: `VibeScribeUITests/TEST_CASES.md` must stay in sync with all UI test sources under `VibeScribeUITests/*.swift`. Sync means: (1) every `func test*` method has a row in markdown, (2) every row maps to an existing method, (3) header total matches `grep -Rho 'func test[A-Za-z0-9_]*' VibeScribeUITests/*.swift | wc -l`, (4) per-class counts match real class method counts.
- **Accessibility coverage rule**: every ID attached through `.accessibilityIdentifier(AccessibilityID.*)` must be either mirrored in UI test IDs (from `VibeScribeUITests/*.swift`) or explicitly listed in `TEST_CASES.md` out-of-scope section with a reason.
- When UI tests, `TEST_CASES.md`, or accessibility IDs change, update both code and markdown in the **same commit** and run `./scripts/validate_ui_test_cases.sh` before committing.
- Minimum gate for UI behavior changes before merge:
  - `./scripts/validate_ui_test_cases.sh`
  - relevant subset via `./scripts/run_test_sets.sh ...` (at least the affected class or scenario)
- UI tests use shared app launches for read-only test classes (`usesSharedLaunch = true`) to minimize launch overhead. All populated-state read-only tests are in a single `PopulatedStateTests` class (one launch). Only destructive tests (delete flows, state transitions) use per-test launches. Preserve this pattern when adding new tests: add populated-state tests to `PopulatedStateTests`, empty-state tests to `EmptyStateTests`, and create a new class only for a distinct destructive scenario.

## Security & Privacy
- Never hardcode credentials; rely on `AppSettings` and sanitize API keys with `SecurityUtils`.  
- Microphone and ScreenCaptureKit permissions are requested on launch—do not bypass the macOS permission dialogs.  
- Respect local storage: audio lives in `~/Library/Application Support/<bundleID>/Recordings`, waveforms under `WaveformCache`.

## Helpful Utilities
- `OverlayWindowManager` wraps the non-activating NSPanel used by the recording overlay.  
- `AudioUtils` centralizes recording directory management, conversions, and merging.  
- `TextChunker` and `ModelService` encapsulate summarization chunking and model discovery—reuse them when extending LLM features.  
- `WaveformCache` stores per-file waveform samples; clear cache via the provided API if audio files change.
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
