# VoiceService API Contract - FROZEN SPECIFICATION

## Overview

This document defines the **FROZEN PUBLIC API CONTRACT** for VoiceService during Phase 2 decomposition. All external code dependencies (especially VoiceSessionBloc) rely on this exact interface and **MUST** continue to work without modification after refactoring.

**⚠️ CRITICAL**: This API contract is immutable during decomposition. Any service boundaries must preserve these exact signatures, behaviors, and timing characteristics.

## API Contract Specification

### Core Service Class

```dart
class VoiceService {
  /// Factory constructor - SINGLETON PATTERN REQUIRED
  /// @param apiClient Required dependency for backend communication
  /// @throws Exception if apiClient is null
  factory VoiceService({required ApiClient apiClient});
  
  /// Cleanup all resources and close streams
  /// MUST be idempotent - safe to call multiple times
  void dispose();
}
```

## Public Properties & Getters

### 1. Backend Configuration

```dart
/// Backend URL getter
/// @returns String The configured backend URL
/// @throws LateInitializationError if accessed before initialize()
String get apiUrl;
```

### 2. Initialization State

```dart
/// Service initialization status
/// @returns bool true if initialize() has completed successfully
bool get isInitialized;
```

### 3. AI Speaking State

```dart
/// Current AI speaking state (mutable property)
/// Used by VoiceSessionBloc for audio coordination
/// @default false
bool isAiSpeaking;
```

## Stream APIs - CRITICAL FOR STATE COORDINATION

### 1. Recording State Stream

```dart
/// Recording state changes - DELEGATES TO RecordingManager
/// @returns Stream<RecordingState> Broadcasts recording state changes
/// @behavior Broadcast stream, multiple subscribers supported
/// @values RecordingState.{stopped, recording, processing, error}
Stream<RecordingState> get recordingState;
```

### 2. Audio Playback Stream

```dart
/// Audio playback state changes
/// @returns Stream<bool> true when audio is playing, false when stopped
/// @behavior Broadcast stream, real-time playback state
/// @timing Updates immediately on play/stop events
Stream<bool> get audioPlaybackStream;
```

### 3. TTS Speaking State Stream

```dart
/// TTS speaking state - CRITICAL FOR VoiceSessionBloc
/// @returns Stream<bool> true when TTS is actively speaking
/// @behavior Broadcast stream, coordinates with auto-listening
/// @timing Must update BEFORE audio playback starts/stops
/// @usage Prevents Maya from hearing herself speak
Stream<bool> get isTtsActuallySpeaking;
```

### 4. Auto-Listening Streams

```dart
/// Auto-listening state changes
/// @returns Stream<AutoListeningState> Current auto-listening state
/// @values AutoListeningState.{idle, aiSpeaking, listening, userSpeaking, processing, error}
Stream<AutoListeningState> get autoListeningStateStream;

/// Auto-listening mode enabled/disabled
/// @returns Stream<bool> true when auto-mode is enabled
Stream<bool> get autoListeningModeEnabledStream;
```

## Core Audio Operations

### 1. Service Initialization

```dart
/// Initialize VoiceService - MUST BE IDEMPOTENT
/// Sets up backend URL, audio permissions, service components
/// @throws Exception on initialization failure
/// @behavior Skip if already initialized
Future<void> initialize();

/// Conditional initialization - only if not already initialized
/// @behavior Calls initialize() only if isInitialized == false
Future<void> initializeOnlyIfNeeded();
```

### 2. Recording Operations

```dart
/// Start audio recording
/// @throws RecordingException if already recording
/// @behavior Updates recordingState stream to RecordingState.recording
Future<void> startRecording();

/// Stop audio recording
/// @returns String? Path to recorded audio file, null if no recording
/// @behavior Updates recordingState stream to RecordingState.stopped
Future<String?> stopRecording();

/// Process recorded audio file (isolate-based)
/// @param recordedFilePath Absolute path to audio file
/// @returns String Base64-encoded audio data
/// @throws Exception if file doesn't exist or processing fails
/// @threading Executes in background isolate via compute()
Future<String> processRecordedAudioFile(String recordedFilePath);
```

### 3. Audio Playback Operations

```dart
/// Play audio file
/// @param audioPath Local file path or URL to audio
/// @behavior Updates audioPlaybackStream and isTtsActuallySpeaking
/// @throws PlaybackException on playback failure
Future<void> playAudio(String audioPath);

/// Play streaming audio from URL
/// @param audioUrl HTTP/HTTPS URL to audio stream
/// @behavior WebSocket streaming for real-time audio
Future<void> playStreamingAudio(String audioUrl);

/// Play audio with completion callbacks
/// @param filePath Local path to audio file
/// @param onDone Optional callback when playback completes
/// @param onError Optional callback on playback error
/// @behavior Includes debounce mechanism to prevent duplicate calls
Future<void> playAudioWithCallbacks(
  String filePath, {
  void Function()? onDone,
  void Function(String error)? onError,
});

/// Stop current audio playback
/// @behavior Updates audioPlaybackStream to false
Future<void> stopAudio();

/// Check if audio is currently playing
/// @returns bool true if audio is actively playing
Future<bool> isPlaying();

/// Mute/unmute speaker output
/// @param muted true to mute, false to unmute
Future<void> setSpeakerMuted(bool muted);
```

## Auto-Listening & TTS State Management

### 1. Auto-Listening Mode Control

```dart
/// Enable auto-listening mode
/// @behavior Starts voice activity detection after TTS
Future<void> enableAutoMode();

/// Disable auto-listening mode
/// @behavior Stops voice activity detection completely
Future<void> disableAutoMode();

/// Enable auto-mode with explicit audio state
/// @param isAudioPlaying Current audio playback state
/// @behavior Considers audio state for proper timing
Future<void> enableAutoModeWithAudioState(bool isAudioPlaying);
```

### 2. TTS State Management - CRITICAL TIMING

```dart
/// Update TTS speaking state - CRITICAL FOR COORDINATION
/// @param isSpeaking true when TTS starts, false when stops
/// @behavior Immediately updates isTtsActuallySpeaking stream
/// @timing MUST be called BEFORE audio playback state changes
/// @usage Prevents auto-listening during TTS playback
void updateTTSSpeakingState(bool isSpeaking);

/// Reset TTS state to default
/// @behavior Sets TTS speaking state to false
/// @usage Called on errors or session resets
void resetTTSState();
```

### 3. Legacy VAD Methods - PRESERVED FOR COMPATIBILITY

```dart
/// Pause voice activity detection
/// @behavior No-op but preserved for API compatibility
/// @deprecated Use auto-listening coordinator directly
Future<void> pauseVAD();

/// Resume voice activity detection
/// @behavior No-op but preserved for API compatibility  
/// @deprecated Use auto-listening coordinator directly
Future<void> resumeVAD();
```

## Auto-Listening Orchestration API

```dart
// Initialize/reset lifecycle
await voiceService.initializeAutoListening();
voiceService.resetAutoListening(full: true, preserveAutoMode: false);

// Hook bloc callbacks and shared streams
voiceService.setAutoListeningRecordingCallback((path) => add(ProcessAudio(path)));
voiceService.setAutoListeningTtsActivityStream(isTtsActiveStream);

// State inspection + read-only mirrors
final AutoListeningState current = voiceService.autoListeningState;
final Stream<AutoListeningState> states = voiceService.autoListeningStateStream;
final Stream<bool> autoMode = voiceService.autoListeningModeEnabledStream;
final snapshot = voiceService.autoListeningSnapshotSource; // exposes streams only

// Explicit control
await voiceService.enableAutoMode();
await voiceService.disableAutoMode();
voiceService.triggerListening();
```

### Manager Component Access

```dart
/// Get audio player manager instance
/// @returns AudioPlayerManager for direct audio control
/// @usage Advanced audio operations not covered by public API
AudioPlayerManager getAudioPlayerManager();

/// Get recording manager instance  
/// @returns RecordingManager for direct recording control
/// @usage Advanced recording operations and state access
RecordingManager getRecordingManager();
```

## Data Types & Enums

### 1. Recording States

```dart
/// Recording state enumeration
/// DEFINED IN: base_voice_service.dart
enum RecordingState {
  stopped,    // No active recording
  recording,  // Currently recording audio
  processing, // Processing recorded audio  
  error       // Recording error occurred
}
```

### 2. Auto-Listening States

```dart
/// Auto-listening state enumeration
/// DEFINED IN: auto_listening_coordinator.dart
enum AutoListeningState {
  idle,         // Not listening, waiting
  aiSpeaking,   // AI is currently speaking
  listening,    // Actively listening for user input
  userSpeaking, // User is currently speaking
  processing,   // Processing user audio input
  error         // Auto-listening error occurred
}
```

### 3. Transcription Models

```dart
/// Transcription model options
/// DEFINED IN: voice_service.dart
enum TranscriptionModel {
  gpt4oMini,  // OpenAI GPT-4o Mini transcription
  deepgramAI, // Deepgram AI transcription
  assembly    // AssemblyAI transcription
}
```

## Exception Types

### 1. Playback Exceptions

```dart
/// Audio playback error exception
/// DEFINED IN: voice_service.dart
class PlaybackException implements Exception {
  final String message;
  
  PlaybackException(this.message);
  
  @override
  String toString() => 'PlaybackException: $message';
}
```

### 2. Recording Exceptions

```dart
/// Recording operation error exception
/// DEFINED IN: recording_manager.dart (used by VoiceService)
class NotRecordingException implements Exception {
  final String message;
  
  NotRecordingException([this.message = 'Recorder is not recording']);
  
  @override  
  String toString() => 'NotRecordingException: $message';
}
```

## Dependency Requirements

### 1. Constructor Dependencies

```dart
/// Required dependency injection
/// @param apiClient Backend API client for HTTP/WebSocket operations
/// @requirement Must be non-null and properly configured
/// @behavior Singleton pattern - same instance returned for subsequent calls
VoiceService({required ApiClient apiClient})
```

### 2. Platform Dependencies

- **Permission Handler**: Microphone permissions on mobile platforms
- **Just Audio**: Audio playback through platform audio APIs  
- **Record Package**: Audio recording through platform APIs
- **Audio Session**: Platform-specific audio session management
- **WebSocket Channel**: Real-time communication with backend

## Critical Usage Patterns - FROM VoiceSessionBloc

### 1. Stream Subscriptions - EXACT BEHAVIOR REQUIRED

```dart
// Recording state monitoring - USED IN VoiceSessionBloc
voiceService.recordingState.listen((RecordingState recState) {
  // State coordination logic depends on exact stream behavior
});

// TTS coordination - CRITICAL FOR MAYA SELF-DETECTION PREVENTION  
voiceService.isTtsActuallySpeaking.listen((bool isSpeaking) {
  // Auto-listening coordination depends on precise timing
});

// Auto-listening state management
voiceService.autoListeningStateStream.listen((AutoListeningState state) {
  // Complex state machine depends on exact state transitions
});
```

### 2. Auto-Listening Coordination - COMPLEX INTEGRATION

```dart
// Explicit auto-mode coordination via new helpers
await voiceService.disableAutoMode();
await voiceService.enableAutoMode();
voiceService.triggerListening();
voiceService.resetAutoListening(full: true, preserveAutoMode: false);
voiceService.setAutoListeningRecordingCallback(_handleRecordingComplete);
voiceService.setAutoListeningTtsActivityStream(isTtsActiveStream);
```

### 3. Audio Lifecycle Management - PRECISE TIMING

```dart
// Audio playback with TTS state coordination
await voiceService.stopAudio();                    // Stop current audio
voiceService.updateTTSSpeakingState(true);         // Signal TTS start
await voiceService.playAudio(audioPath);           // Play TTS audio
// TTS completion detected via stream
voiceService.updateTTSSpeakingState(false);        // Signal TTS end
voiceService.resetTTSState();                       // Reset TTS state
```

### 4. Recording Workflow - EXACT SEQUENCE

```dart
// Recording workflow used by VoiceSessionBloc
final recordedPath = await voiceService.stopRecording();
if (recordedPath != null) {
  final base64Audio = await voiceService.processRecordedAudioFile(recordedPath);
  // Process base64Audio...
}
```

## API Constraints & Requirements

### 1. **Singleton Pattern** - IMMUTABLE
- Factory constructor MUST return same instance for multiple calls
- Internal state MUST be preserved across all references
- Disposal MUST affect all references globally

### 2. **Stream Continuity** - EXACT BEHAVIOR  
- All streams MUST maintain exact same types and behaviors
- Broadcast streams MUST support multiple subscribers
- Stream timing MUST remain identical for coordination logic

### 3. **Exception Handling** - EXACT TYPES
- MUST throw same exception types for identical error conditions  
- Exception messages MAY change but types MUST remain consistent
- Error propagation behavior MUST remain identical

### 4. **Timing Dependencies** - CRITICAL CONSTRAINTS
- TTS state updates MUST occur before audio state changes
- Stream emissions MUST maintain exact timing relationships
- Auto-listening coordination MUST preserve precise state machine timing

### 5. **Component Access** - DIRECT REFERENCES
- Direct access to internal components MUST be preserved
- Component methods called directly MUST remain available
- Complex operations requiring direct control MUST continue working

### 6. **Initialization Patterns** - IDEMPOTENT BEHAVIOR
- Multiple initialize() calls MUST be safe (no-op if already initialized)
- Conditional initialization MUST work exactly as before
- Service dependencies MUST initialize in correct order

### 7. **Resource Management** - PROPER CLEANUP
- dispose() MUST clean up all streams, timers, and platform resources
- MUST be idempotent - safe to call multiple times
- ALL subscribers MUST be notified of stream closures

## Testing Requirements for API Contract

### 1. **Interface Compatibility Tests**
```dart
// Verify exact method signatures
test('API signatures remain identical', () {
  final service = VoiceService(apiClient: mockApiClient);
  
  // Method existence and signatures
  expect(service.initialize, isA<Future<void> Function()>());
  expect(service.startRecording, isA<Future<void> Function()>());
  expect(service.recordingState, isA<Stream<RecordingState>>());
});
```

### 2. **Behavioral Compatibility Tests**  
```dart
// Verify stream behavior
test('Streams maintain exact behavior', () async {
  final service = VoiceService(apiClient: mockApiClient);
  
  // Multiple subscription support
  final sub1 = service.recordingState.listen((_) {});
  final sub2 = service.recordingState.listen((_) {});
  
  expect(() => sub1.cancel(), returnsNormally);
  expect(() => sub2.cancel(), returnsNormally);
});
```

### 3. **Exception Compatibility Tests**
```dart
// Verify exception types
test('Exception types remain identical', () {
  expect(() => throw PlaybackException('test'), 
         throwsA(isA<PlaybackException>()));
  expect(() => throw NotRecordingException(),
         throwsA(isA<NotRecordingException>()));
});
```

## Refactoring Guidelines

### ✅ **ALLOWED CHANGES**
- Internal implementation details
- Service composition and delegation
- Performance optimizations  
- Error handling improvements (same exception types)
- Additional private methods and properties
- Internal threading and concurrency patterns

### ❌ **FORBIDDEN CHANGES**
- Public method signatures or return types
- Stream types or broadcasting behavior
- Exception types or error conditions
- Timing characteristics of stream emissions
- Component access patterns
- Initialization behavior or requirements

### ⚠️ **REQUIRES VALIDATION**
- Stream emission timing changes
- Error propagation path modifications
- Resource cleanup order changes
- Platform dependency modifications

---

**🔒 FROZEN API STATUS**: This contract is IMMUTABLE during Phase 2 decomposition

**📋 VALIDATION**: All changes MUST pass existing VoiceSessionBloc integration tests

**📅 Version**: Phase 2.0.3 - API Contract Definition Complete

**➡️ Next Phase**: Phase 2.1 - Service decomposition with API contract preservation
