# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Flutter Frontend Commands
```bash
# Development
flutter clean
flutter pub get
flutter run

# Building
flutter build apk --debug          # Android debug
flutter build apk --release        # Android release
flutter build ios                  # iOS build
flutter build web                  # Web build

# Testing
flutter test                       # Run all unit tests
flutter test test/services/        # Test specific directory
flutter test --coverage           # Generate coverage report
flutter test integration_test      # Run integration tests

# Code Quality
flutter analyze                   # Static analysis
dart format .                     # Format code

# Icons Generation
flutter pub run flutter_launcher_icons
```

### Backend Commands (Python/FastAPI)
```bash
# Setup virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
.\venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Run development server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# Database migrations
alembic upgrade head
```

## Architecture Overview

### Frontend Architecture (Flutter/BLoC)

The app follows BLoC pattern with dependency injection:

```
lib/
├── blocs/              # Business Logic Components
│   ├── voice_session_bloc.dart (911 lines - manages session state)
│   └── managers/       # Specialized state managers
├── services/           # Core business services
│   ├── voice_service.dart (1,088 lines - audio/TTS/WebSocket)
│   ├── auto_listening_coordinator.dart (1,282 lines - VAD/recording)
│   └── websocket_audio_manager.dart (WebSocket communication)
├── di/                 # Dependency injection
│   ├── service_locator.dart (814 lines - GetIt setup)
│   └── dependency_container.dart (custom DI container)
└── screens/            # UI layer
```

**Key Architectural Patterns:**
- State Management: BLoC pattern with `flutter_bloc`
- DI: Hybrid approach using GetIt + custom DependencyContainer
- Audio Processing: Custom RNNoise plugin for noise cancellation
- Real-time Communication: WebSocket-based audio streaming

### Backend Architecture (FastAPI)

```
app/
├── api/                # API endpoints
├── services/           # Business logic
│   ├── voice_service.py (TTS/streaming)
│   ├── llm_manager.py (unified LLM interface)
│   └── streaming_pipeline.py (audio streaming)
├── models/             # SQLAlchemy models
└── core/               # Configuration and security
```

**Key Features:**
- Multiple LLM support: OpenAI, Anthropic, Google Gemini
- Audio streaming with OPUS codec
- PostgreSQL with SQLAlchemy ORM
- Google Cloud Run deployment ready

## Critical Refactoring Areas

Based on JulyIssues.md, these services need decomposition:
1. **VoiceSessionBloc** (911 lines) - Extract message handling, timer logic, and state management
2. **AutoListeningCoordinator** (1,282 lines) - Separate VAD, recording, and audio processing
3. **VoiceService** (1,088 lines) - Split audio, TTS, WebSocket, and permissions

## Threading Model

```
Main Thread:
├── VoiceService
├── AutoListeningCoordinator
└── VoiceSessionBloc

Background Isolates:
├── WebSocketAudioManager (dart:isolate)
└── Audio Processing (Platform Channels)

Native Threads:
├── RNNoise VAD (C++)
├── Android AudioManager
└── Android TextToSpeech
```

## Testing Approach

### Flutter Testing
- Unit tests use `mockito` for mocking
- BLoC tests use `bloc_test` package
- Integration tests in `integration_test/` directory
- Characterization tests before refactoring (see `test/blocs/voice_session_bloc_characterization_test.dart`)

### Backend Testing
- pytest framework (implied from structure)
- Test files in `tests/` directory

## Environment Configuration

### Frontend
- Environment variables via `flutter_dotenv`
- API configuration in `lib/config/api.dart`
- Firebase configuration in `firebase_options.dart`

### Backend
- Configuration in `app/core/config.py`
- Environment variables in `.env` file
- Google Cloud secrets for production

## Recent Development Focus

Based on git history:
- OPUS audio codec implementation for streaming
- TTS streaming improvements
- WebSocket safety and cleanup
- Voice session management refactoring

## Important Notes

- The app uses Firebase for authentication, storage, and Firestore
- Custom RNNoise plugin for real-time noise cancellation
- WebSocket-based real-time audio streaming between frontend and backend
- Multiple build scripts available (`build_*.ps1` files)
- Comprehensive refactoring plan in `JulyIssues.md`