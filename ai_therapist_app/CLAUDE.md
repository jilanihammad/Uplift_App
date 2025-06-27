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

**AI Therapist App** is a Flutter-based voice-enabled therapy application with real-time AI interactions. The app uses BLoC pattern for state management and follows a clean layered architecture with **complete dependency injection** (Phase 6 migration completed).

### Key Architectural Patterns

1. **BLoC Pattern**: Used for state management, especially in `VoiceSessionBloc` for real-time voice interactions
2. **Dependency Injection**: ✅ **COMPLETE** - Interface-based dependency injection with `DependencyContainer` replaces service locator anti-pattern
3. **Repository Pattern**: Data access through repositories in `lib/data/repositories/` with interface contracts
4. **Interface Segregation**: 20+ interfaces in `lib/di/interfaces/` for complete testability and loose coupling
5. **Event-Driven Architecture**: Circular dependencies resolved using event bus pattern (`AuthCoordinator`)

### Critical Service Dependencies

#### Voice Processing Pipeline
- **VoiceService** (`lib/services/voice_service.dart`) - 1,033 lines, legacy service with reduced functionality (TTS/WebSocket methods moved to TTSService)
- **VoiceSessionBloc** (`lib/blocs/voice_session_bloc.dart`) - Coordinates real-time voice interactions
- **AutoListeningCoordinator** (`lib/services/auto_listening_coordinator.dart`) - Manages voice activity detection
- **RNNoiseService** - Custom noise reduction using RNNoise C++ integration

### Audio Services Architecture

**Status**: ✅ **Refactored** - The monolithic VoiceService has been successfully split into focused, single-responsibility services.

#### Core Audio Services

- **VoiceSessionCoordinator** - Main facade implementing `IVoiceService` interface, orchestrates all audio services
- **AudioRecordingService** - Handles microphone access, recording state management, audio level monitoring
- **TTSService** - Text-to-speech generation and playback coordination with WebSocket streaming
- **WebSocketAudioManager** - Real-time audio streaming over WebSocket connections
- **AudioFileManager** - Audio file operations and resource management with cleanup

#### Architecture Benefits

- **Single Responsibility**: Each service has a focused, well-defined purpose
- **Interface-Based Design**: All services implement clear interface contracts for better testability
- **Dependency Injection**: Complete migration to interface-based constructor injection
- **Improved Maintainability**: Smaller, focused files with clear separation of concerns

#### AI Therapy Pipeline  
- **TherapyService** (`lib/services/therapy_service.dart`) - Core AI interaction service, implements `ITherapyService` with 86 interface methods
- **MessageProcessor** (`lib/services/message_processor.dart`) - Handles message transcription and processing with dependency injection
- **MemoryManager** (`lib/services/memory_manager.dart`) - Conversation context management, implements `IMemoryManager`  
- **AudioGenerator** (`lib/services/audio_generator.dart`) - TTS audio generation with constructor injection

#### State Management Flow
```
User Voice Input → IVoiceService (VoiceSessionCoordinator) → VoiceSessionBloc → ITherapyService → AI Response → ITTSService → Audio Output
```

#### DependencyContainer Usage Patterns

**Accessing Services**
```dart
final container = DependencyContainer();
final therapy = container.therapy;           // ITherapyService
final voice = container.voiceService;        // IVoiceService
final auth = container.authService;          // IAuthService
final api = container.apiClient;             // IApiClient
```

**Constructor Injection Pattern**
```dart
class MyWidget extends StatelessWidget {
  final ITherapyService? therapyService;
  
  const MyWidget({this.therapyService});
  
  @override
  Widget build(BuildContext context) {
    final therapy = therapyService ?? DependencyContainer().therapy;
    // Use therapy service...
  }
}
```

**Service Implementation Pattern**
```dart
class MyService implements IMyService {
  final IApiClient _apiClient;
  final IMemoryManager _memoryManager;
  
  MyService({
    required IApiClient apiClient,
    required IMemoryManager memoryManager,
  }) : _apiClient = apiClient, _memoryManager = memoryManager;
  
  @override
  Future<void> doSomething() async {
    // Implementation using injected dependencies
  }
}
```

### Data Layer Architecture

#### Repositories (✅ Phase 6 Complete - All with Interface Contracts)
- `SessionRepository` - Therapy session persistence, implements `ISessionRepository`
- `MessageRepository` - Message history management, implements `IMessageRepository`
- `AuthRepository` - User authentication, implements `IAuthRepository`
- `UserRepository` - User profile management, implements `IUserRepository`

All repositories use constructor injection with `IApiClient` and `IAppDatabase` dependencies.

#### Local Storage
- **SQLite Database** (`lib/data/datasources/local/app_database.dart`) - 726 lines, handles local data
- **SharedPreferences** - User preferences and settings
- **Secure Storage** - Sensitive data like tokens

#### Remote Data Sources
- **Firebase Integration** - Authentication, Firestore, messaging
- **Backend API** (`lib/data/datasources/remote/api_client.dart`) - REST/WebSocket communication
- **WebSocket Streaming** - Real-time voice data transmission

### Dependency Injection Architecture

**Status**: ✅ **Complete** - Full dependency injection migration achieved with interface-based design

#### Key Features
- **Interface-Based Design**: All services implement comprehensive interfaces from `lib/di/interfaces/`
- **Modular Registration**: Services organized through CoreModule, ServicesModule, and AudioServicesModule
- **Event-Driven Patterns**: Circular dependencies resolved using AuthCoordinator and event streams
- **Clean Access**: DependencyContainer provides convenient service access

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

**Voice Session Timing**: ✅ **RESOLVED** - Maya's self-detection issue fixed with robust stream monitoring solution.

## Development Considerations

### Completed Architectural Refactoring

✅ **Migration Complete** - The codebase has successfully completed major architectural improvements:
- **Service Locator Anti-pattern**: ✅ Eliminated
- **Monolithic Services**: ✅ Refactored into focused, single-responsibility components
- **UI/Logic Separation**: ✅ Clean dependency injection in UI components
- **Complex State Management**: ✅ Interface-based dependency injection with event-driven patterns

### New Development Workflow

#### Using the DependencyContainer
```dart
// Modern dependency injection pattern
class SomeWidget extends StatelessWidget {
  final ITherapyService? therapyService;
  final IAuthService? authService;
  
  const SomeWidget({
    this.therapyService,
    this.authService,
  });
  
  @override
  Widget build(BuildContext context) {
    final container = DependencyContainer();
    final therapy = therapyService ?? container.therapy;
    final auth = authService ?? container.authService;
    // Clean, testable architecture
  }
}
```

#### Service Creation Pattern
```dart
// All services now use constructor injection
class NewService implements INewService {
  final IApiClient _apiClient;
  final IMemoryManager _memoryManager;
  
  NewService({
    required IApiClient apiClient,
    required IMemoryManager memoryManager,
  }) : _apiClient = apiClient, _memoryManager = memoryManager;
}
```

#### Dependency Injection Best Practices
1. **Interface First**: Always implement service interfaces for testability
2. **Constructor Injection**: Use constructor parameters for all dependencies
3. **Optional Parameters**: Support optional dependencies with fallback to DependencyContainer
4. **@override Annotations**: Properly document interface implementations

#### Testing Support
```dart
// Easy mocking with interfaces
class MockTherapyService implements ITherapyService {
  @override
  Future<String> processMessage(String message) async {
    return 'Mock response';
  }
}

// Inject mocks in tests
MyScreen(
  therapyService: MockTherapyService(),
  authService: MockAuthService(),
)
```

### Code Quality Improvements
- ✅ **Voice Service Refactoring** - Split monolithic service into 5 focused services
- ✅ **UI Components** - Migrated to constructor injection with interface dependencies
- ✅ **Services & Repositories** - All use interface-based dependency injection
- ✅ **Service Locator Replacement** - Clean `DependencyContainer` interface implemented

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
- **Dependency Injection**: ✅ **Interface-based DI** (`get_it: ^8.0.3`) with `DependencyContainer`
- **Navigation**: `go_router: ^15.0.0`
- **Network**: `dio: ^5.3.2`, `web_socket_channel: ^3.0.1`
- **Audio Stack**: `record: ^5.0.1`, `just_audio: ^0.10.0`, `flutter_tts: ^4.2.2`
- **Testing**: `mockito: ^5.4.6`, `bloc_test: ^10.0.0`

### Architectural Achievements

- **Interface Coverage**: 20+ service interfaces implemented
- **Dependency Injection**: 100% migration from service locator pattern
- **Testability**: All components mockable via interface contracts
- **Performance**: Maintained performance with improved compile-time validation

## ✅ Dependency Injection Migration Complete

### Summary

The AI Therapist App has successfully completed its architectural migration from service locator anti-pattern to modern interface-based dependency injection.

### Key Achievements

- **Service Locator Elimination**: Complete removal of service locator anti-pattern
- **Interface-Based Architecture**: 20+ service interfaces with comprehensive contracts
- **Constructor Injection**: All services use dependency injection via constructors
- **Event-Driven Patterns**: Circular dependencies resolved using AuthCoordinator
- **Modular Registration**: Clean service organization through CoreModule, ServicesModule, AudioServicesModule

### Developer Standards

#### Service Development
1. **Interface First**: Always implement service interfaces
2. **Constructor Injection**: Use dependency injection for all dependencies
3. **Optional Parameters**: Support testing with optional constructor parameters
4. **@override Annotations**: Document interface implementations properly

#### UI Development
1. **Dependency Injection**: Use optional constructor parameters for services
2. **Fallback Pattern**: `service ?? DependencyContainer().serviceGetter`
3. **Interface Usage**: Depend on interfaces, not concrete implementations
4. **Testability**: All components easily mockable

### Benefits Achieved

- **Clean Architecture**: Modern, maintainable codebase with clear boundaries
- **Enhanced Testability**: All components mockable via interface contracts
- **Better Performance**: Compile-time dependency validation
- **Developer Experience**: Clean dependency access and easy testing