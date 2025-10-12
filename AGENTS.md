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
- No automated tests exist yet; add XCTest targets under `VibeScribeTests/` when you introduce coverage.

## Coding Guidelines
- Swift 5+, four-space indentation, filenames match primary types.  
- Prefer idiomatic SwiftUI and async/Combine patterns already used in managers.  
- Use `Logger` for diagnostics instead of `print`; categories cover audio, UI, transcription, LLM, etc.  
- Follow existing data flow: interact with `Record` and `AppSettings` through SwiftData contexts, post `Notification` events when updating UI state.  
- Keep whitespace clean and stick to ASCII unless files already contain Unicode icons.

## Testing & Debugging Notes
- Add deterministic unit tests for pure logic (`AudioUtils`, `TextChunker`, URL building) first.  
- UI flows rely on SwiftData and AppKit status bar integration—use previews or lightweight harnesses where possible.  
- A debug toggle (`simulateEmptyRecordings`) lives in `AppStorage`; gate debug-only code with `#if DEBUG`.

## Security & Privacy
- Never hardcode credentials; rely on `AppSettings` and sanitize API keys with `SecurityUtils`.  
- Microphone and ScreenCaptureKit permissions are requested on launch—do not bypass the macOS permission dialogs.  
- Respect local storage: audio lives in `~/Library/Application Support/<bundleID>/Recordings`, waveforms under `WaveformCache`.

## Helpful Utilities
- `OverlayWindowManager` wraps the non-activating NSPanel used by the recording overlay.  
- `AudioUtils` centralizes recording directory management, conversions, and merging.  
- `TextChunker` and `ModelService` encapsulate summarization chunking and model discovery—reuse them when extending LLM features.  
- `WaveformCache` stores per-file waveform samples; clear cache via the provided API if audio files change.
