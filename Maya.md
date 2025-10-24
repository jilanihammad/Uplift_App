# Maya (Uplift) Product & Engineering Guide

Comprehensive reference for engineers, product managers, and stakeholders working on Maya—the AI therapist experience delivered through a Flutter client and FastAPI backend.

---

## 1. Product Snapshot
- **Mission**: Provide empathetic, AI-assisted therapy sessions across text and voice with real-time streaming feedback.
- **Platforms**: Android (primary), iOS, Windows, macOS (Flutter desktop); backend on Google Cloud Run.
- **Core Pillars**: Conversational intelligence, low-latency audio streaming, secure session management, cross-provider LLM and TTS support.
- **Repositories**: Frontend in `ai_therapist_app`, backend in `ai_therapist_backend` within the same mono-repo.

---

## 2. System Architecture Overview
1. **Flutter Client** (`ai_therapist_app`)
   - UI + business logic using BLoC/state managers.
   - Voice capture, streaming playback, and session coordination.
   - Local persistence (SQLite/Drift) for session history, preferences, and cached anchors.
2. **FastAPI Backend** (`ai_therapist_backend`)
   - Unified LLM manager with provider switching (OpenAI, Groq, Anthropic, Google, Azure, DeepSeek).
   - Real-time voice pipeline via WebSocket streaming and rate-limited REST endpoints.
   - PostgreSQL + SQLAlchemy for persistence.
   - Cloud Run entrypoint runs `alembic upgrade head` on container start; manual migrations are only for troubleshooting. Make sure `DATABASE_URL` targets Cloud SQL (not localhost) before any manual run.
   - Personalization persistence (profile basics, anchors, session summaries) exposed via `/api/v1/profile`, `/api/v1/anchors`, `/api/v1/session_summaries` with Firebase-auth guards and idempotent semantics.
3. **Shared Contracts**
   - REST endpoints (`/api/v1/...`) and WebSocket channels for TTS/audio events.
   - Auth via Firebase JWT → backend validation.
   - App Check/Play Integrity for mobile attestation.

Communication flow: mobile captures audio → backend transcription + LLM generation → backend streams TTS audio → client plays while updating UI state.

---

## 3. Frontend (Flutter) Deep Dive
### 3.1 Project Anatomy
- Entry point: `ai_therapist_app/lib/main.dart` – sets up Firebase, logging, DI, routing, global error handling.
- Routing: `ai_therapist_app/lib/config/routes.dart` with `GoRouter` guards for auth/onboarding.
- Dependency Injection: GetIt via `ai_therapist_app/lib/di/service_locator.dart` and `dependency_container.dart`; feature flags in `lib/utils/feature_flags.dart` toggle hybrid pipelines.
- State Management: Primary BLoC (`lib/blocs`) plus helper managers for timers, session scope, and message orchestration.

### 3.2 Voice & Session Pipeline
Key components (all under `lib/services/`):
1. **VoiceSessionBloc** (`voice_session_bloc.dart`) – central coordinator handling events for session lifecycle, mode switching, TTS playback, and amplitude smoothing. Interfaces with legacy `VoiceService` and the new `IVoiceService` facade (Phase 6 hybrid architecture).
2. **VoiceService** (`voice_service.dart`) – orchestrates recording (`AudioRecordingService`), RNNoise-based VAD, backend API calls, playback via `AudioPlayerManager`, file cleanup, and interaction with `SimpleTTSService`.
3. **VoiceSessionCoordinator & AutoListeningCoordinator** – provide modular control of auto-listen, generation counters, and streaming callbacks.
4. **MessageProcessor + TherapyService** – determine whether to call backend endpoints or direct LLM providers (controlled by config service and feature flags).
5. **SimpleTTSService & WebSocketAudioManager** – manage buffered streaming audio, interplay with just_audio, and VAD gating using generation callbacks.

Supporting utilities:
- `AudioProcessingService`, `RNNoiseService`, and `EnhancedVADManager` for noise suppression and speech detection.
- `SessionScopeManager` to clean up resources when voice sessions end.
- `MemoryManager`, `MemoryService`, and `ConversationMemory` to persist session anchors and insights.

### 3.3 Data Layer
- **Remote**: `lib/data/datasources/remote/api_client.dart` handles REST/WebSocket interactions with token injection and request logging.
- **Local**: `lib/data/datasources/local` (`DatabaseProvider`, `AppDatabase`, `PrefsManager`) for SQLite via Drift and shared preferences.
- **Repositories**: Auth, session, message, and user repositories under `lib/data/repositories` wrap data sources for testability.

### 3.4 Configuration & Feature Flags
- `.env` managed via `lib/config/app_config.dart`; defaults to production backend Cloud Run URL. `ttsStreamingEnabled` and other toggles read from env to control pipeline behavior.
- `FeatureFlags` (shared prefs-backed) manage runtime switches like the refactored voice pipeline.
- Firebase initialization handled by `lib/utils/firebase_init.dart`; logging via `utils/logging_service.dart` and `AppLogger`.

### 3.5 Presentation Layer
- Screens live in `lib/screens` (splash, auth, chat, profile, history, resources, settings, onboarding, diagnostics, tasks).
- Widgets and UI components under `lib/widgets` and `lib/presentation` with theme configuration in `lib/config/theme.dart`.
- Design emphasizes theme-aware components (session summary cards, action lists) and dark mode support.

### 3.6 Platform Integration
- Android entry: `android/app/src/main/kotlin/com/maya/uplift/MainActivity.kt` with wakelock method channel, `UpliftApplication.kt` for Firebase/App Check bootstrap, and `AppCheckProvidersManager.kt` for provider selection (Play Integrity vs debug).
- Permissions and network config in `android/app/src/main/AndroidManifest.xml` and `res/xml/network_security_config.xml` (see `Before-Release.md` for tightening before store submission).

### 3.7 Testing & Tooling
- Unit/widget tests in `ai_therapist_app/test/` using `bloc_test`, `mocktail`, etc.
- Integration tests under `integration_test/` covering end-to-end voice sessions, auto mode scenarios, dark mode persistence, timestamp fixes.
- CI/quality commands: `flutter analyze`, `flutter test`, `flutter test integration_test`, plus targeted scripts from doc files (`test_checklist.md`, `quick_test_guide.md`).
- Specialized docs: `TTS_BUFFERING_IMPLEMENTATION.md`, `TTS_CLEANUP_COMPLETE_REPORT.md`, `WAKELOCK_IMPLEMENTATION.md`, `AUTO_MODE_PERSISTENCE_FIX.md`, etc., catalogue historical fixes and expected behavior.

### 3.8 Developer Workflow
1. `flutter pub get`
2. Configure `.env` (if necessary) with backend URL and flags.
3. Run locally via `flutter run`; choose device/emulator.
4. For debugging voice pipeline, leverage `lib/debug_app.dart`, `debug_api.dart`, and `monitor_logs.sh`.
5. Use GetIt service locator logs to ensure dependencies are registered; consult `PHASE_6_MIGRATION_STATUS.md` for hybrid architecture decisions.

---

## 4. Backend (FastAPI) Deep Dive
### 4.1 Project Anatomy
- Entrypoint: `ai_therapist_backend/app/main.py` loads env, configures logging, initializes DB, and mounts routers.
- API Router: `app/api/api_v1/api.py` aggregates endpoints under `/api/v1`.
- Endpoints: REST + WebSocket in `app/api/endpoints/` (`ai.py`, `voice.py`) with dependencies in `app/api/deps`.
- Services: `app/services/` includes `llm_manager.py`, `therapy_service.py`, `streaming_pipeline.py`, `transcription_service.py`, rate limiting, and voice service docs.

### 4.2 LLM & Audio Management
- **LLM Manager** (`app/services/llm_manager.py`): unified interface routing chat, TTS, and transcription to configured providers (see `app/core/llm_config.py`). Features tenacity retry policies, circuit breakers (Phase 2), HTTP client pooling, and version enforcement for the OpenAI SDK.
- **Streaming Pipeline** (`app/services/streaming_pipeline.py`): handles binary WebSocket frames, flow control, interrupt acknowledgment, and adaptive buffering for sub-400 ms latency targets.
- **Rate Limiting & Security**: `app/core/rate_limiter.py`, `security_middleware.py`, `websocket_enhancements.py`, and `voice.py` implement JWT validation, session limits, origin/subprotocol checks, and text input limits (30 req/min per user).
- **Provider Modularization**: `app/core/phase2_integration.py`, `phase3_fast_path.py`, `phase3_streaming_tts.py` compose provider-specific hooks and fallbacks.

### 4.3 Persistence & Config
- Database models and CRUD logic in `app/db`, `app/models`, `app/crud` (SQLAlchemy).
- Config & secrets handled via `app/core/config.py`, `.env`, and environment variable loading (supports `.env.dev` for local).
- Encryption utilities and rate limit state stored via `app/services/encryption_service.py`, `rate_limit_coordinator.py`.

### 4.4 Testing & Diagnostics
- Rich suite of pytest modules in `ai_therapist_backend/tests/` and specialized scripts (e.g., `test_streaming_pipeline.py`, `test_opus_streaming.py`, `test_ttfb_metrics.py`, `test_phase1_optimizations.py`).
- Benchmark tools (`benchmark_ttfb.py`, `phase3_optimized.csv`, `benchmark_results.csv`) track latency improvements.
- Manual test scripts (`test_backend_smoke.sh`, `test_mode_switching.py`, `test_wav_fix.py`) ensure stability across audio formats and provider fallbacks.
- Observability via `app/core/enhanced_logging.py`, `performance_monitor.py`, `http_client_manager.py` for tracing and metrics (OpenTelemetry-ready).

### 4.5 Local Development & Deployment
1. `pip install -r requirements-dev.txt`
2. Configure `.env.dev` and `.env` with provider keys (OpenAI, Groq, Anthropic, etc.).
3. Launch dev server: `python dev_server.py` or `uvicorn app.main:app --reload`.
4. Run tests: `pytest`, targeted scripts, and streaming benchmarks.
5. Deployment: `deploy_to_cloud.sh` or Cloud Build pipeline; Dockerfiles provided for various environments (`Dockerfile.cloudrun`, `.simple`, `.test`).
6. Cloud Run expects GCP Project with Cloud SQL Postgres; see `ai_therapist_backend/README.md` and `deploy_to_cloud.sh`.

### 4.6 Production Hardening Highlights
- JWT session tracking with concurrent-session limits and automatic invalidation.
- Interrupt acknowledgment protocol ensures no overlapping audio on rapid user input.
- Adaptive TTS formats (WAV, Opus, AAC) based on network scoring, reducing bandwidth while meeting quality targets.
- Binary WebSocket frames reduce payload size by ~33%, keeping CPU and latency in check.
- App Check integration expects Play Integrity tokens; same tokens validated server-side before streaming.

---

## 5. Infrastructure & Operations
- **Hosting**: Google Cloud Run (backend) with Cloud SQL (PostgreSQL). Storage for audio artifacts via GCS (configured in deploy scripts).
- **CI/CD**: Scripts for local smoke (`test_backend_smoke.sh`), Cloud Build YAML for deployment, and PowerShell helpers for Windows builds.
- **Monitoring**: Logging and metrics via custom `logger` wrappers and `performance_monitor`. Integrate with Google Cloud Monitoring using provided exporters.
- **Secrets Management**: GCP Secret Manager for API keys (OpenAI, Groq, Anthropic, Stripe, encryption keys). `.env` files should not ship in production—use environment variables instead.

---

## 6. Testing Strategy Summary
- **Frontend**: Unit tests (voice pipeline, feature flags, theme), widget/integration tests (session flows, auto mode). Use `test_checklist.md` for release gates.
- **Backend**: Pytest suites grouped by features (LLM routing, audio streaming, rate limiting). Replay tests for VAD/Opus issues ensure regression protection.
- **Performance**: Benchmarks for TTFB and audio streaming latency; soak tests (`soak_test.js`) simulate long-running sessions.
- **Security**: Automated checks for JWT/session handling, App Check enforcement, and rate limiting. See `Before-Release.md` for additional pre-launch validations and tests.

---

## 7. Release & Compliance
- **Android Play Store**: Follow `Before-Release.md` to re-enable App Check, tighten network security, remove debug dependencies, validate permissions, scrub secrets, and execute new automated tests.
- **Data Safety**: Ensure declarations cover audio capture, transcript storage, and analytics usage. Provide privacy policy links inside the app (Settings/About).
- **Build Artifacts**: Prefer `flutter build appbundle` for release; backend deployed via Cloud Run (continuous or manual using `deploy_to_cloud.sh`).
- **Observability Post-Launch**: Monitor error logs (App Logger, backend structured logs), TTS latency metrics, and rate limit dashboards.
- **Personalization Sync Rollout**: New backend endpoints are protected by the `memory_persistence_enabled` flag on the client. Keep it disabled until staging validates end-to-end profile/anchor/session summary sync.

---

## Recently Logged Updates
- Backend now connects to Cloud SQL (instance `jilaniuplift` in `us-central1`) and runs migrations automatically via `scripts/entrypoint.sh` on Cloud Run startup.
- New Alembic revision adds `user_profiles`, `session_anchors`, and `session_summaries` with UUID primary keys and soft-delete semantics; migration stamped head and tested against Cloud SQL.
- Personalization API exposed at `/api/v1/profile`, `/api/v1/anchors`, `/api/v1/session_summaries`; all require Firebase JWT and support idempotent updates.
- Desktop/mobile builds currently gate personalization sync behind `memory_persistence_enabled`; client-side sync implementation is next.
- Home screen UI refreshed: greeting card uses a FilledButton with theme colors, “Talk Now” uses an OutlinedButton wrapped in a surfaceVariant container for lighter look in light theme.
- MemoryService now syncs profile basics and anchors with the backend when `memory_persistence_enabled` is enabled; ChatScreen pushes session summaries via `/session_summaries:upsert` after local save.
- MemoryService queues profile/anchor updates locally (SharedPreferences) and flushes them once network sync succeeds, improving offline resilience of personalization.
- Mood persistence MVP shipped: Cloud SQL `user_mood_entries` table + Flutter SQLite cache with `mood_persistence_enabled` feature flag, batched sync, and 60-day retention.

---

## 8. Onboarding Checklist for New Contributors
1. **Read Key Docs**: `Maya.md` (this file), `CLAUDE.md`, `DOCUMENTATION_STRUCTURE.md`, backend `LLM_CONFIGURATION_GUIDE.md`, and `Before-Release.md`.
2. **Set Up Environment**:
   - Frontend: install Flutter 3+, configure Firebase project (copy relevant `google-services.json`).
   - Backend: Python 3.9+, virtualenv, set `.env` with API keys, configure PostgreSQL (local or Docker).
3. **Run Baseline Tests**: `flutter test`, `pytest`, streaming smoke tests.
4. **Understand Voice Pipeline**: Review `voice_session_bloc.dart`, `voice_service.dart`, `websocket_audio_manager.dart`, `SimpleTTSService`, and `message_processor.dart`.
5. **Explore Backend Services**: Step through `app/services/llm_manager.py`, `app/api/endpoints/voice.py`, and `app/core` modules.
6. **Check Feature Flags**: Evaluate `FeatureFlags` defaults and toggles when working on voice pipeline or direct LLM access.
7. **Coordinate Deployments**: Familiarize yourself with Cloud Run scripts and App Check considerations before shipping.
8. **Security & Compliance**: Adhere to secret management, logging hygiene, and release gating items captured in `Before-Release.md`.

---

## 9. Additional Resources
- **Troubleshooting**: `fix.md`, `improvements.md`, `streaming.md`, `TTS_STREAMING_IMPLEMENTATION.md`, `verbose_logging_fix_summary.md`.
- **Migration Notes**: `backendRefactor.md`, `PHASE_6_MIGRATION_STATUS.md`, `refactor_progress.md`.
- **Testing Guides**: `test_bulletproof_completion.md`, `test_dark_mode_persistence.dart`, `test_wav_header_fix.dart`.
- **Deployment Helpers**: `deploy_to_cloud.sh`, `deploy_to_cloud.ps1`, `build_*` scripts for Flutter builds.

Stay aligned with the hybrid architecture vision: maintain compatibility while gradually shifting to the interface-driven voice pipeline and modular backend services. When in doubt, review existing documentation and follow the safety-first release process.
