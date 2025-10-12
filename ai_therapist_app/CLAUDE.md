# CLAUDE.md

Guidance for Claude Code when working inside `ai_therapist_app`.

## Core Commands

```bash
# setup
flutter clean
flutter pub get

# run app
dart run build_runner clean   # only if code-gen artifacts exist
flutter run                    # choose device or emulator

# code quality
flutter analyze
dart format .

# testing
flutter test                   # all unit/widget tests
flutter test integration_test  # integration tests

# builds
flutter build apk --debug
flutter build apk --release
flutter build ios --no-codesign
```

## High-Level Architecture

### State & Presentation
- **BLoC-driven UI**: `lib/blocs` holds `VoiceSessionBloc` plus helper managers for timers, messages, and session scope.
- **Theme-aware screens**: Widgets rely on `Theme.of(context).colorScheme` (recently updated session summary/action cards included).
- **Routing & navigation**: `lib/config/routes.dart` uses `go_router` with auth/onboarding redirects.

### Services & Features
- **Voice pipeline** (`lib/services`):
  - `voice_service.dart` orchestrates recording, TTS, and backend calls via `VoiceSessionCoordinator` and `AutoListeningCoordinator`.
  - `audio_generator.dart`, `simple_tts_service.dart`, and `websocket_audio_manager.dart` handle streaming and playback.
- **LLM interaction**: `message_processor.dart` chooses between direct LLM calls and backend proxy based on config; history handling tuned to avoid role confusion.
- **Memory & anchors**: `memory_manager.dart`, `conversation_memory.dart`, and `memory_service.dart` persist session memories, anchors, and emotional states.
- **Config & feature flags**: `config_service.dart`, `app_config.dart`, and `utils/feature_flags.dart` centralize environment toggles (e.g., direct LLM mode, streaming switches).
- **Dependency injection**: `di/service_locator.dart` + `di/dependency_container.dart` register services; scoped session services use `SessionScopeManager`.

### Real-Time Audio Flow
1. Auto-listening VAD detects speech (`AutoListeningCoordinator`).
2. `VoiceService` records via RNNoise-enhanced recorder (`audio_recording_service.dart`).
3. Transcription/LLM handled by `message_processor.dart` and `therapy_service.dart`.
4. TTS streams back through `simple_tts_service.dart` → `AudioPlayerManager`.
5. Session end guard prevents new TTS once `VoiceSessionStatus.ended` is set.

## Backend Interface (FYI)
Although backend lives in `ai_therapist_backend/`, the Flutter app expects:
- REST endpoints at `/ai/response`, `/therapy/end_session`, etc.
- WebSocket at `/ws/tts` for streaming audio.
- Auth via Firebase (token refresh handled in `auth_service.dart`).

## Testing Strategy
- **Unit/Widget tests** live in `test/` (use `bloc_test`, `mocktail`).
- **Integration tests** under `integration_test/` for end-to-end voice session scenarios.
- Add new tests alongside feature work; keep `flutter analyze` clean.

## Recent Updates (2025-10)
- Session summary/action cards now theme-aware (no hard-coded light colors).
- Session end guard prevents late TTS playback.
- Conversation history normalization fixes “Maya speaking in first person”.
- Login/app titles rebranded from “Uplift” to “Maya”.
- Config/service layers support direct LLM mode and anchor guidance.

## Contribution Tips
- Reference `docs/` files (e.g., `TTS_BUFFERING_IMPLEMENTATION.md`) for historical context.
- Prefer `Theme.of(context).colorScheme` over literal colors.
- When editing voice pipeline, ensure cleanup paths (session end, auto mode) remain consistent.
- Update this file whenever architecture or workflows change—avoid stale line counts or assumptions.
