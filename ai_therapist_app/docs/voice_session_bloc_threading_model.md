# VoiceSessionBloc Threading Model Documentation

## Phase 0.5.2: Threading and Platform Channel Analysis

### Executive Summary

This document captures the complete threading model and platform channel interactions within VoiceSessionBloc and its dependencies. This documentation is MANDATORY before any refactoring to prevent platform channel violations, race conditions, and isolate boundary issues.

### Table of Contents
1. [Threading Architecture Overview](#threading-architecture-overview)
2. [Platform Channel Boundaries](#platform-channel-boundaries)
3. [Asynchronous Operation Flows](#asynchronous-operation-flows)
4. [Stream Processing Model](#stream-processing-model)
5. [Critical Race Conditions](#critical-race-conditions)
6. [Isolate Boundaries](#isolate-boundaries)
7. [Thread Safety Requirements](#thread-safety-requirements)
8. [Refactoring Constraints](#refactoring-constraints)

---

## 1. Threading Architecture Overview

### Main UI Thread Operations
VoiceSessionBloc operates primarily on Flutter's main UI thread with the following characteristics:

```
Main Thread Execution:
├── BLoC Event Processing (synchronous event handlers)
├── State Emissions
├── Stream Subscriptions (3 active)
│   ├── recordingState (from VoiceService)
│   ├── isPlayingStream (from AudioPlayerManager)
│   └── isTtsActuallySpeaking (from VoiceService)
└── UI State Updates
```

### Asynchronous Operations
The following operations execute asynchronously but return to main thread:

1. **Service Initialization** (`_onInitializeService`)
   - `IVoiceService.initialize()` - Platform channel call
   - `ITherapyService.init()` - Network initialization

2. **Audio Control** (`_onStopAudio`, `_onPlayAudio`)
   - Platform channel calls to native audio APIs
   - Must complete on main thread

3. **Recording Control** (`_onSwitchMode`, `_onEndSession`)
   - Native audio recording APIs
   - File system operations

4. **Network Operations** (`_onProcessAudio`, `_onProcessTextMessage`)
   - WebSocket communication
   - HTTP API calls
   - TTS streaming

---

## 2. Platform Channel Boundaries

### Critical Platform Channels Used

#### 2.1 Audio Recording (via Record package)
```dart
Platform Channel: "com.llfbandit.record/messages"
Thread: Main UI Thread → Platform Thread → Main UI Thread
Operations:
- startRecording() - MUST be on main thread
- stopRecording() - MUST be on main thread  
- recordingState stream - Crosses thread boundary
```

#### 2.2 Audio Playback (via just_audio)
```dart
Platform Channel: "com.ryanheise.just_audio.methods"
Thread: Main UI Thread → Platform Thread → Main UI Thread
Operations:
- play() - Can be called from any thread
- stop() - Can be called from any thread
- playerStateStream - Crosses thread boundary
```

#### 2.3 Text-to-Speech (via flutter_tts)
```dart
Platform Channel: "flutter_tts"
Thread: Main UI Thread only
Operations:
- speak() - MUST be on main thread
- stop() - MUST be on main thread
- setCompletionHandler - Callback on main thread
```

#### 2.4 Permissions (via permission_handler)
```dart
Platform Channel: "flutter.baseflow.com/permissions/methods"
Thread: Main UI Thread only
Operations:
- request() - MUST be on main thread
- status check - MUST be on main thread
```

---

## 3. Asynchronous Operation Flows

### 3.1 Audio Processing Flow (ProcessAudio event)
```
1. Main Thread: ProcessAudio event received
2. Main Thread: emit(isProcessingAudio: true)
3. Async Operation: processRecordedAudioFile()
   └── HTTP call to transcription service
4. Main Thread: Add user message to state
5. Async Operation: processUserMessageWithStreamingAudio()
   ├── WebSocket connection established
   ├── Streaming TTS data received
   └── Audio playback initiated (platform channel)
6. Main Thread: Callbacks (onTTSPlaybackComplete, onTTSError)
7. Main Thread: emit(isProcessingAudio: false)
```

### 3.2 Voice Mode Switch Flow
```
1. Main Thread: SwitchMode event
2. Async: stopAudio() → Platform channel
3. Main Thread: resetTTSState()
4. Async: Future.delayed(200ms) - CRITICAL TIMING
5. Async: enableAutoMode() → Multiple platform channels
6. Main Thread: Conditionally trigger listening
```

### 3.3 Auto-Listening Enable Flow
```
1. Main Thread: EnableAutoMode event
2. Skip if already enabled (thread-safe check)
3. Async: stopAudio() → Platform channel
4. Main Thread: resetTTSState()  
5. Async: Future.delayed(125ms) - CRITICAL BUFFER
6. Async: enableAutoMode() → Platform channels
7. Main Thread: triggerListening() on coordinator
```

---

## 4. Stream Processing Model

### 4.1 Recording State Stream
```dart
Source: VoiceService.recordingState
Type: Stream<RecordingState>
Thread Model:
├── Native platform emits state changes
├── Stream controller on main thread
├── VoiceSessionBloc listens and maps to SetRecordingState
└── State update on main thread
```

### 4.2 TTS State Stream
```dart
Source: VoiceService.isTtsActuallySpeaking  
Type: Stream<bool>
Thread Model:
├── TTS completion callbacks from platform
├── Stream controller on main thread
├── VoiceSessionBloc listens for auto-listening coordination
└── Complex state machine for voice mode transitions
```

### 4.3 Audio Playback Stream
```dart
Source: AudioPlayerManager.isPlayingStream
Type: Stream<bool>
Thread Model:
├── Audio player state changes from platform
├── Stream controller on main thread
├── Currently monitored but not actively used
└── Future: Could coordinate with TTS state
```

---

## 5. Critical Race Conditions

### 5.1 Maya Self-Detection Issue (RESOLVED)
**Problem**: TTS playback detected by VAD as user speech
**Solution**: 125ms buffer delays before enabling auto-listening
**Thread Safety**: Delays execute asynchronously but state checks on main thread

### 5.2 Recording State Transitions
**Risk**: Multiple rapid recording start/stop calls
**Mitigation**: State checks before operations
**Thread Model**: All checks and operations on main thread

### 5.3 Service Initialization Race
**Risk**: Services used before initialization complete
**Current**: No initialization enforcement
**Required**: Initialization state machine

---

## 6. Isolate Boundaries

### 6.1 Current Isolate Usage
- **None in VoiceSessionBloc directly**
- **VoiceService** uses compute() for audio file processing
- **No custom isolates spawned**

### 6.2 Isolate Constraints for Refactoring
1. Platform channels CANNOT be accessed from isolates
2. UI updates must return to main isolate
3. Service instances cannot cross isolate boundaries
4. Stream controllers must remain on main isolate

---

## 7. Thread Safety Requirements

### 7.1 State Mutations
- ✅ All state updates via emit() on main thread
- ✅ No direct state mutations
- ✅ Immutable state objects

### 7.2 Service Calls
- ⚠️ Most service methods assumed main thread
- ⚠️ No explicit thread verification
- ⚠️ Platform channels require main thread

### 7.3 Stream Subscriptions
- ✅ Subscriptions created in constructor
- ✅ Properly cancelled in close()
- ⚠️ No null-safety for subscription cancellation

---

## 8. Refactoring Constraints

### 8.1 MUST Maintain Thread Safety
1. **Platform Channels**: Keep all platform channel calls on main thread
2. **State Updates**: Only emit from main thread
3. **Stream Processing**: Maintain existing subscription model

### 8.2 MUST Preserve Timing
1. **125ms VAD Buffer**: Critical for Maya self-detection
2. **200ms Mode Switch Delay**: Required for audio cleanup
3. **Stream Order**: Recording → Processing → Playing sequence

### 8.3 MUST Handle Async Coordination
1. **Service Initialization**: Must complete before use
2. **Audio State Machine**: Must prevent invalid transitions
3. **Error Propagation**: Must return to main thread

### 8.4 Decomposition Thread Model

When splitting VoiceSessionBloc into managers:

```
SessionStateManager:
├── Pure Dart, no platform channels
├── Synchronous state transitions
└── Safe to refactor freely

TimerManager:
├── Dart Timer class (main thread)
├── No platform channels
└── Must emit on main thread

MessageCoordinator:
├── Async network operations
├── Must handle errors on main thread
└── WebSocket management considerations

AudioCoordinator (if created):
├── CRITICAL: Multiple platform channels
├── MUST maintain thread safety
├── MUST preserve timing delays
└── Complex state machine preservation
```

---

## Critical Findings for Refactoring

### ⚠️ High-Risk Areas
1. **Auto-listening coordination** - Complex timing and state dependencies
2. **Platform channel calls** - Must remain on main thread
3. **TTS state management** - Tightly coupled to voice mode logic
4. **Stream subscription lifecycle** - Must properly transfer to new managers

### ✅ Safe Refactoring Targets
1. **Message management** - Pure Dart operations
2. **Session state** - No platform dependencies
3. **Timer management** - Standard Dart timers
4. **Mood/duration selection** - UI state only

### 🔒 Mandatory Preservation
1. **125ms and 200ms timing delays**
2. **Stream subscription order and lifecycle**
3. **Main thread execution for platform channels**
4. **Error propagation to main thread**

---

## Appendix: Platform Channel Reference

### Methods Requiring Main Thread
```dart
// VoiceService / IVoiceService
- initialize()
- stopRecording() 
- startRecording()
- stopAudio()
- enableAutoMode()
- disableAutoMode()
- setSpeakerMuted()
- playAudio()
- resetTTSState()
- updateTTSSpeakingState()

// TTSService  
- speak()
- stop()

// Permission checks
- Permission.microphone.request()
- Permission.microphone.status
```

### Safe for Any Thread
```dart
// Pure Dart operations
- State calculations
- Message list management
- History building
- Timer operations
- Stream controller operations (if created on main thread)
```

---

**Document Version**: 1.0  
**Created**: Phase 0.5.2 - Threading Model Documentation  
**Purpose**: Safety documentation before VoiceSessionBloc refactoring  
**Status**: COMPLETE ✅