# VibeScribe

<img width="700" alt="screenshot" src="https://github.com/user-attachments/assets/53b42ce6-f0d6-405e-b5a1-b3b19fc56c90" />

VibeScribe turns meetings, interviews, and brainstorming sessions into structured notes. Record microphone and optional system audio, watch the transcript stream in, and let AI craft shareable summaries—without leaving the macOS menu bar.

## Highlights
- **Status bar first** – Launch from the menu bar, toggle a compact recording overlay, and jump back to the main window when you need deeper review.  
- **Dual-source capture** – `CombinedAudioRecorderManager` records the mic plus system audio (when ScreenCaptureKit permissions allow) and merges them into a single track.  
- **Drag-and-drop ingest** – Drop audio/video files to import, convert to the app’s m4a format, and persist them with SwiftData.  
- **Live Whisper integration** – Prefer SSE streaming for real-time updates, fall back to classic requests automatically, and watch progress inside the Record Detail view.  
- **AI summaries & auto-titles** – Chunk long transcripts, call any OpenAI-compatible server, and optionally generate a title straight from the summary.  
- **Waveform-first playback** – Seek, scrub, and change speed with cached waveforms so large files stay responsive.  
- **Extensible settings** – Configure multiple endpoints, load remote model lists, and edit chunking prompts without touching source code.

## Requirements
- macOS 15.0 or later (SwiftData + ScreenCaptureKit features).  
- Xcode 15.3 or newer to build the project.  
- Whisper-compatible transcription server (local or remote).  
- OpenAI-compatible API for summarization (optional if you only need transcripts).

## Getting Started
1. Open `VibeScribe.xcodeproj` in Xcode and run the **VibeScribe** scheme on macOS.  
2. On first launch, grant microphone access. System audio capture prompts appear when the overlay first records.  
3. Use the menu bar icon to open the main window or launch the recording overlay.  
4. Configure services in **Settings** before requesting transcripts or summaries.

### Configure Whisper & AI Services
- **Speech to Text** tab: supply the base URL (e.g., `http://localhost:9000/v1/`), optional API key, and model name. Press *Refresh Models* to populate the picker via `ModelService`.  
- **Summary** tab: set the OpenAI-compatible base URL, key, and model. Tweak chunking size, chunk prompt, and final summary prompt as needed. Enable auto title generation to rename recordings as soon as summaries finish.

## How It Works
- **Recording flow** – The floating `RecordingOverlayView` uses `CombinedAudioRecorderManager` to start mic capture immediately, request system audio if allowed, show live meters, and save merged m4a files into `~/Library/Application Support/<bundleID>/Recordings`.  
- **Imports** – `AudioFileImportManager` validates dropped files, converts them to m4a, computes duration, stores a `Record` via SwiftData, and notifies the UI so the new item is auto-selected.  
- **Transcription** – `RecordProcessingManager` queues work per recording, attempts SSE streaming through `WhisperTranscriptionManager`, and updates UI state with partial text. If streaming fails, it retries with a regular Whisper request.  
- **Summarization** – After transcription (automatically or on demand), the manager chunk-splits long text with `TextChunker`, calls the configured LLM endpoint, merges chunk summaries, and optionally generates a title.  
- **Review** – `RecordDetailView` pairs `AudioPlayerManager` playback controls with waveform scrubbing, tabbed transcript/summary views, inline rename/download, and manual retry buttons.

## Project Layout
- `VibeScribeApp.swift` – App entry plus status bar delegate.  
- `Views/` – Main window (`ContentView`), sidebar + detail, overlay, settings, and reusable components.  
- `Managers/` – Recording stack, import pipeline, audio playback, overlay window management, transcription/summarization services, waveform cache.  
- `Models/` – SwiftData models (`Record`, `AppSettings`).  
- `Utils/` – Logger, audio helpers, security helpers, text chunking, API URL builder.  
- `Sources/` – Shared extensions (e.g., `TimeInterval.clockString`).  
- `Assets.xcassets` & `Preview Content` – UI assets and SwiftUI previews.

## Development Notes
- CLI build: `xcodebuild -scheme VibeScribe -configuration Debug -destination 'platform=macOS' build`.  
- Tests are not yet implemented; add XCTest targets under `VibeScribeTests/` when introducing coverage (start with pure utilities like `AudioUtils` or `TextChunker`).  
- Use the centralized `Logger` (`Utils/Logger.swift`) for diagnostics; categories exist for audio, UI, transcription, network, data, security, and LLM activity.  
- Debug-only toggles (such as `simulateEmptyRecordings`) live behind `#if DEBUG` and `@AppStorage`.

## Data & Privacy
- Recordings and merged audio live in `~/Library/Application Support/<bundleID>/Recordings` (falls back to `~/Documents` if necessary).  
- Waveform caches are stored separately via `WaveformCache` to avoid recomputing large files.  
- API keys and prompts persist in SwiftData; they are sanitized before network calls using `SecurityUtils`.  
- Respect macOS privacy prompts—microphone and screen/audio capture permissions are a hard requirement for dual-source recording.

## Troubleshooting
- **No audio or blank transcript** – Confirm the captured file exists in the recordings directory and retry transcription; Whisper errors surface inside the Record Detail view.  
- **Streaming not supported** – If the server does not support SSE, VibeScribe automatically falls back; check settings for correct base URL.  
- **Model list empty** – Use valid base URLs ending in `/v1/`; the Model Service simply calls `GET /models`.
