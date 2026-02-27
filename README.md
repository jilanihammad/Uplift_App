# AI Therapist App

A cross-platform Conversational AI therapist app with real-time chat and voice (TTS) streaming, built with Flutter (frontend) and Python (FastAPI backend).

---

## Features

- **Conversational AI Therapist**: Engage in text or voice conversations with an AI therapist powered by OpenAI's language models. Get empathetic, context-aware responses for mental wellness support.
- **Real-Time Streaming**: Get instant feedback with streamed chat responses and text-to-speech (TTS) audio for a natural, interactive experience.
- **Voice Mode**: Use voice input for hands-free interaction and hear natural-sounding spoken responses. Ideal for accessibility and on-the-go use.
- **Device Support**: Optimized for Android (tested on SM S938U1), with support for iOS, Windows, and macOS.
- **Modern UI**: Responsive, accessible, and user-friendly interface with dark mode and intuitive navigation.
- **Session Management**: Maintains conversation history and context for personalized interactions.
- **Robust Error Handling**: Graceful handling of network issues, API errors, and reconnections.

---

## System Requirements

- **OS**: Android 9+ (tested on SM S938U1), iOS 14+, Windows 10+, macOS 12+
- **Hardware**: 4GB RAM, 500MB storage
- **Dependencies**:
  - Flutter 3.0+
  - Python 3.9+
  - Git
  - OpenAI API key (for backend)

---

## Architecture

- **Frontend**: Built with Flutter, using BLoC for state management. Connects to the backend via REST and WebSocket for real-time streaming.
- **Backend**: Powered by FastAPI (Python), integrating OpenAI's APIs for chat and TTS. Serves data through REST and WebSocket endpoints (`/ws/chat`, `/ws/tts`).
- **Flow**: User inputs (text/voice) → Frontend → Backend → OpenAI → Streamed responses back to the app.

---

## Quick Start

### Backend Setup

```bash
# Clone the backend repo
git clone https://github.com/your-org/ai-therapist-backend.git
cd ai-therapist-backend
# Create a virtual environment
python -m venv env
source env/bin/activate  # On Windows: env\Scripts\activate
pip install -r requirements.txt
cp .env.example .env  # Add your OPENAI_API_KEY here
uvicorn app.main:app --reload
# Test it: curl http://localhost:8000/health
```

### Frontend Setup

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

- **Backend**: Copy `.env.example` to `.env` and add:
  ```env
  OPENAI_API_KEY=your-key-here
  PORT=8000
  ```
- **Frontend**: Update `lib/config.dart` or `lib/config/app_config.dart` with the backend URL if needed.

---

## Key Endpoints

### Chat Streaming
- **WebSocket:** `ws://localhost:8000/ws/chat`
  - Send JSON messages like `{ "message": "Hello" }`.
  - See [docs/Backend.md](docs/Backend.md) for full message format and examples.

### TTS Streaming
- **WebSocket:** `ws://localhost:8000/voice/ws/tts`
  - Streams audio responses in real time.
  - See [docs/Backend.md](docs/Backend.md) for format and usage.

---

## Testing & Development

- **Run backend tests:** `pytest tests/`
- **Use mock data:** Set `USE_MOCK=true` in `.env`
- **Verify backend is running:** `curl http://localhost:8000/health`
- **Contribute:** See [CONTRIBUTING.md](CONTRIBUTING.md) (to be created)

---

## Documentation

- [Backend Setup & API](docs/Backend.md)
- [Frontend Setup & Integration](docs/Frontend.md)
- [Troubleshooting](docs/Troubleshooting.md)
- [Release & Monitoring](docs/Release.md)

---

## FAQ / Common Issues

- **Why isn't the WebSocket connecting?**
  - Check your backend URL and ensure the server is running and accessible.
- **How do I get an OpenAI API key?**
  - Sign up at https://platform.openai.com/ and create an API key.
- **Audio isn't playing on my device.**
  - Ensure you have granted microphone and audio permissions.

---

## Release Notes

See [docs/Release.md](docs/Release.md) for version history and updates.

---

## License

MIT 
