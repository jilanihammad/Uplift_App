# Frontend Setup & Integration Documentation

## Overview

The frontend for the AI Therapist App is a cross-platform Flutter application. It features real-time chat and TTS streaming, a modern UI, and robust state management using the BLoC pattern.

---

## Architecture

- **Flutter**: Cross-platform UI toolkit
- **BLoC Pattern**: For state management (ChatBloc, etc.)
- **WebSocket**: For real-time chat and TTS streaming
- **just_audio**: For audio playback
- **UI**: Modern, responsive, and accessible

---

## Setup Instructions

```bash
# Clone the frontend repo
git clone https://github.com/your-org/ai-therapist-app.git
cd ai-therapist-app
flutter pub get
flutter doctor  # Check for any setup issues
flutter run
```

---

## Configuration

- **Backend URL**: Update `lib/config/app_config.dart` (or similar) with your backend's base URL if needed.
- **Permissions**: Ensure microphone and audio permissions are set in `AndroidManifest.xml` and `Info.plist` for Android/iOS.
- **API Keys**: No API keys needed in the frontend; all secrets are managed by the backend.

---

## Streaming Integration

### Chat Streaming
- Uses `web_socket_channel` to connect to `/ws/chat` endpoint.
- Sends initial JSON message with user input, history, and session ID.
- Listens for streamed `chunk`, `done`, and `error` messages.
- Updates chat UI in real time as chunks arrive.

### TTS Streaming
- Uses `web_socket_channel` to connect to `/voice/ws/tts` endpoint.
- Sends JSON message with text, voice, and params (e.g., `{ "response_format": "opus" }`).
- Receives base64-encoded audio chunks, decodes, and plays them using `just_audio`.
- Handles fallback to mp3 if opus is not supported.

---

## Key Files & Structure

- `lib/screens/`: UI screens (chat, voice mode, diagnostics, etc.)
- `lib/blocs/`: BLoC classes for chat, session, etc.
- `lib/services/`: WebSocket, TTS, and audio services
- `lib/config/`: App configuration (backend URL, etc.)
- `lib/data/`: Models and repositories

---

## Testing on Device

- **Android**: Connect your device (e.g., SM S938U1), enable developer mode, and run:
  ```bash
  flutter run
  ```
- **iOS**: Open the project in Xcode, set up signing, and run on a simulator or device.
- **Web/Desktop**: Run with `flutter run -d chrome` or `flutter run -d windows` (limited streaming support).

---

## Troubleshooting

- **WebSocket not connecting**: Check backend URL and network connectivity.
- **Audio not playing**: Ensure permissions are granted and device volume is up.
- **App crashes on startup**: Run `flutter doctor` and resolve any issues.
- **TTS not streaming**: Check backend logs and ensure the endpoint is reachable.

---

## Contributing

- See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on submitting issues and pull requests.

---

## Further Reading

- [Backend Setup & API](Backend.md)
- [Troubleshooting](Troubleshooting.md)
- [Release & Monitoring](Release.md) 