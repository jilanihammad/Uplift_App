# AI Therapist App - Major Refactoring Plan

## Overview
This document outlines a comprehensive refactoring plan for the AI Therapist Flutter application. The current codebase has several architectural issues that impact maintainability, testability, and scalability. This plan prioritizes the most critical issues and provides a structured approach to resolving them.

## Current Architecture Issues

### 1. Service Locator Anti-Pattern
- **Impact**: Used 214 times across the codebase
- **Problem**: Creates tight coupling, makes testing difficult, hides dependencies
- **Affects**: Entire application architecture

### 2. Monolithic Service Classes
- **Impact**: Large files with multiple responsibilities
- **Problem**: Violates Single Responsibility Principle, hard to maintain and test
- **Affects**: Core functionality and performance

### 3. Mixed Concerns in UI Components
- **Impact**: Business logic mixed with presentation logic
- **Problem**: Reduces reusability, makes testing complex
- **Affects**: All major screens

### 4. Complex State Management
- **Impact**: Overly complex BLoCs handling multiple concerns
- **Problem**: Hard to debug, maintain, and extend
- **Affects**: Real-time features and user interactions

---

## Critical Files Requiring Major Refactoring

### 🔴 **Priority 1: Critical (Must Fix)**

#### 1. `lib/di/service_locator.dart` (488 lines)
**Current Issues:**
- Service locator anti-pattern used throughout application
- Complex dependency registration order
- Circular dependency issues
- Hard to test and mock dependencies
- Singleton dependencies creating global state

**Refactoring Plan:**
```dart
// Current problematic pattern
final authService = serviceLocator<AuthService>();

// Target pattern with dependency injection
class ChatScreen extends StatelessWidget {
  final AuthService authService;
  final VoiceService voiceService;
  
  const ChatScreen({
    required this.authService,
    required this.voiceService,
  });
}
```

**Implementation Steps:**
1. **Phase 1**: Create dependency injection interfaces
   ```dart
   abstract class IAuthService { ... }
   abstract class IVoiceService { ... }
   abstract class ITherapyService { ... }
   ```

2. **Phase 2**: Create dependency modules
   ```dart
   class ServiceModule {
     static void registerServices(GetIt locator) {
       locator.registerLazySingleton<IAuthService>(() => AuthService());
       locator.registerFactory<IVoiceService>(() => VoiceService());
     }
   }
   ```

3. **Phase 3**: Gradually replace service locator usage
   - Start with leaf components (utilities, models)
   - Move to services layer
   - Finally update UI components

4. **Phase 4**: Remove global service locator

**Estimated Effort:** 4-5 weeks
**Impact:** Entire codebase architecture improvement

---

#### 2. `lib/services/voice_service.dart` (1,419 lines)
**Current Issues:**
- Massive monolithic class with 7+ responsibilities
- 33 import statements indicating tight coupling
- Complex singleton pattern with nested initialization
- Mixed concerns: recording, playback, TTS, WebSocket, file management
- Hard to test due to external dependencies

**Current Structure:**
```dart
class VoiceService {
  // Recording functionality
  // Playback functionality  
  // TTS functionality
  // WebSocket management
  // File management
  // Auto-listening coordination
  // Session management
}
```

**Target Architecture:**
```dart
// Split into focused services
abstract class IAudioRecordingService {
  Future<void> startRecording();
  Future<String> stopRecording();
  Stream<double> get audioLevelStream;
}

abstract class ITTSService {
  Future<String> generateSpeech(String text, {String voice});
  Future<void> playAudio(String audioPath);
}

abstract class IWebSocketAudioManager {
  Future<void> connectToBackend();
  Future<void> streamAudio(Uint8List audioData);
}

abstract class IAudioFileManager {
  Future<String> saveAudioFile(Uint8List data);
  Future<void> cleanupTempFiles();
}

class VoiceSessionCoordinator {
  final IAudioRecordingService _recordingService;
  final ITTSService _ttsService;
  final IWebSocketAudioManager _wsManager;
  final IAudioFileManager _fileManager;
  
  // Orchestrates voice session workflow
}
```

**Implementation Steps:**
1. **Week 1**: Extract recording service
2. **Week 2**: Extract TTS service
3. **Week 3**: Extract WebSocket manager and file manager
4. **Week 4**: Create coordinator and update dependencies

**Testing Strategy:**
- Create mock implementations for each interface
- Unit test each service independently
- Integration tests for coordinator

**Estimated Effort:** 3-4 weeks

---

#### 3. `lib/screens/chat_screen.dart` (1,092 lines)
**Current Issues:**
- Massive UI file mixing presentation and business logic
- Multiple service dependencies injected directly
- Complex state management with controllers and subscriptions
- Hard to test due to tight coupling

**Current Structure:**
```dart
class ChatScreen extends StatefulWidget {
  // UI rendering
  // Business logic
  // State management
  // Service coordination
  // Session management
  // Audio controls
}
```

**Target Architecture:**
```dart
// Extract business logic to BLoC
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ITherapyService therapyService;
  final IVoiceService voiceService;
  final ISessionService sessionService;
}

// Split UI into focused widgets
class ChatScreen extends StatelessWidget {
  Widget build(context) => BlocProvider(
    create: (_) => ChatBloc(),
    child: Column([
      ChatHeaderSection(),
      ChatMessageListSection(),
      ChatInputSection(),
      VoiceControlsSection(),
    ]),
  );
}

class ChatMessageListSection extends StatelessWidget { ... }
class VoiceControlsSection extends StatelessWidget { ... }
class ChatInputSection extends StatelessWidget { ... }
```

**Implementation Steps:**
1. **Week 1**: Extract ChatBloc with events and states
2. **Week 2**: Create reusable widget components
3. **Week 3**: Implement dependency injection and testing

**Estimated Effort:** 2-3 weeks

---

#### 4. `lib/services/auto_listening_coordinator.dart` (940 lines)
**Current Issues:**
- Complex state machine with multiple timers and guards
- Tight coupling between VAD management and recording coordination
- Multiple responsibilities mixed together
- Complex debouncing and timeout logic

**Current Structure:**
```dart
class AutoListeningCoordinator {
  // VAD management
  // Recording coordination
  // State machine logic
  // Timer management
  // Configuration management
}
```

**Target Architecture:**
```dart
// Use proper state machine pattern
enum AutoListeningState {
  idle, listening, recording, processing, speaking
}

abstract class IVoiceActivityDetector {
  Stream<bool> get voiceDetectedStream;
  void setThreshold(double threshold);
}

abstract class IRecordingCoordinator {
  Future<void> startRecording();
  Future<void> stopRecording();
}

class AutoListeningStateMachine extends Bloc<AutoListeningEvent, AutoListeningState> {
  final IVoiceActivityDetector vadDetector;
  final IRecordingCoordinator recordingCoordinator;
  final TimerManager timerManager;
}

class TimerManager {
  void startTimeout(Duration duration, VoidCallback onTimeout);
  void cancelAllTimers();
}
```

**Implementation Steps:**
1. **Week 1**: Extract VAD detector interface and implementation
2. **Week 2**: Create state machine with proper events/states
3. **Week 3**: Extract timer management and integrate components

**Estimated Effort:** 2-3 weeks

---

#### 5. `lib/blocs/voice_session_bloc.dart` (678 lines)
**Current Issues:**
- Overly complex BLoC handling multiple concerns
- Multiple stream subscriptions creating memory leaks
- Event handlers with side effects
- Using `dynamic` types indicating poor type safety

**Target Architecture:**
```dart
// Split into focused BLoCs
class AudioSessionBloc extends Bloc<AudioSessionEvent, AudioSessionState> {
  // Handles audio recording/playback state only
}

class MessageProcessingBloc extends Bloc<MessageEvent, MessageState> {
  // Handles message transcription and AI response
}

class SessionTimerBloc extends Bloc<TimerEvent, TimerState> {
  // Handles session timing and duration
}

class VoiceSessionCoordinator {
  final AudioSessionBloc audioBloc;
  final MessageProcessingBloc messageBloc;
  final SessionTimerBloc timerBloc;
  
  // Coordinates between BLoCs using event-driven communication
}
```

**Implementation Steps:**
1. **Week 1**: Split into separate BLoCs with proper types
2. **Week 2**: Implement event-driven communication between BLoCs
3. **Week 3**: Update UI components and add testing

**Estimated Effort:** 2-3 weeks

---

### 🟡 **Priority 2: High (Should Fix)**

#### 6. `lib/main.dart` (870 lines)
**Current Issues:**
- 68 import statements indicating architectural problems
- Complex initialization logic mixed with app setup
- Firebase initialization scattered throughout
- Multiple global variables

**Refactoring Plan:**
```dart
// Extract initialization logic
class AppInitializer {
  static Future<void> initialize() async {
    await FirebaseInitializer.initialize();
    await DatabaseInitializer.initialize();
    await ServiceInitializer.initialize();
  }
}

class FirebaseInitializer {
  static Future<void> initialize() async { ... }
}

// Clean main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInitializer.initialize();
  runApp(MyApp());
}
```

**Estimated Effort:** 1-2 weeks

---

#### 7. `lib/screens/home_screen.dart` (936 lines)
**Current Issues:**
- Large UI file with business logic mixed in
- Multiple service dependencies
- Heavy initializations in initState

**Refactoring Plan:**
```dart
// Extract business logic
class HomeBloc extends Bloc<HomeEvent, HomeState> { ... }

// Split into widget components
class HomeScreen extends StatelessWidget {
  Widget build(context) => BlocProvider(
    create: (_) => HomeBloc(),
    child: Column([
      UserProgressSection(),
      QuickActionsSection(),
      RecentActivitySection(),
      NavigationSection(),
    ]),
  );
}
```

**Estimated Effort:** 1-2 weeks

---

#### 8. `lib/data/datasources/local/app_database.dart` (726 lines)
**Current Issues:**
- Complex singleton implementation
- Multiple database concerns in single file
- Platform-specific logic mixed with core logic

**Refactoring Plan:**
```dart
class DatabaseManager {
  final DatabaseFactory factory;
  final MigrationManager migrationManager;
}

class MigrationManager {
  Future<void> runMigrations(Database db, int version);
}

class DatabaseFactory {
  static Database createDatabase(String path);
}
```

**Estimated Effort:** 1-2 weeks

---

#### 9. `lib/services/auth_service.dart` (719 lines)
**Current Issues:**
- Multiple authentication methods in single class
- Complex dependency management
- Mixing auth logic with user management

**Refactoring Plan:**
```dart
abstract class IAuthenticationService {
  Future<User?> signInWithEmail(String email, String password);
  Future<void> signOut();
}

abstract class IUserManagementService {
  Future<void> updateUserProfile(UserProfile profile);
  Future<UserProfile?> getCurrentUserProfile();
}

abstract class ITokenManager {
  Future<String?> getAccessToken();
  Future<void> refreshToken();
}
```

**Estimated Effort:** 1-2 weeks

---

## Implementation Timeline

### Phase 1: Foundation (8-10 weeks)
**Goal**: Fix critical architectural issues

1. **Service Locator Migration** (4-5 weeks)
   - Week 1-2: Create interfaces and dependency modules
   - Week 3-4: Replace service locator in services layer
   - Week 5: Update UI components and remove global service locator

2. **Voice Service Refactoring** (3-4 weeks)
   - Week 1: Extract recording service
   - Week 2: Extract TTS service  
   - Week 3: Extract WebSocket and file managers
   - Week 4: Create coordinator and testing

3. **Voice Session BLoC Refactoring** (2-3 weeks)
   - Week 1: Split into focused BLoCs
   - Week 2: Implement event-driven communication
   - Week 3: Update UI and testing

### Phase 2: UI and State Management (6-8 weeks)
**Goal**: Improve UI architecture and maintainability

1. **Chat Screen Refactoring** (2-3 weeks)
2. **Auto Listening Coordinator** (2-3 weeks)
3. **Main.dart Initialization** (1-2 weeks)
4. **Database Layer** (1-2 weeks)

### Phase 3: Cleanup and Optimization (4-6 weeks)
**Goal**: Address remaining issues and technical debt

1. **Auth Service** (1-2 weeks)
2. **Home Screen** (1-2 weeks)
3. **Code Duplication Cleanup** (2-3 weeks)

**Total Estimated Effort:** 18-24 weeks

---

## Testing Strategy

### Unit Testing
- Create mock implementations for all interfaces
- Test each service independently
- Achieve >80% code coverage for refactored components

### Integration Testing
- Test service interactions through coordinators
- End-to-end testing for critical user flows
- Performance testing for audio components

### Refactoring Testing
- Ensure existing functionality remains unchanged
- Regression testing for each refactored component
- User acceptance testing for critical features

---

## Benefits of Refactoring

### Immediate Benefits
- **Improved Maintainability**: Smaller, focused classes
- **Better Testability**: Dependency injection enables mocking
- **Reduced Coupling**: Clear interfaces between components
- **Enhanced Performance**: Optimized service lifecycle management

### Long-term Benefits
- **Scalability**: Easier to add new features
- **Code Reusability**: Focused components can be reused
- **Team Productivity**: Easier onboarding and collaboration
- **Bug Reduction**: Better separation of concerns reduces bugs

### Business Benefits
- **Faster Feature Development**: Well-structured code enables rapid development
- **Reduced Maintenance Costs**: Less technical debt means lower maintenance overhead
- **Improved App Quality**: Better architecture leads to more stable app
- **Easier Third-party Integrations**: Clean interfaces make integration simpler

---

## Risk Mitigation

### Technical Risks
- **Breaking Changes**: Implement feature flags and gradual rollout
- **Performance Regression**: Continuous performance monitoring
- **New Bugs**: Comprehensive testing strategy

### Project Risks
- **Timeline Delays**: Break work into smaller, independent chunks
- **Resource Constraints**: Prioritize most critical issues first
- **Scope Creep**: Stick to defined refactoring goals

### Mitigation Strategies
- **Incremental Approach**: Refactor one component at a time
- **Backward Compatibility**: Maintain existing APIs during transition
- **Rollback Plan**: Keep ability to revert changes if needed
- **Monitoring**: Add telemetry to track refactoring impact

---

## Success Metrics

### Code Quality Metrics
- **Cyclomatic Complexity**: Reduce average complexity by 50%
- **Class Size**: No classes >500 lines
- **Test Coverage**: Achieve >80% coverage for refactored components
- **Code Duplication**: Reduce duplicate code by 60%

### Performance Metrics
- **App Startup Time**: Maintain or improve current performance
- **Memory Usage**: Reduce memory footprint by 20%
- **Voice Processing Latency**: Maintain sub-200ms response time

### Development Metrics
- **Build Time**: Maintain or improve current build performance
- **Developer Productivity**: Measure feature development velocity
- **Bug Rate**: Reduce critical bugs by 40%

---

## Next Steps

1. **Review and Approve**: Review this plan with the development team
2. **Prioritize**: Confirm prioritization of refactoring tasks
3. **Resource Planning**: Allocate development resources
4. **Start Phase 1**: Begin with service locator migration
5. **Set up Monitoring**: Implement metrics tracking
6. **Regular Reviews**: Weekly progress reviews and adjustments

---

## Notes

- This refactoring plan is designed to be executed incrementally
- Each phase can be done independently to minimize risk
- Priority should be given to components that are actively being developed
- Consider creating feature branches for major refactoring work
- Regular code reviews are essential during the refactoring process

**Last Updated:** 2025-01-22
**Document Version:** 1.0