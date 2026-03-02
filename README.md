# Uplift

AI therapist app with real-time chat and voice streaming. Flutter frontend, FastAPI backend, OpenAI for conversation and TTS.

## How It Works

User sends text or voice input from the Flutter app. The app connects to the backend over WebSockets for streaming responses. The backend calls OpenAI for conversation and text-to-speech, streaming audio back in real time.

```
User input (text/voice) → Flutter app → FastAPI backend → OpenAI → streamed response → app
```

**Chat:** `ws://localhost:8000/ws/chat` (JSON messages, streamed responses)

**Voice:** `ws://localhost:8000/voice/ws/tts` (streamed audio output)

## Features

- Text and voice conversations with context-aware responses
- Real-time streaming for both chat and TTS audio
- Session management with conversation history
- Cross-platform: Android (primary), iOS, Windows, macOS

## Architecture

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.0+, BLoC state management |
| Backend | FastAPI (Python 3.9+) |
| AI | OpenAI (chat completions + TTS) |
| Transport | REST + WebSocket |

## Quick Start

### Backend

```bash
cd backend
python -m venv env && source env/bin/activate
pip install -r requirements.txt
cp .env.example .env  # add your OPENAI_API_KEY
uvicorn app.main:app --reload
```

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

Update `lib/config.dart` with your backend URL if not running on localhost.

## Testing

```bash
# Backend
pytest tests/

# Mock mode (no API key needed)
# Set USE_MOCK=true in .env
```

## License

MIT
