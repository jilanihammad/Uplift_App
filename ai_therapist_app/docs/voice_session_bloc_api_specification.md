# VoiceSessionBloc API Specification

## Phase 0.5.3: Complete API Contract Documentation

### Overview

This document provides the complete API specification for VoiceSessionBloc, defining all public interfaces, behaviors, and contracts that MUST be preserved during the Phase 1 refactoring. This specification serves as the definitive reference for maintaining backward compatibility.

---

## 1. Constructor Contract

### Current Constructor Signature
```dart
VoiceSessionBloc({
  required VoiceService voiceService,
  required VADManager vadManager,
  ITherapyService? therapyService,
  IVoiceService? interfaceVoiceService,
  IProgressService? progressService,
  INavigationService? navigationService,
})
```

### Required Parameters
- `voiceService`: Legacy VoiceService instance (being phased out)
- `vadManager`: Voice Activity Detection manager

### Optional Parameters (maintain for compatibility)
- `therapyService`: AI therapy service interface
- `interfaceVoiceService`: New voice service interface (Phase 6 migration)
- `progressService`: Progress tracking interface
- `navigationService`: Navigation interface

### Constructor Behavior
1. Initializes with `VoiceSessionState.initial()`
2. Registers 30+ event handlers
3. Subscribes to 3 streams:
   - `voiceService.recordingState`
   - `voiceService.getAudioPlayerManager().isPlayingStream`
   - `voiceService.isTtsActuallySpeaking`

---

## 2. Event Processing Contract

### Complete Event List (30+ events)

#### Session Lifecycle (6 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `StartSession` | None | Resets state to initial values |
| `SessionStarted` | `String? sessionId` | Sets session ID and loading status |
| `EndSession` | None | Cleanup audio, stop recording, clear state |
| `EndSessionRequested` | None | Sets ended status, mutes speaker |
| `SetInitializing` | `bool isInitializing` | Updates loading status |
| `SetEndingSession` | `bool isEndingSession` | Updates ended status |

#### Audio Control (9 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `StartListening` | None | Sets isListening=true |
| `StopListening` | None | Sets isListening=false |
| `SwitchMode` | `bool isVoiceMode` | Complex mode transition with delays |
| `ProcessAudio` | `String audioPath` | Transcribe and process audio file |
| `StopAudio` | None | Calls IVoiceService.stopAudio() |
| `PlayAudio` | `String audioPath` | Plays audio file |
| `EnableAutoMode` | None | Enables VAD with 125ms buffer |
| `DisableAutoMode` | None | Disables VAD via coordinator |
| `SetRecordingState` | `bool isRecording` | Updates recording state |

#### UI State (8 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `SelectMood` | `Mood mood` | Sets selected mood |
| `MoodSelected` | `Mood mood` | Sets mood, generates welcome message |
| `ChangeDuration` | `int minutes` | Sets duration in minutes |
| `DurationSelected` | `Duration duration` | Sets duration object |
| `ShowMoodSelector` | `bool show` | Toggle mood UI |
| `ShowDurationSelector` | `bool show` | Toggle duration UI |
| `ToggleMicMute` | None | Toggles mic enabled state |
| `SetSpeakerMuted` | `bool isMuted` | Mutes/unmutes speaker |

#### Message Processing (4 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `ProcessTextMessage` | `String text` | Process user text input |
| `TextMessageSent` | `String message` | Alias for ProcessTextMessage |
| `AddMessage` | `TherapyMessage message` | Adds with sequence number |
| `UpdateAmplitude` | `double amplitude` | Currently no-op |

#### State Updates (5 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `SetProcessing` | `bool isProcessing` | Updates processing state |
| `HandleError` | `String error` | Sets error message |
| `AudioPlaybackStateChanged` | `bool isPlaying` | Internal stream event |
| `TtsStateChanged` | `bool isSpeaking` | Updates AI speaking state |
| `UpdateSessionTimer` | None | Currently no-op |

#### TTS Events (2 events)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `PlayWelcomeMessage` | `String welcomeMessage` | TTS with state coordination |
| `WelcomeMessageCompleted` | None | Marks greeting played |

#### Service Control (1 event)
| Event | Parameters | Behavior |
|-------|------------|----------|
| `InitializeService` | None | Initialize voice and therapy services |

---

## 3. State Contract

### State Properties

#### Core Properties
```dart
VoiceSessionStatus status         // Enum with 11 values
List<TherapyMessage> messages     // Conversation history
String? errorMessage              // Current error if any
String? currentSessionId          // Active session ID
int currentMessageSequence        // Message ordering
```

#### Audio State
```dart
bool isListening                  // Mic actively listening
bool isRecording                  // Recording to file
bool isProcessingAudio           // STT/AI processing
bool isAiSpeaking                // TTS active
bool isAutoListeningEnabled      // VAD enabled
bool isMicEnabled                // Mic permission
bool speakerMuted                // Speaker muted
```

#### UI State
```dart
bool isVoiceMode                 // Voice vs chat mode
bool showMoodSelector            // Mood UI visible
bool showDurationSelector        // Duration UI visible
bool showMicButton               // Mic button visible
bool showSendButton              // Send button visible
bool isInitialGreetingPlayed    // Welcome TTS done
```

#### Configuration
```dart
Mood? selectedMood               // User's mood
Duration? selectedDuration       // Session duration
String? currentSystemPrompt      // AI system prompt
String? activeTherapyStyleName   // Therapy style
TherapistStyle? therapistStyle   // Full style object
```

### Computed Properties (Getters)
```dart
bool canSend                     => !isProcessingAudio && !isVoiceMode
bool isInitializing              => status == VoiceSessionStatus.loading
int sessionDurationMinutes       => selectedDuration?.inMinutes ?? 0
int sessionTimerSeconds          => 0 // TODO placeholder
bool isEndingSession             => status == VoiceSessionStatus.ended
double amplitude                 => 0.0 // TODO placeholder
bool isProcessing                => isProcessingAudio
bool isSpeakerMuted              => speakerMuted
bool isVADActive                 => isAutoListeningEnabled
bool isListeningForVoice         => isVADActive && !isRecording && !isProcessing && !isAiSpeaking
```

---

## 4. Behavioral Contracts

### 4.1 Welcome Message Generation
- Generates mood-specific messages from predefined sets
- 5 message variants per mood (happy, sad, anxious, angry, neutral, stressed)
- Adds as first message with sequence=1
- In voice mode: triggers TTS playback via PlayWelcomeMessage event

### 4.2 Message Sequencing
- Each message gets incrementing sequence number
- User messages followed by AI messages
- Sequence starts at 0, increments per message
- Preserved in message history

### 4.3 Mode Switching Behavior

#### To Voice Mode:
1. Stop any playing audio
2. Reset TTS state and call `resetAutoListening(full: true)`
3. Wait 200 ms (audio cleanup)
4. Call `initializeAutoListening()` and re-register callbacks/streams
5. Enable auto-mode via `voiceService.enableAutoMode()`
6. Trigger listening when welcome/audio guards allow

#### To Chat Mode:
1. Disable auto-mode
2. Stop recording (handle NotRecordingException)
3. Process any pending audio
4. Update UI state

### 4.4 Auto-Listening Coordination
- 125 ms buffer after TTS stops (prevents self-detection)
- Triggered after welcome message in voice mode
- Skipped if already enabled
- Uses IVoiceService auto-listening APIs (`initializeAutoListening`, `resetAutoListening`, `setAutoListeningRecordingCallback`, `triggerListening`) plus pipeline snapshots; no direct coordinator access.

### 4.5 Error Handling
- Service errors propagated to errorMessage
- Processing state cleared on error
- Fallback messages for network failures
- TTS errors handled with state reset

---

## 5. Stream Contracts

### Required Stream Subscriptions

1. **Recording State Stream**
   ```dart
   Source: voiceService.recordingState
   Type: Stream<RecordingState>
   Mapping: Contains "recording" → SetRecordingState(true)
   ```

2. **Audio Playback Stream**
   ```dart
   Source: voiceService.getAudioPlayerManager().isPlayingStream  
   Type: Stream<bool>
   Mapping: bool → AudioPlaybackStateChanged(bool)
   ```

3. **TTS State Stream**
   ```dart
   Source: voiceService.isTtsActuallySpeaking
   Type: Stream<bool>
   Mapping: bool → TtsStateChanged(bool)
   Critical: Triggers auto-listening after TTS
   ```

### Stream Lifecycle
- Created in constructor
- Cancelled in close() method
- Must handle null-safety

---

## 6. Critical Timing Requirements

### Mandatory Delays
```dart
// Auto-listening buffer (prevents self-detection)
static const Duration AUTO_LISTENING_BUFFER = Duration(milliseconds: 125);

// Voice mode switch delay (audio cleanup)
static const Duration VOICE_MODE_DELAY = Duration(milliseconds: 200);
```

### Timing Sequences
1. **After TTS Completes**: Wait 125ms → Enable auto-listening
2. **Voice Mode Switch**: Stop audio → Wait 200ms → Enable auto-mode
3. **Session End**: Immediate speaker mute → Then cleanup

---

## 7. Service Dependencies

### Required Service Interfaces
```dart
VoiceService                     // Legacy, being migrated
IVoiceService                    // New interface (Phase 6)
ITherapyService                  // AI therapy processing
VADManager                       // Voice activity detection
AutoListeningCoordinator         // VAD coordination
AudioPlayerManager               // Audio playback
```

### Service Method Calls
- Must use `_safeVoiceService` helper for interface methods
- Legacy methods via `voiceService` directly
- Therapy via injected service or DependencyContainer fallback

---

## 8. Threading Requirements

### Main Thread Only
- All event processing
- All state emissions
- Platform channel calls
- Stream subscriptions

### Async Operations (return to main thread)
- Service initialization
- Audio processing
- Network calls
- File operations

---

## 9. Preservation Requirements

### MUST Preserve
1. All 30+ event handlers
2. All state properties and getters
3. Stream subscription lifecycle
4. Timing delays (125ms, 200ms)
5. Error handling patterns
6. Message sequencing logic
7. Mode switching behavior
8. Welcome message generation

### Safe to Refactor (internally)
1. Private helper methods
2. Internal state management
3. Service coordination logic
4. Computation methods

---

## 10. Migration Strategy

### Phase 1 Approach (Current)
1. Create internal managers with focused responsibilities
2. VoiceSessionBloc becomes coordinating facade
3. Delegate operations to appropriate managers
4. Maintain exact public API

### Manager Responsibilities
- **SessionStateManager**: State transitions, status management
- **TimerManager**: Session timing, duration tracking  
- **MessageCoordinator**: Message processing, sequencing
- **VoiceSessionBloc**: Coordination, API preservation

### Success Criteria
- All characterization tests pass
- No breaking changes to public API
- Clean internal separation of concerns
- Improved testability and maintainability

---

**Document Version**: 1.0  
**Created**: Phase 0.5.3 - API Contract Specification  
**Purpose**: Complete API documentation for safe refactoring  
**Status**: FROZEN ❄️ - This API must be preserved
