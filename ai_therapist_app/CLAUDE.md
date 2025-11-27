# CLAUDE.md

Comprehensive guidance for engineers working on the Maya AI Therapist Flutter app.

## Core Commands

```bash
# Setup
flutter clean
flutter pub get

# Run app
dart run build_runner clean   # only if code-gen artifacts exist
flutter run                    # choose device or emulator

# Code quality
flutter analyze
dart format .

# Testing
flutter test                   # all unit/widget tests
flutter test integration_test  # integration tests

# Builds
flutter build apk --debug
flutter build apk --release
flutter build ios --no-codesign
```

---

## High-Level Architecture

### State Management (BLoC Pattern)
- **VoiceSessionBloc** (`lib/blocs/voice_session_bloc.dart`): Central orchestrator for voice sessions
  - Manages voice/chat mode switching
  - Coordinates TTS, recording, and auto-listening states
  - Uses generation counters (`_modeGeneration`) to prevent stale callbacks
- **Helper Managers**: TimerManager, MessageCoordinator, SessionStateManager decompose bloc complexity
- **State Flow**: Events → BLoC → State → UI rebuilds

### Dependency Injection
- **ServiceLocator** (`lib/di/service_locator.dart`): GetIt-based registration
- **DependencyContainer** (`lib/di/dependency_container.dart`): Typed service access
- **SessionScopeManager** (`lib/services/session_scope_manager.dart`): Per-session service lifecycle
  - Creates fresh AudioPlayerManager, VoiceSessionCoordinator per session
  - Disposes services on session end to prevent memory leaks

### Services Layer (`lib/services/`)
| Service | Purpose |
|---------|---------|
| `voice_service.dart` | Master orchestrator for recording, TTS, auto-listening |
| `voice_session_coordinator.dart` | Focused interface for bloc-to-service communication |
| `simple_tts_service.dart` | WebSocket TTS streaming with queue management |
| `auto_listening_coordinator.dart` | VAD-driven automatic recording triggers |
| `enhanced_vad_manager.dart` | RNNoise-based voice activity detection |
| `recording_manager.dart` | Audio recording with shared recorder access |
| `audio_player_manager.dart` | ExoPlayer/just_audio wrapper for playback |

---

## Voice Pipeline Architecture

### Audio Flow (Voice Mode)
```
┌─────────────────────────────────────────────────────────────────────┐
│                        VOICE SESSION FLOW                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. VAD Detection (EnhancedVADManager)                              │
│     └── RNNoise confidence > 0.8 threshold                          │
│     └── Min 5 speech frames (50ms) to trigger                       │
│     └── Min 30 silence frames (300ms) to end                        │
│                                                                     │
│  2. Recording (RecordingManager)                                    │
│     └── SharedRecorderAccess prevents concurrent recorder use       │
│     └── 48kHz mono M4A format                                       │
│     └── Path: /cache/recordings/{uuid}.m4a                          │
│                                                                     │
│  3. Transcription (VoiceService → Backend)                          │
│     └── POST /voice/transcribe with base64 audio                    │
│     └── 45s timeout for slow connections                            │
│                                                                     │
│  4. LLM Response (MessageProcessor → Backend)                       │
│     └── POST /ai/response with history context                      │
│     └── State machine guides conversation flow                      │
│                                                                     │
│  5. TTS Streaming (SimpleTTSService)                                │
│     └── WebSocket /ws/tts                                           │
│     └── WAV format (OPUS disabled - see Audio Format section)       │
│     └── Progressive streaming with 4KB buffer threshold             │
│                                                                     │
│  6. Playback (AudioPlayerManager)                                   │
│     └── ExoPlayer on Android, AVPlayer on iOS                       │
│     └── Natural completion triggers listening restart               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Auto-Listening State Machine
```
┌───────────────────────────────────────────────────────────────────┐
│              AutoListeningCoordinator States                       │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│   idle ──(enableAutoMode)──► listeningForVoice                    │
│     │                              │                              │
│     │                              │ (VAD speech start)           │
│     │                              ▼                              │
│     │                         userSpeaking                        │
│     │                              │                              │
│     │                              │ (VAD speech end + timeout)   │
│     │                              ▼                              │
│     │                         processing                          │
│     │                              │                              │
│     │                              │ (transcription complete)     │
│     │                              ▼                              │
│     │                         aiSpeaking                          │
│     │                              │                              │
│     │◄─────(TTS complete)─────────┘                               │
│     │                                                             │
│     │◄─────(disableAutoMode)───── any state                       │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## TTS Streaming Implementation

### SimpleTTSService Architecture (`lib/services/simple_tts_service.dart`)

**Queue-Based Processing**:
- Requests queued to prevent overlapping TTS
- `hasPendingOrActiveTts` getter for race condition checks
- Generation tracking prevents stale completions

**WebSocket Connection Pooling** (lines 161-204):
```dart
// Pre-warmed connections save ~150ms per request
WebSocketChannel? _prewarmedConnection;
static const Duration _connectionTtl = Duration(seconds: 30);

Future<WebSocketChannel> _getConnection(String wsUrl) async {
  // Reuse pre-warmed connection if valid
  // Start pre-warming next connection in background
}
```

**Streaming Flow**:
1. Send `{text, voice, format}` over WebSocket
2. Receive `hello` message with mime type
3. Accumulate audio chunks until buffer threshold (4KB)
4. Start playback with LiveTtsAudioSource
5. Continue streaming remaining chunks
6. Receive `tts-done` message
7. Wait for playback completion

**Race Condition Guards** (lines 1429-1450):
```dart
// Don't reset TTS state if playback is active
@override
void resetTTSState() {
  if (_queue.isNotEmpty || _state != _State.idle || _pendingStreams > 0) {
    debugPrint('🛡️ Skipping reset - active TTS in progress');
    return;
  }
  // ... actual reset
}
```

---

## VAD (Voice Activity Detection)

### EnhancedVADManager (`lib/services/enhanced_vad_manager.dart`)

**RNNoise Integration**:
- Native noise suppression via `rnnoise_flutter` plugin
- 48kHz sample rate required
- Returns VAD probability (0.0 - 1.0)

**Thresholds (tuned to reduce false positives)**:
```dart
double _speechThreshold = 0.8;      // RNNoise confidence threshold
int _minSpeechFrames = 5;           // 50ms at 10fps to start
int _minSilenceFrames = 30;         // 300ms at 10fps to end
```

**Android AudioRecord.read() Blocking Fix** (CRITICAL):

The `audio_streamer` package uses blocking `AudioRecord.read()` on Android. When stopping VAD, the worker thread can get stuck waiting for audio frames.

**Old Approach (caused 500ms timeouts)**:
```dart
await _audioSubscription!.cancel();
await _workerDone!.future.timeout(Duration(milliseconds: 500)); // BLOCKED!
```

**New Non-Blocking Approach** (lines 698-800):
```dart
Future<void> stopListening() async {
  // 1. Set shutdown flags IMMEDIATELY
  _isShuttingDown = true;
  _isStreamActive = false;
  _isListening = false;

  // 2. Complete worker future IMMEDIATELY (don't wait for blocked read())
  _completeWorkerIfNeeded('shutdown signal');

  // 3. Cancel subscription without awaiting (sends stop signal to native)
  unawaited(_audioSubscription!.cancel());

  // 4. Brief delay for stop signal propagation (NOT waiting for read())
  await Future.delayed(Duration(milliseconds: 50));
}
```

**Key Insight**: The worker thread will naturally stop on its next frame because the shutdown flag checks in `_processRNNoiseAudioChunk` will return early:
```dart
if (!_isInitialized || !_isStreamActive || _isShuttingDown || !_isListening) {
  return; // Exit early - worker effectively stopped
}
```

---

## Audio Format Configuration

### AudioFormatConfig (`lib/config/audio_format_config.dart`)

**Current Settings**:
```dart
static bool get enableOpusFormat => false;  // WAV mode
static int get opusRolloutPercentage => 0;  // OPUS disabled
```

**Why OPUS is Disabled**:
The backend (OpenAI TTS) returns WAV format by default. Even when the client requests OPUS:
```
Client: format=opus
Backend Response: RIFF....WAVEfmt (WAV data!)
```

To enable OPUS, the backend would need `response_format: "opus"` in the OpenAI TTS API call.

**Audio Format Negotiator** (`lib/services/audio_format_negotiator.dart`):
- Priority: Native (Gemini Live) > Client OPUS preference > Backend format > WAV fallback
- Emergency fallback to WAV if streaming fails
- Format info logged for debugging

---

## Critical Race Conditions & Fixes

### 1. TTS Reset During Active Playback
**Problem**: `resetTTSState()` was killing AI response TTS when welcome message completed.

**Fix** (`voice_session_bloc.dart:771-784`):
```dart
if (_safeVoiceService.hasPendingOrActiveTts) {
  debugPrint('Skipping stopAudio/resetTTS - active TTS in progress');
  // Still enable auto mode but skip destructive operations
  await _safeVoiceService.enableAutoMode();
  return;
}
```

### 2. Auto Mode Desync During Mic Toggle
**Problem**: Toggling mic during TTS caused `autoModeEnabled` to desync from bloc state. When TTS finished, Maya wouldn't resume listening.

**Fix A** - Include mic state in callback (`voice_session_bloc.dart:303-307`):
```dart
voiceService.canStartListeningCallback = () =>
    state.isVoiceMode &&
    state.isInitialGreetingPlayed &&
    state.isMicEnabled &&  // CRITICAL: Include mic state
    !state.isVoiceModeSwitching;
```

**Fix B** - Re-enable auto mode on TTS completion (`voice_service.dart:1699-1714`):
```dart
if (!_autoListeningCoordinator.autoModeEnabled) {
  // If bloc says we CAN listen, re-enable auto mode
  if (canStartListeningCallback != null && canStartListeningCallback!()) {
    _autoListeningCoordinator.enableAutoMode();
    _autoListeningCoordinator.startListening();
    return;
  }
}
```

### 3. Generation Counter Pattern
Used throughout to prevent stale async callbacks:
```dart
final gen = _modeGeneration;
await someAsyncOperation();
if (gen != _modeGeneration) return; // State changed, abort
```

---

## Interfaces & Contracts

### IVoiceService (`lib/di/interfaces/i_voice_service.dart`)
Key methods for voice operations:
- `startRecording()` / `stopRecording()` / `tryStopRecording()` (idempotent)
- `enableAutoMode()` / `disableAutoMode()`
- `updateTTSSpeakingState(bool, {int? playbackToken})`
- `hasPendingOrActiveTts` - Race condition guard

### ITTSService (`lib/di/interfaces/i_tts_service.dart`)
TTS operations:
- `speak(text, {voice, format, caller})` - Queue TTS request
- `stopSpeaking()` - Cancel active TTS
- `hasPendingOrActiveTts` - Check for active/queued TTS

---

## Common Gotchas & Debugging Tips

### Don't Do This
```dart
// ❌ Don't await subscription cancel on Android (blocks on AudioRecord.read)
await _audioSubscription!.cancel();

// ❌ Don't reset TTS state without checking hasPendingOrActiveTts
_ttsService.resetTTSState(); // May kill active AI response!

// ❌ Don't call disableAutoMode without considering TTS state
disableAutoMode(); // May prevent listening restart after TTS

// ❌ Don't ignore generation counters in async callbacks
await longOperation();
emit(state); // State may have changed!
```

### Do This Instead
```dart
// ✅ Use unawaited for subscription cancel
unawaited(_audioSubscription!.cancel());

// ✅ Check hasPendingOrActiveTts before reset
if (!_ttsService.hasPendingOrActiveTts) {
  _ttsService.resetTTSState();
}

// ✅ Check canStartListeningCallback for current bloc state
if (canStartListeningCallback?.call() ?? false) {
  _autoListeningCoordinator.enableAutoMode();
}

// ✅ Use generation counters
final gen = _generation;
await longOperation();
if (gen != _generation) return;
```

### Useful Debug Logs
```
🎯 [TTS] Starting playback     - TTS request started
✅ [TTS] Natural completion    - Playback finished normally
🛡️ [TTS] Skipping reset       - Race condition guard triggered
🛑 Enhanced VAD: Shutdown flags set - VAD stopping (non-blocking)
[VoiceService] TTS done – autoMode disabled but bloc allows listening, re-enabling
```

---

## File Organization

```
lib/
├── blocs/
│   └── voice_session_bloc.dart      # Main session orchestrator
├── config/
│   ├── audio_format_config.dart     # OPUS/WAV settings
│   └── llm_config.dart              # LLM provider settings
├── di/
│   ├── interfaces/                  # Service contracts
│   ├── service_locator.dart         # GetIt registration
│   └── dependency_container.dart    # Typed service access
├── services/
│   ├── voice_service.dart           # Voice orchestrator
│   ├── simple_tts_service.dart      # TTS streaming
│   ├── auto_listening_coordinator.dart  # VAD coordination
│   ├── enhanced_vad_manager.dart    # RNNoise VAD
│   ├── recording_manager.dart       # Audio recording
│   └── audio_player_manager.dart    # Playback
├── screens/
│   └── chat_screen.dart             # Main UI
└── utils/
    ├── feature_flags.dart           # Runtime toggles
    └── opus_header_utils.dart       # Audio format utilities
```

---

## Recent Updates (2025-11)

### Performance Optimizations
- WebSocket connection pooling saves ~150ms per TTS request
- Reduced TTS buffer from 32KB to 4KB for faster time-to-first-audio
- AudioPlayerManager pre-warming on app startup
- Deferred RemoteConfigService initialization

### Bug Fixes
- VAD worker thread no longer blocks on `AudioRecord.read()` (non-blocking shutdown)
- Auto mode re-enablement after TTS when mic was toggled during playback
- TTS reset race condition guard (`hasPendingOrActiveTts`)
- Generation counter pattern prevents stale async callbacks

### Architecture Changes
- `canStartListeningCallback` now includes `isMicEnabled` state
- VoiceService re-enables auto mode on TTS completion if bloc allows
- Enhanced VAD uses immediate shutdown flags instead of waiting for blocked threads

---

## Testing Checklist for Voice Features

Before merging voice pipeline changes:
- [ ] Start voice session, let Maya speak welcome message
- [ ] User speaks, Maya responds (full cycle)
- [ ] Toggle mic ON/OFF during TTS - Maya should resume listening after TTS
- [ ] End session during TTS - TTS should stop cleanly
- [ ] Background app during TTS - audio should continue
- [ ] Check logs for race condition warnings (`🛡️`, `⚠️`)
- [ ] No "Worker completion timeout" warnings in logs
- [ ] `flutter analyze` passes

---

## Contributing

1. Read this document thoroughly before making voice pipeline changes
2. Use generation counters for all async operations that modify state
3. Check `hasPendingOrActiveTts` before any TTS reset/stop operations
4. Test mic toggle during TTS playback
5. Update this document when adding new patterns or fixing bugs
