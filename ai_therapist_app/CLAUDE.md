# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Flutter Commands
- **Run app**: `flutter run` (connects to available device automatically)
- **Build debug APK**: `flutter build apk --debug` or use `build_debug.ps1` 
- **Build release APK**: `flutter build apk --release` or use `build_release.ps1`
- **Clean build**: `flutter clean && flutter pub get`
- **Analyze code**: `flutter analyze`
- **Run tests**: `flutter test`
- **Run integration tests**: `flutter test integration_test/`
- **Get dependencies**: `flutter pub get`

### Testing Commands
- **Run all tests**: `flutter test`
- **Run specific test**: `flutter test test/services/therapy_service_test.dart`
- **Run widget tests**: `flutter test test/widget_test/`
- **Run BLoC tests**: `flutter test test/blocs/`

### Build Scripts (Windows PowerShell)
- `build_debug.ps1` - Build debug APK with Firebase debugging
- `build_release.ps1` - Build production release APK
- `build_cloud_release.ps1` - Build for cloud deployment
- `run_release_test.ps1` - Test release build functionality

### Code Quality Commands
- **Analyze code**: `flutter analyze` (uses `package:flutter_lints/flutter.yaml`)
- **Format code**: `flutter format .`
- **Check dependencies**: `flutter pub deps`

## Architecture Overview

### Core Application Structure

**AI Therapist App** is a Flutter-based voice-enabled therapy application with real-time AI interactions. The app uses BLoC pattern for state management and follows a layered architecture with dependency injection.

### Key Architectural Patterns

1. **BLoC Pattern**: Used for state management, especially in `VoiceSessionBloc` for real-time voice interactions
2. **Service Locator**: Currently transitioning to proper dependency injection (see `refactor.md`)
3. **Repository Pattern**: Data access through repositories in `lib/data/repositories/`
4. **Interface Segregation**: Interfaces defined in `lib/di/interfaces/` for better testability

### Critical Service Dependencies

#### Voice Processing Pipeline
- **VoiceService** (`lib/services/voice_service.dart`) - 1,033 lines, legacy service with reduced functionality (TTS/WebSocket methods moved to TTSService)
- **VoiceSessionBloc** (`lib/blocs/voice_session_bloc.dart`) - Coordinates real-time voice interactions
- **AutoListeningCoordinator** (`lib/services/auto_listening_coordinator.dart`) - Manages voice activity detection
- **RNNoiseService** - Custom noise reduction using RNNoise C++ integration

### Audio Services Architecture

**Status**: ✅ **Refactored** - The monolithic `VoiceService` (originally 1,419 lines, now 1,033 lines) has been successfully split into focused, single-responsibility services.

#### Refactored Audio Services

**VoiceSessionCoordinator** (`lib/services/voice_session_coordinator.dart`) - ~350 lines
- **Role**: Main facade implementing `IVoiceService` interface
- **Responsibilities**: Orchestrates all focused audio services, maintains timing coordination
- **Key Features**: Preserves 125ms timing buffer for Maya's voice detection, manages service initialization
- **Usage**: Primary entry point for voice operations, replaces monolithic VoiceService

**AudioRecordingService** (`lib/services/audio_recording_service.dart`) - ~460 lines  
- **Role**: Handles all audio recording operations
- **Responsibilities**: Microphone access, recording state management, audio level monitoring
- **Interface**: `IAudioRecordingService`
- **Key Features**: VAD integration, noise reduction, recording quality settings

**TTSService** (`lib/services/tts_service.dart`) - ~630 lines
- **Role**: Text-to-speech generation and playback coordination  
- **Responsibilities**: TTS streaming, audio playback, timing management
- **Interface**: `ITTSService`
- **Key Features**: WebSocket TTS streaming, 125ms timing buffer preservation, multiple voice providers
- **Critical**: Maintains the timing fix that prevents Maya from detecting her own voice

**WebSocketAudioManager** (`lib/services/websocket_audio_manager.dart`) - ~590 lines
- **Role**: Real-time audio streaming over WebSocket connections
- **Responsibilities**: WebSocket lifecycle, audio streaming, session management  
- **Interface**: `IWebSocketAudioManager`
- **Key Features**: Connection reuse, automatic reconnection, stream multiplexing

**AudioFileManager** (`lib/services/audio_file_manager.dart`) - ~620 lines
- **Role**: Audio file operations and resource management
- **Responsibilities**: File I/O, caching, cleanup, format validation
- **Interface**: `IAudioFileManager`  
- **Key Features**: Safe file deletion, cache management, temporary file cleanup, FileCleanupManager

#### Service Registration & Dependency Injection

**AudioServicesModule** (`lib/di/modules/audio_services_module.dart`)
- **Purpose**: Centralized registration of all refactored audio services
- **Features**: Lazy singleton registration, dependency order management, initialization coordination
- **Integration**: Registered via `AudioServicesModule.registerServices()` in service locator
- **Validation**: Includes service validation and initialization methods

#### Architecture Benefits

**Single Responsibility Principle**
- Each service has a focused, well-defined purpose
- Easier testing and mocking of individual components
- Reduced complexity compared to 1,419-line monolith

**Interface-Based Design**
- All services implement clear interface contracts
- Better testability and dependency injection
- Easier to swap implementations or add features

**Preserved Critical Features**  
- ✅ **Maya's self-detection issue RESOLVED** with engineer's robust solution in AutoListeningCoordinator
- All existing functionality preserved during refactoring
- Backward compatibility maintained via dual service registration

**Improved Maintainability**
- Smaller, focused files (~350-650 lines each)
- Clear separation of concerns
- Better error isolation and debugging

#### Migration Status

**✅ Completed**: Core audio services refactored and integrated
**🔄 In Progress**: AudioGenerator still uses legacy VoiceService (compatibility)
**📋 Future**: Phase 5 integration of AutoListeningCoordinator and VADManager

#### Service Dependencies

```
VoiceSessionCoordinator (IVoiceService)
├── AudioRecordingService (IAudioRecordingService)  
├── TTSService (ITTSService)
│   └── AudioPlayerManager
├── WebSocketAudioManager (IWebSocketAudioManager)
└── AudioFileManager (IAudioFileManager)
```

**Legacy Compatibility**
- Original `VoiceService` still registered for `AudioGenerator` compatibility
- New `IVoiceService` (VoiceSessionCoordinator) available for new components
- Gradual migration path allows incremental adoption

#### AI Therapy Pipeline  
- **TherapyService** (`lib/services/therapy_service.dart`) - Core AI interaction service, implements `ITherapyService`
- **MessageProcessor** (`lib/services/message_processor.dart`) - Handles message transcription and processing
- **MemoryManager** (`lib/services/memory_manager.dart`) - Conversation context management
- **AudioGenerator** (`lib/services/audio_generator.dart`) - TTS audio generation

#### State Management Flow
```
User Voice Input → VoiceService → VoiceSessionBloc → TherapyService → AI Response → TTS → Audio Output
```

### Data Layer Architecture

#### Repositories
- `SessionRepository` - Therapy session persistence
- `MessageRepository` - Message history management  
- `AuthRepository` - User authentication
- `UserRepository` - User profile management

#### Local Storage
- **SQLite Database** (`lib/data/datasources/local/app_database.dart`) - 726 lines, handles local data
- **SharedPreferences** - User preferences and settings
- **Secure Storage** - Sensitive data like tokens

#### Remote Data Sources
- **Firebase Integration** - Authentication, Firestore, messaging
- **Backend API** (`lib/data/datasources/remote/api_client.dart`) - REST/WebSocket communication
- **WebSocket Streaming** - Real-time voice data transmission

### Service Registration & Dependency Injection

**Current State**: Using service locator pattern (being refactored)
**Target State**: Interface-based dependency injection

#### Interface Contracts
All services implement interfaces from `lib/di/interfaces/`:
- `ITherapyService` - AI therapy interactions
- `IVoiceService` - Voice processing operations  
- `IAuthService` - Authentication operations
- `IMemoryManager` - Context management
- And 20+ other service interfaces

#### Service Registration
Services are registered in `lib/di/service_locator.dart` with specific dependency order requirements.

### Real-Time Features

#### Voice Session Management
The `VoiceSessionBloc` manages complex state transitions:
- `VoiceSessionIdle` → `VoiceSessionRecording` → `VoiceSessionProcessing` → `VoiceSessionPlaying`
- Coordinates with multiple services simultaneously
- Handles audio level monitoring, VAD, and TTS timing

#### Audio Processing Chain
1. **Recording** - High-quality audio capture with noise reduction
2. **VAD Processing** - Voice activity detection with RNNoise
3. **Streaming** - Real-time audio streaming to backend
4. **Transcription** - Speech-to-text processing
5. **AI Processing** - Therapeutic response generation  
6. **TTS Generation** - Text-to-speech synthesis
7. **Playback** - Audio playback with timing coordination

### Critical Timing Dependencies

**Voice Session Timing**: ✅ **RESOLVED** - Maya's self-detection issue fixed using engineer's robust solution. Replaced race-prone timing buffers with combined stream monitoring (AudioPlayer + TTS) and `firstWhere(!busy)` stable state detection. No more 125ms timing dependencies needed.

## Important Development Considerations

### Service Refactoring Status
The codebase is undergoing major refactoring (documented in `refactor.md`). Key issues being addressed:
- Service locator anti-pattern (214 usages)
- Monolithic service classes
- Mixed concerns in UI components  
- Complex state management

### Critical File Sizes & Complexity
- ✅ `voice_service.dart` - 1,033 lines (**REFACTORED** → split into 5 focused services ~350-650 lines each)
- `chat_screen.dart` - 1,092 lines (needs UI/logic separation)
- `service_locator.dart` - 488 lines (being replaced with DI)
- `auto_listening_coordinator.dart` - 940 lines (complex state machine)

### Voice Processing Specifics
- **RNNoise Integration**: Custom C++ plugin for noise reduction
- **Audio Format**: WAV format preferred for processing
- **Sample Rate**: 16kHz standard for voice processing
- **VAD Threshold**: Configurable voice activity detection sensitivity
- **TTS Providers**: Multiple TTS engines supported (OpenAI, Google, Azure)

### Firebase Configuration
- Project: `upliftapp-cd86e`
- App Check enabled for security
- Real-time messaging for notifications
- Firestore for user data persistence

### Environment Configuration
- **Environment Variables**: Configured via `.env` file in assets
- **LLM Providers**: OpenAI, Google Gemini 2.5 Flash, Groq Llama 3.3
- **Backend URLs**: 
  - Local: `http://localhost:8000`
  - Production: `https://ai-therapist-backend-385290373302.us-central1.run.app`
- **TTS Models**: OpenAI GPT-4o-mini-tts (sage voice), Google Gemini TTS (Zephyr voice)
- **Database**: PostgreSQL configuration for backend services

### Testing Infrastructure
- Unit tests in `test/` directory
- Widget tests for UI components
- BLoC tests for state management
- Integration tests for complete flows
- Mock services for testing (`mockito` library)

### Build & Deployment
- Debug builds include Firebase debugging tools
- Release builds optimize for production
- PowerShell scripts automate build processes
- APK output to `C:\Releases` directory

### Platform Support
- **Primary**: Android (main development target)
- **Secondary**: iOS, Web, Windows, macOS, Linux
- **Native Features**: Microphone access, audio processing, wake lock management

### Memory Management
- Automatic cleanup of temporary audio files
- Efficient audio buffer management  
- Resource cleanup on session termination
- Wake lock management for uninterrupted sessions

### CI/CD Pipeline
- **GitHub Actions**: `.github/workflows/ci.yml` runs on push/PR to main
- **Flutter Version**: 3.19.x stable channel required
- **Pipeline Steps**: dependencies → analyze → test → build APK
- **Artifacts**: Release APK automatically uploaded to GitHub

### Code Quality Standards
- **Linting**: Uses `package:flutter_lints/flutter.yaml` recommended rules
- **Analysis**: Run `flutter analyze` before commits
- **Formatting**: Use `flutter format .` for consistent code style
- **No Custom Lint Rules**: Currently follows Flutter defaults

### Key Dependencies
- **Custom Plugin**: `rnnoise_flutter` (C++ noise reduction, local path dependency)
- **State Management**: BLoC pattern (`flutter_bloc: ^9.1.0`)
- **Dependency Injection**: Service locator (`get_it: ^8.0.3`) - being refactored to interfaces
- **Navigation**: `go_router: ^15.0.0`
- **Network**: `dio: ^5.3.2`, `web_socket_channel: ^3.0.1`
- **Audio Stack**: `record: ^5.0.1`, `just_audio: ^0.10.0`, `flutter_tts: ^4.2.2`
- **Testing**: `mockito: ^5.4.6`, `bloc_test: ^10.0.0`