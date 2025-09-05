# Repository Guidelines

## Project Structure & Module Organization
- App code lives in `VibeScribe/`.
  - `Views/` (SwiftUI screens and components), `Managers/` (audio, transcription, model services), `Models/` (app state and data types), `Utils/` (logging, helpers), `Assets.xcassets/`, `Info.plist`.
- Xcode project: `VibeScribe.xcodeproj`. Entry point: `VibeScribeApp.swift`.

## Build, Test, and Development Commands
- Open in Xcode: `open VibeScribe.xcodeproj` (run the `VibeScribe` scheme on macOS).
- CLI build: `xcodebuild -scheme VibeScribe -configuration Debug -destination 'platform=macOS' build`.
- CLI test (if a test target exists): `xcodebuild test -scheme VibeScribe -destination 'platform=macOS' -enableCodeCoverage YES`.

## Coding Style & Naming Conventions
- Swift 5+, 4‑space indentation, no trailing whitespace. Prefer SwiftUI idioms.
- Types: PascalCase (`AudioRecorderManager`), methods/properties: lowerCamelCase, constants: lowerCamelCase with `let`.
- Files match primary type (`SettingsView.swift`, `WhisperTranscriptionManager.swift`).
- Use the existing logging helpers in `Utils/Logger.swift` or `Utils/DebugLogger.swift` instead of `print`.

## Testing Guidelines
- Framework: XCTest. Place tests under `<ProjectName>Tests/` mirroring source paths (e.g., `VibeScribeTests/Managers/...`).
- Name files `*Tests.swift` and functions `test...()`. Keep units small and deterministic (mock audio/IO boundaries).
- Aim for coverage on `Managers/` and `Utils/` first (pure logic, error paths).

## Commit & Pull Request Guidelines
- Commits: imperative, concise summaries (e.g., “Refactor audio capture pipeline”, “Add screen capture permission check”).
- Scope changes narrowly; one logical change per commit.
- PRs must include: clear description, rationale, testing steps, and screenshots/GIFs for UI changes. Link issues when applicable.
- PRs should build cleanly via Xcode and `xcodebuild`.

## Security & Configuration Tips
- Do not commit secrets or server URLs with credentials. Use user‑configurable settings (`Models/AppSettings.swift`) and `Keychain`/`UserDefaults` as appropriate.
- Keep third‑party endpoints configurable (Whisper server, OpenAI‑compatible API). Document defaults in README, not source.
- Follow macOS privacy requirements: microphone/screen capture permissions are already handled—do not bypass these flows.
