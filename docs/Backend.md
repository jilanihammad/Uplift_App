# Backend Setup & API Documentation

## Overview

The backend for the AI Therapist App is built with **Python (FastAPI)** and integrates with OpenAI for both chat and text-to-speech (TTS) services. It exposes REST and WebSocket endpoints for real-time streaming of chat and audio.

---

## Tech Stack
- **Python 3.9+**
- **FastAPI** (web framework)
- **Uvicorn** (ASGI server)
- **aiohttp** (for async HTTP requests to OpenAI)
- **OpenAI API** (for LLM and TTS)

---

## Setup Instructions

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

---

## Environment Variables & Configuration

Edit your `.env` file:

```env
OPENAI_API_KEY=your-key-here
PORT=8000
USE_MOCK=false
# Add any other provider keys as needed
```

---

## Endpoints

### Health Check
- **GET** `/health`
- **Response:** `{ "status": "ok" }`

### Chat Completion (REST)
- **POST** `/chat/complete`
- **Body:** `{ "message": "Hello", "history": [] }`
- **Response:** `{ "reply": "Hi there!" }`

### TTS (Text-to-Speech) (REST)
- **POST** `/voice/synthesize`
- **Body:** `{ "text": "Hello!", "voice": "sage" }`
- **Response:** `{ "url": "https://.../audio/123.mp3" }`

### Transcription (REST)
- **POST** `/voice/transcribe`
- **Body:** `{ "audio_data": "<base64>", "audio_format": "m4a" }`
- **Response:** `{ "text": "Transcribed text" }`

---

## WebSocket Streaming Endpoints

### Chat Streaming
- **WebSocket:** `/ws/chat`
- **Connect:** `ws://localhost:8000/ws/chat` (local) or `wss://ai-therapist-backend-.../ws/chat` (prod)
- **Client sends:**
  ```json
  {
    "message": "Hello, Maya!",
    "history": [],
    "session_id": "abc123"
  }
  ```
- **Server streams:**
  - Each chunk:
    ```json
    {
      "type": "chunk",
      "content": "Hi there",
      "sequence": 1,
      "timestamp": "2024-06-09T12:34:56.789Z"
    }
    ```
  - When complete:
    ```json
    {
      "type": "done",
      "sequence": 2,
      "timestamp": "2024-06-09T12:34:57.000Z"
    }
    ```
  - On error:
    ```json
    {
      "type": "error",
      "detail": "Error message",
      "timestamp": "2024-06-09T12:34:57.123Z"
    }
    ```

### TTS Streaming
- **WebSocket:** `/voice/ws/tts`
- **Connect:** `ws://localhost:8000/voice/ws/tts` (local) or `wss://ai-therapist-backend-.../voice/ws/tts` (prod)
- **Client sends:**
  ```json
  {
    "text": "How are you today?",
    "voice": "sage",
    "params": { "response_format": "opus" }
  }
  ```
- **Server streams:**
  - Each chunk:
    ```json
    { "type": "audio_chunk", "data": "<base64 audio>" }
    ```
  - When complete:
    ```json
    { "type": "done" }
    ```
  - On error:
    ```json
    { "type": "error", "detail": "Error message" }
    ```

---

## Testing Endpoints

- **Health:** `curl http://localhost:8000/health`
- **Chat (REST):** `curl -X POST http://localhost:8000/chat/complete -H "Content-Type: application/json" -d '{"message": "Hi"}'`
- **TTS (REST):** `curl -X POST http://localhost:8000/voice/synthesize -H "Content-Type: application/json" -d '{"text": "Hello!"}'`
- **WebSocket (chat):** `wscat -c ws://localhost:8000/ws/chat`
- **WebSocket (tts):** `wscat -c ws://localhost:8000/voice/ws/tts`

---

## Deployment Notes

- Deploy to Google Cloud Run or your preferred cloud provider.
- Set environment variables (API keys, etc.) in your cloud environment.
- Use HTTPS/WSS in production.

---

## Troubleshooting

- **403 Forbidden:** Check API keys and endpoint permissions.
- **WebSocket not connecting:** Ensure correct URL and that the backend is running and accessible.
- **Audio not streaming:** Check OpenAI API key and backend logs for errors.
- **Timeouts:** Increase server timeout settings if needed.

---

## Release & Monitoring

See [Release.md](Release.md) for deployment and monitoring best practices. 