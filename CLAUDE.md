# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI Therapist App - A full-stack application providing AI-powered therapeutic conversations through voice and text interactions. The project consists of a Flutter mobile/desktop app frontend and a Python FastAPI backend.

## Architecture

### Frontend (ai_therapist_app/)
- **Pattern**: BLoC (Business Logic Component) with hybrid architecture (Phase 6 migration)
- **State Management**: Flutter BLoC, Provider, GetX
- **Dependency Injection**: GetIt service locator
- **Key Services**: VoiceService, TherapyService, AudioProcessingService
- **Platform Support**: Android, iOS, Windows, macOS

### Backend (ai_therapist_backend/)
- **Framework**: FastAPI with modular service architecture
- **Database**: PostgreSQL (Cloud SQL) with SQLAlchemy ORM
- **Cloud SQL Instance**: `jilaniuplift` in `us-central1`, database: `ai_therapist`
- **Automatic Migrations**: Runs `alembic upgrade head` on Cloud Run startup via `scripts/entrypoint.sh`
- **LLM Integration**: Unified LLM manager supporting OpenAI, Groq, Anthropic, Google, Azure, DeepSeek
- **Deployment**: Google Cloud Run with Cloud SQL connection
- **Personalization API**: `/api/v1/profile`, `/api/v1/anchors`, `/api/v1/session_summaries` with Firebase JWT auth

## Common Development Commands

### Flutter App
```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Run in release mode with custom backend
flutter run --release --dart-define=API_BASE_URL=https://your-backend-url

# Build for platforms
flutter build apk --release                 # Android
flutter build ios --release                 # iOS
flutter build windows --release             # Windows
flutter build macos --release               # macOS

# Run tests and analysis
flutter analyze
flutter test
```

### Backend Server
```bash
# Local development (fastest - no Cloud Run deployments needed!)
cd ai_therapist_backend
python dev_server.py                       # Auto-reload, uses .env.dev

# Alternative local development
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Install dev dependencies (first time only)
pip install -r requirements-dev.txt

# Run using dev script
python scripts/dev.py local

# Database migrations
# IMPORTANT: Cloud Run runs migrations automatically via entrypoint.sh
# Manual migrations are only needed for local development or troubleshooting

# For local development with Cloud SQL Proxy
cloud-sql-proxy upliftapp-cd86e:us-central1:jilaniuplift --port=5433
export DATABASE_URL="postgresql://postgres:7860@localhost:5433/ai_therapist"
alembic upgrade head                        # Apply migrations
alembic revision -m "Description"           # Create new migration
alembic stamp head                          # Mark migration as applied (troubleshooting only)

# Deploy to production
bash deploy_to_cloud.sh

# Build and run with Docker
docker build -t ai-therapist-backend .
docker run -p 8080:8080 ai-therapist-backend
```

### Testing Endpoints (Local Development)
```bash
# Health check (local dev server)
curl http://localhost:8000/health

# Test TTS streaming (check for 150-300ms TTFB)
curl -X POST "http://localhost:8000/voice/synthesize" \
  -H "Content-Type: application/json" \
  -d '{"text": "Testing TTS streaming optimization"}'

# Test AI chat
curl -X POST "http://localhost:8000/ai/response" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello world"}'

# Test transcription
curl -X POST "http://localhost:8000/voice/transcribe" \
  -H "Content-Type: application/json" \
  -d '{"audio_data": "base64_audio_here", "audio_format": "mp3"}'

# Production endpoints (for comparison)
curl -X GET "https://ai-therapist-backend-385290373302.us-central1.run.app/health"
```

## Key Technical Decisions

### Audio Architecture
- **Format**: OPUS (ogg_opus) for 60-70% size reduction
- **Streaming**: WebSocket-based real-time audio streaming
- **Processing**: RNNoise for voice activity detection and noise reduction
- **TTS**: Supports multiple providers (OpenAI, ElevenLabs, Google)

### LLM Integration
- **Unified Manager**: Single interface for multiple LLM providers
- **Providers**: OpenAI (GPT), Groq (fast inference), Anthropic (Claude), Google (Gemini)
- **Configuration**: Environment-based provider selection
- **Streaming**: Supports both text and audio streaming responses

### Current Migration (Phase 6)
The codebase is undergoing a hybrid architecture migration to decompose monolithic services:
- VoiceSessionBloc supports both legacy and new interfaces
- Gradual migration of AutoListeningCoordinator, VoiceService
- Target: <15 methods per service class, 80%+ test coverage

## Environment Configuration

### Required Environment Variables
```bash
# Backend (.env)
OPENAI_API_KEY=your-key
GROQ_API_KEY=your-key
DATABASE_URL=postgresql://user:pass@host/db
FIREBASE_CREDENTIALS=path/to/credentials.json

# Flutter App (.env)
API_BASE_URL=https://your-backend-url
FIREBASE_API_KEY=your-key
```

### Database Setup
```bash
# Cloud SQL Connection (for local development)
# Instance: upliftapp-cd86e:us-central1:jilaniuplift
# Database: ai_therapist
# User: postgres, Password: 7860

# Install and run Cloud SQL Proxy
cloud-sql-proxy upliftapp-cd86e:us-central1:jilaniuplift --port=5433

# Set DATABASE_URL for local development
export DATABASE_URL="postgresql://postgres:7860@localhost:5433/ai_therapist"

# Initialize database (migrations run automatically on Cloud Run)
alembic upgrade head

# Seed with test data (if needed)
python scripts/seed_db.py

# Production DATABASE_URL (set in Cloud Run)
# postgresql://postgres:7860@/ai_therapist?host=/cloudsql/upliftapp-cd86e:us-central1:jilaniuplift
```

## Important Implementation Notes

### Threading Model
- Platform channels run on main thread
- Native audio plugins use separate threads
- WebSocket isolates for streaming
- Careful coordination required for audio processing

### Security Considerations
- JWT authentication for API endpoints
- Encryption for sensitive session data
- Rate limiting on all endpoints
- Firebase Auth integration

### Performance Targets
- Audio latency: <100ms for voice detection
- TTS response: <500ms first byte
- Build time: 30% reduction target
- Code complexity: 50% reduction target

## Testing Strategy

### Flutter Tests
- Unit tests with Mockito for service mocking
- Integration tests for critical user flows
- Characterization tests before refactoring

### Backend Tests
- pytest for unit and integration tests
- Mock audio infrastructure for CI/CD
- Test fixtures for LLM responses

## Deployment

### Backend Deployment
```bash
# Deploy to Google Cloud Run
bash deploy_to_cloud.sh

# Manual deployment steps
gcloud builds submit --tag=gcr.io/PROJECT_ID/ai-therapist-backend
gcloud run deploy ai-therapist-backend \
  --image=gcr.io/PROJECT_ID/ai-therapist-backend \
  --platform=managed \
  --region=us-central1 \
  --memory=2Gi \
  --cpu=2
```

### Flutter Release
- Use provided PowerShell scripts for Windows builds
- Follow standard Flutter release procedures for mobile
- Environment-specific builds using --dart-define

## Common Issues and Solutions

### Audio Issues
- If TTS is not working, check OPUS codec support
- For streaming issues, verify WebSocket connection
- VAD sensitivity can be adjusted in AudioProcessingService

### Build Issues
- Clean Flutter build: `flutter clean && flutter pub get`
- Backend dependencies: Ensure Python 3.9+ and all requirements installed
- Firebase config: Verify google-services.json (Android) and GoogleService-Info.plist (iOS)

### Database Issues
- **Migration errors on Cloud Run**: Check that `DATABASE_URL` points to Cloud SQL (not localhost/SQLite)
- **DuplicateTable errors**: Use `alembic stamp head` to mark existing tables as migrated
- **Connection refused**: Ensure Cloud SQL Proxy is running for local development
- **Password authentication failed**: Verify Cloud SQL postgres password is set to `7860`

### API Integration
- Use the LLM manager's unified interface for provider switching
- Check provider-specific environment variables
- Monitor rate limits for external APIs

## Personalization & Persistence

### Backend Tables (added in latest migration)
- **user_profiles**: `id (uuid)`, `user_id (unique)`, `preferred_name`, `pronouns`, `locale`, `version`, `updated_at`
- **session_anchors**: `id (uuid)`, `user_id`, `client_anchor_id`, `anchor_text`, `anchor_type`, `confidence`, `is_deleted`, `last_seen_session_index`, `updated_at`
- **session_summaries**: `id (uuid)`, `user_id`, `session_id (unique)`, `summary_json`, `updated_at`

### API Endpoints (requires Firebase JWT)
```bash
# Profile management
GET /api/v1/profile                         # Get current profile + ETag
PUT /api/v1/profile                         # Update profile (optimistic concurrency)

# Anchor management
GET /api/v1/anchors?since=<timestamp>       # Get deltas with tombstones
POST /api/v1/anchors:upsert                 # Idempotent upsert by client_anchor_id
POST /api/v1/anchors:delete                 # Mark anchor as deleted (tombstone)

# Session summaries
POST /api/v1/session_summaries:upsert       # Idempotent upsert by session_id
```

### Feature Flag
- Client-side sync gated by `memory_persistence_enabled` feature flag
- MemoryService syncs profile/anchors with backend when enabled
- ChatScreen pushes session summaries after local save
- Offline queue persists pending updates in SharedPreferences

## Logging & Observability

### Logging Utilities (app/core/logging_utils.py)
- **ISO-8601 UTC timestamps**: Unified format `2025-10-20T02:53:48Z` across all environments
- **PII scrubbing**: `preview_text()` truncates user messages at INFO level (full text only at DEBUG)
- **Header redaction**: `redact_headers()` protects cookies and auth tokens
- **Latency timing**: `LatencyTimer` class uses monotonic clock for accurate measurements
- **Request tracing**: `create_log_context()` and correlation IDs for distributed tracing

### Follow-up Improvements
See `LOGGING_IMPROVEMENTS_FOLLOWUP.md` for remaining tasks:
- Header redaction in auth/voice endpoints (1-2 hours)
- Correlation ID propagation (2-3 hours)
- Monotonic timing updates (3-4 hours)
- Log level policy cleanup (2-3 hours)

## Recently Logged Updates

### Cloud SQL Migration (commits: e3e306a8, edbbe0bb)
- Backend now connects to Cloud SQL (instance `jilaniuplift` in `us-central1`)
- Migrations run automatically via `scripts/entrypoint.sh` on Cloud Run startup
- New Alembic revision adds `user_profiles`, `session_anchors`, `session_summaries`
- Migration stamped to head and tested against Cloud SQL
- `deploy_to_cloud.sh` updated with Cloud SQL connection and DATABASE_URL

### Personalization Features
- Personalization API exposed at `/api/v1/profile`, `/api/v1/anchors`, `/api/v1/session_summaries`
- All endpoints require Firebase JWT and support idempotent updates
- UUID primary keys and soft-delete semantics for all tables
- Desktop/mobile builds gate personalization sync behind `memory_persistence_enabled`

### Logging Improvements (commit: c8a526d8)
- Created `app/core/logging_utils.py` with security-focused logging helpers
- Updated `app/core/logger.py` with ISO-8601 UTC timestamps
- Updated `app/services/streaming_pipeline.py` to scrub PII from logs
- Preview text only at INFO level, full text at DEBUG level
- Documented remaining improvements in `LOGGING_IMPROVEMENTS_FOLLOWUP.md`

### Flutter Client Sync
- MemoryService now syncs profile basics and anchors with backend when `memory_persistence_enabled` is enabled
- ChatScreen pushes session summaries via `/session_summaries:upsert` after local save
- MemoryService queues profile/anchor updates locally (SharedPreferences) and flushes once network sync succeeds
- Improved offline resilience of personalization features