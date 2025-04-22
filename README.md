# VibeScribe
VibeScribe is a macOS menu bar application for recording, transcribing, and summarizing audio.

## Features
- Records audio from your microphone
- Transcribes audio using a local Whisper server
- Summarizes transcriptions using an OpenAI-compatible API
- Global hotkey for starting/stopping recordings
- Clean and intuitive UI

## Requirements
- macOS 12.0 or later
- A local Whisper server for transcription
- An OpenAI-compatible API endpoint for summarization (local or remote)

## Usage
1. Launch VibeScribe - it will appear as an icon in your menu bar
2. Configure your settings (Whisper server URL, OpenAI-compatible API URL, etc.)
3. Use the global hotkey (default: ⌘⇧R) or the menu bar button to start/stop recording
4. View your recordings and their transcriptions/summaries in the app

## Configuration
The settings panel allows you to configure:

- Global hotkey for recording
- Whisper server URL
- OpenAI-compatible API URL and API key
- Context size for text chunks
- Prompts for summarization