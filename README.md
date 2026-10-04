# VibeScribe

<table>
  <tr>
    <td><img width="700" alt="VibeScribe" src="https://github.com/user-attachments/assets/16f4926d-1657-4154-990d-66bbfd90a9d8" /></td>
    <td align="center" valign="top"><img width="300" alt="Recording overlay" src="https://github.com/user-attachments/assets/6e0be794-e3fd-42c3-9918-afdf257e20e6" /><br/><i>Always-on-top recording overlay</i></td>
  </tr>
</table>

VibeScribe is a macOS app that records your meetings from any app and turns them into smart summaries using AI.  
Transcription can run on your Mac. For a fully local workflow, also configure a local summary server; selecting a remote provider sends the corresponding audio or text to that service.

## Key Features
- Record a meeting from any app (Zoom, Meet, Teams, Discord, Slack, or others) and get a summary in the same language as the conversation.
- Import, transcribe, and summarize existing audio or video files via drag and drop.
- Automatically title your notes from the summary.
- Native transcription option on macOS 26+ with the `Native` provider.
- Pick the on-device transcription language directly in Settings when using the native provider.

## Quick Start

The processing safeguards described below are new since 1.4.0. Until a newer release is available, build the current source to use them.

Requires macOS 26 or later. Configure a summary model and endpoint in Settings before recording if you want automatic summaries. The default FluidAudio transcription provider downloads its models on first use.

### Record a meeting
1. Click the menu bar icon.
2. Select "Start Recording."
3. Speak or play audio from your computer.
4. Stop recording and save it.
5. VibeScribe transcribes the saved audio and creates a summary with your configured summary model.

### Transcribe an existing audio or video file
1. Drag and drop any audio or video file into VibeScribe.
2. Wait for transcription to complete.
3. Wait for summarization to complete using your configured summary model.

_Note: You can change the summarization prompt in Settings (Cmd + ,)._

### Retry with a different model
1. Record your meeting with VibeScribe.
2. Change the Transcription or Summarization model to your preferred one.
3. Re-run transcription and summarization.

## Installation

### Download from GitHub Releases
1. Go to the [Releases page](https://github.com/pfrankov/vibe-scribe/releases).
2. Download `VibeScribe.zip`.
3. Extract the ZIP archive.
4. Drag VibeScribe to your Applications folder.

### First Launch
The 1.4.0 release uses ad-hoc signing and is not notarized. If macOS blocks the app, see [Apple's guidance for opening apps safely](https://support.apple.com/en-us/102445).

The app requests microphone access on launch. Capturing system audio requests the corresponding permission when recording starts. The optional Native provider also requires Speech Recognition authorization.

## 1️⃣ Transcription Setup

The **Default (FluidAudio)** provider runs transcription on your Mac and downloads its models on first use. It needs no Whisper server or API key.

Select **Native** in Settings to use Apple's on-device speech recognition and choose a supported language. Required speech assets may need to download. If Native is unavailable or permission is denied, VibeScribe displays the error; it does not switch to a remote service. Select another provider explicitly to retry elsewhere.

For server-based transcription, choose one of the following options.

### Option 1: WhisperServer (recommended, private)

Download and run [WhisperServer](https://github.com/pfrankov/whisper-server).

After running WhisperServer:
1. Open VibeScribe Settings and select the **WhisperServer** provider.
2. This provider uses `http://localhost:12017/v1/` without an API key.
3. Select a model served by WhisperServer, such as `parakeet-tdt-0.6b-v3`.

### Option 2: OpenAI Whisper API
If you have an OpenAI API key:

1. Open VibeScribe Settings and select **Whisper compatible API**.
2. Set Whisper Base URL: `https://api.openai.com/v1/`
3. Create a new [API key](https://platform.openai.com/api-keys).
4. Enter your API key.
5. Set Model to `whisper-1`.

## 2️⃣ Summarization Setup

Summaries and automatic titles use the separate OpenAI-compatible endpoint in the Summary settings. Select a model and a valid HTTP or HTTPS endpoint before processing. Missing configuration produces a local error and preserves existing content. Local services can use an empty API key; remote services may require one.

### Option 1: Ollama (recommended, private)
1. Install [Ollama](https://ollama.com/download).
2. Download a model:
```bash
ollama pull gemma3:4b
```
3. In VibeScribe Settings, Summary section:
   - OpenAI Base URL: `http://localhost:11434/v1/`
   - Leave the API key empty
   - Model: `gemma3:4b`

### Option 2: OpenAI API
1. Open VibeScribe Settings, Summary section.
2. Set OpenAI Base URL: `https://api.openai.com/v1/`
3. Enter your API key.
4. Set Model to `gpt-5-mini`.

_Note: You can use any OpenAI-compatible provider, such as OpenRouter._

## Build from Source
If you want to build VibeScribe yourself:

### Requirements
- macOS 26.0 or later
- Xcode 26.3 and its bundled Swift compiler are the validated CI toolchain for the pinned dependencies

### Steps

1. Clone the repository:
```bash
git clone https://github.com/pfrankov/vibe-scribe.git
cd vibe-scribe
```

2. Open the project in Xcode.

3. Select the **VibeScribe** scheme. The project uses manual ad-hoc signing for local macOS builds.

4. Press `Cmd + R` to build and run, or use Product → Run.

To run the same unsigned Release compilation as CI:
```bash
xcodebuild -project VibeScribe.xcodeproj -scheme VibeScribe -configuration Release -destination 'platform=macOS' -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

The validation workflow also runs synthetic audio, Unicode, processing-configuration, and content-logging regressions plus targeted UI tests. Synthetic request tests intercept requests in process; they do not test real speech permissions, microphones, or remote APIs.

## License
MIT
