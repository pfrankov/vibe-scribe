# VibeScribe

<table>
  <tr>
    <td><img width="700" alt="VibeScribe" src="https://github.com/user-attachments/assets/374c108c-7ad9-45e0-b625-9878e67dedb8" /></td>
    <td align="center" valign="top"><img width="300" alt="Recording overlay" src="https://github.com/user-attachments/assets/6e0be794-e3fd-42c3-9918-afdf257e20e6" /><br/><i>Always-on-top recording overlay</i></td>
  </tr>
</table>

VibeScribe is a macOS app that records your meetings from any app and turns them into smart summaries using AI.  
🔒 Privacy first—everything can be done using only local AI models.

## Key Features
- Record a meeting from any app (Zoom, Meet, Teams, Discord, Slack, or others) and get a summary in the same language as the conversation.
- Import, transcribe, and summarize existing audio or video files via drag and drop.
- Automatically title your notes from the summary.
- Native transcription option on macOS 26+ with the `Native` provider.
- Pick the on-device transcription language directly in Settings when using the native provider.

## Quick Start

### Record a meeting
1. Click the menu bar icon.
2. Select "Start Recording."
3. Speak or play audio from your computer.
4. Click "Stop" when finished.
5. Get near-instant transcription and a summary.

### Transcribe an existing audio or video file
1. Drag and drop any audio or video file into VibeScribe.
2. Wait for transcription to complete.
3. Wait for summarization to complete.

_Note: You can change the summarization prompt in Settings (Cmd + ,)._

### Retry with a different model
1. Record your meeting with VibeScribe.
2. Change the Transcription or Summarization model to your preferred one.
3. Re-run transcription and summarization.

## Installation

### Download from GitHub Releases
1. Go to the [Releases page](https://github.com/pfrankov/vibe-scribe/releases).
2. Download the latest `.dmg` file.
3. Open the `.dmg` file.
4. Drag VibeScribe to your Applications folder.

### 🚨 First Launch
Because this app is not signed by Apple, you need to do this:
1. Right-click VibeScribe in Applications.
2. Select "Open."
3. Click "Open" in the warning dialog.
4. Or go to System Settings → Privacy & Security → allow the app.

The app will ask for these permissions:
- Microphone — to record your voice
- Screen Recording — to capture system audio

## 1️⃣ Transcription Setup

On macOS 26 or later the default `Native` provider handles speech-to-text locally. Make sure **System Settings → Keyboard → Dictation → On-Device** is enabled and the required locale is downloaded. Follow the steps below only if you prefer a server workflow or your Mac is running an earlier release.

### Option 1: WhisperServer (recommended, private)

Download and run [WhisperServer](https://github.com/pfrankov/whisper-server).

After running WhisperServer:
1. Open VibeScribe Settings.
2. Set Whisper Base URL: `http://localhost:12017/v1/`
3. Leave the API key empty (not needed for a local server).
4. Set Model to `parakeet-tdt-0.6b-v3`.

### Option 2: OpenAI Whisper API
If you have an OpenAI API key:

1. Open VibeScribe Settings.
2. Set Whisper Base URL: `https://api.openai.com/v1/`
3. Create a new [API key](https://platform.openai.com/api-keys).
4. Enter your API key.
5. Set Model to `whisper-1`.

## 2️⃣ Summarization Setup

VibeScribe can create smart summaries using AI. You need an OpenAI-compatible server.

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
- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Steps

1. Clone the repository:
```bash
git clone https://github.com/pfrankov/vibe-scribe.git
cd vibe-scribe
```

2. Open the project in Xcode.

3. Select your development team:
   - Click the project in Xcode
   - Select the VibeScribe target
   - Go to "Signing & Capabilities"
   - Choose your team

4. Build and run:
   - Press `Cmd + R` to build and run
   - Or use the menu: Product → Run

## License
MIT
