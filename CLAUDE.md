# CLAUDE.md

## Project Overview

AI Therapist App (Maya) — Full-stack voice & text therapy conversations. Flutter mobile/desktop frontend + Python FastAPI backend.

## Architecture (Post-Refactor April 2026)

### Backend (`ai_therapist_backend/app/`)
- **Framework**: FastAPI with modular service architecture
- **Database**: PostgreSQL (Cloud SQL) with SQLAlchemy + Alembic migrations
- **Entry**: `app/main.py` — app creation, middleware, root endpoints, WebSocket proxies

#### LLM Provider System (`app/services/llm/`)
Strategy pattern — each provider is its own file:
```
app/services/llm/
  manager.py           — Router + singleton (llm_manager)
  base_provider.py     — ABC: generate, stream, tts, transcribe
  providers/
    openai_provider.py    — OpenAI + Azure
    google_provider.py    — Gemini + GeminiLiveSession
    anthropic_provider.py — Claude
    groq_provider.py      — Groq
    xai_provider.py       — Grok/xAI
    deepseek_provider.py  — DeepSeek
```
Adding a new LLM provider = 1 new file in `providers/`.

#### Voice Endpoints (`app/api/endpoints/voice/`)
Split from monolithic voice.py into focused modules:
```
voice/
  streaming.py      — /ws/tts/speech (main WebSocket TTS handler)
  tts.py            — /ws/tts (SimpleTTSService compatible)
  gemini_live.py    — /ws/gemini/live (Gemini duplex)
  transcription.py  — /synthesize, /transcribe
  health.py         — /ping, /rate-limit-status
  security.py       — WebSocketSecurityValidator, JWTSecurityManager
  connection.py     — ConnectionManager, pipeline pool
  rate_limiter.py   — TextInputRateLimiter
```

#### Streaming Pipeline (`app/services/pipeline/`)
```
pipeline/
  pipeline.py        — Core EnhancedAsyncPipeline
  flow_control.py    — FlowControlMonitor, backpressure
  metrics.py         — PipelineMetrics, ProductionMetricsService
  models.py          — StreamingMessage, AudioChunk, CompletionSentinel
```

#### Auth (`app/api/deps/auth.py`)
Firebase → Google Keys (RS256) → Local Secret (HS256, dev-only) fallback chain.
FastAPI dependency: `Depends(get_current_user)` returns `AuthenticatedUser`.

### Frontend (`ai_therapist_app/lib/`)
- **Pattern**: BLoC + GetIt DI
- **State**: Flutter BLoC (primary), Provider (theme only)
- **Voice Pipeline**: VoicePipelineController → MicAutoModeController → VoiceService → AutoListeningCoordinator

#### Key Files
| File | Purpose |
|------|---------|
| `blocs/voice_session_bloc.dart` | Central session orchestrator |
| `services/voice_service.dart` | Voice operations master |
| `services/simple_tts_service.dart` | WebSocket TTS streaming + queue |
| `services/auto_listening_coordinator.dart` | VAD-driven recording |
| `services/enhanced_vad_manager.dart` | RNNoise voice detection |
| `services/audio_player_manager.dart` | just_audio playback |
| `di/service_locator.dart` | GetIt registration |
| `services/pipeline/voice_pipeline_controller.dart` | Pipeline state machine |

## Common Commands

### Flutter
```bash
flutter pub get && flutter analyze && flutter test
flutter run                    # debug
flutter build apk --release    # Android
```

### Backend
```bash
cd ai_therapist_backend
python dev_server.py           # local dev with auto-reload
python -m pytest               # tests
```

### Beads
```bash
bd list                        # all beads
bd show <id>                   # bead details
bd create --title "..." --description "..." --priority 1 --type bug
```

## Environment Variables

### Backend (.env)
```
OPENAI_API_KEY, GROQ_API_KEY, XAI_API_KEY, ANTHROPIC_API_KEY
FIREBASE_PROJECT_ID, GOOGLE_APPLICATION_CREDENTIALS
DATABASE_URL=postgresql://...
```

### Flutter (.env)
```
BACKEND_URL=https://your-backend-url
```

## Key Design Decisions
- Migrations via Alembic only (no create_all)
- WebSocket TTS uses connection pooling (150ms savings)
- VAD: RNNoise at 48kHz, 0.8 confidence threshold
- Audio: WAV default (OPUS disabled), 4KB buffer threshold
- Non-blocking VAD shutdown on Android (AudioRecord.read blocks)
