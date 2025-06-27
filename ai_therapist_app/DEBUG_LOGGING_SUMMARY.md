# TTS/VAD Coordination Debugging Logs

This document summarizes the comprehensive debugging logs added to track the TTS/VAD coordination flow from start to finish.

## Log Prefixes Used

- `[TTS-VAD]` - TTS/VAD coordination events
- `[AUDIO-FLOW]` - Audio playback tracking events
- `[STATE-TRACK]` - State transitions and their triggers
- `[TIMING]` - Timing-related events (delays, buffers)

## Files Modified with Debug Logging

### 1. VoiceSessionBloc (`lib/blocs/voice_session_bloc.dart`)

**Key Methods Enhanced:**
- `_onTtsStateChanged()` - Tracks TTS state transitions and auto mode enablement conditions
- `_onEnableAutoMode()` - Detailed logging of auto mode enablement process
- `_onDisableAutoMode()` - Tracks auto mode disabling 
- `_onAudioPlaybackStateChanged()` - Monitors audio playback state changes

**Sample Log Output:**
```
[TTS-VAD] [VoiceSessionBloc] TTS state changed: false
[STATE-TRACK] [VoiceSessionBloc] Previous AI speaking state: true
[STATE-TRACK] [VoiceSessionBloc] New AI speaking state: false
[TTS-VAD] [VoiceSessionBloc] TTS transition detected (true -> false), initial TTS has completed, enabling listening
[TIMING] [VoiceSessionBloc] Adding 125ms buffer delay before enabling auto mode
[TTS-VAD] [VoiceSessionBloc] Dispatching EnableAutoMode after TTS with buffer delay
```

### 2. AudioPlayerManager (`lib/services/audio_player_manager.dart`)

**Key Methods Enhanced:**
- `_emitPlayingState()` - Tracks audio playing state changes with detailed context
- `playerStateStream.listen()` - Monitors audio player state transitions
- `processingStateStream.listen()` - Tracks audio processing state changes
- `stopAudio()` - Comprehensive logging of audio stop operations

**Sample Log Output:**
```
[AUDIO-FLOW] [AudioPlayerManager] Playing state changed to true
[STATE-TRACK] [AudioPlayerManager] Previous state: false, New state: true
[AUDIO-FLOW] [AudioPlayerManager] Audio playback started
[AUDIO-FLOW] [AudioPlayerManager] Processing state changed: ProcessingState.completed
[AUDIO-FLOW] [AudioPlayerManager] Audio playback completed - emitting stopped state
```

### 3. EnhancedVADManager (`lib/services/enhanced_vad_manager.dart`)

**Key Methods Enhanced:**
- `startListening()` - Detailed VAD startup conditions and state validation
- `stopListening()` - Comprehensive shutdown sequence tracking
- `_triggerSpeechStart()` - Speech detection event logging
- `_triggerSpeechEnd()` - Speech end event logging

**Sample Log Output:**
```
[TTS-VAD] [EnhancedVADManager] 🎙️ Enhanced VAD: Starting voice activity detection
[STATE-TRACK] [EnhancedVADManager] VAD start conditions:
[STATE-TRACK] [EnhancedVADManager] - Is initialized: true
[STATE-TRACK] [EnhancedVADManager] - Is disposing: false
[STATE-TRACK] [EnhancedVADManager] - Is listening: false
[STATE-TRACK] [EnhancedVADManager] - Use RNNoise: true
[TTS-VAD] [EnhancedVADManager] 🗣️ Enhanced VAD: Speech started (RNNoise)
[STATE-TRACK] [EnhancedVADManager] Speech detection state changed: true
```

### 4. AutoListeningCoordinator (`lib/services/auto_listening_coordinator.dart`)

**Key Methods Enhanced:**
- `enableAutoMode()` - Auto mode enablement with state validation
- `disableAutoMode()` - Auto mode disabling with resource cleanup tracking
- `_startListening()` - VAD startup process logging
- `_stopListeningAndRecording()` - Comprehensive stop sequence tracking

**Sample Log Output:**
```
[TTS-VAD] [AutoListeningCoordinator] enableAutoMode called
[STATE-TRACK] [AutoListeningCoordinator] Current state: AutoListeningState.idle
[STATE-TRACK] [AutoListeningCoordinator] Auto mode enabled: false
[STATE-TRACK] [AutoListeningCoordinator] VAD active: false
[STATE-TRACK] [AutoListeningCoordinator] Recording active: false
[TIMING] [AutoListeningCoordinator] Post-audio delay timer cancelled
[TTS-VAD] [AutoListeningCoordinator] Auto mode enabled, broadcasting state change
```

### 5. TTSService (`lib/services/tts_service.dart`)

**Key Methods Enhanced:**
- `_setIsSpeaking()` - TTS speaking state changes with context
- Existing TTS VAD FIX logs maintained and enhanced

**Sample Log Output:**
```
[TTS-VAD] [TTSService] 🔍 TTSService speaking state changed: true
[STATE-TRACK] [TTSService] Previous speaking state: false, New state: true
[TTS-VAD] [TTSService] 🔍 TTS started - VAD should be paused
[TTS-VAD] [TTSService] 🔍 TTSService speaking state changed: false
[TTS-VAD] [TTSService] 🔍 TTS stopped - VAD can be resumed (if onDone was called)
```

### 6. VoiceService (`lib/services/voice_service.dart`)

**Key Methods Enhanced:**
- `_setAiSpeaking()` - AI speaking state management
- `updateTTSSpeakingState()` - External TTS state updates

**Sample Log Output:**
```
[TTS-VAD] [VoiceService] updateTTSSpeakingState called with: true
[STATE-TRACK] [VoiceService] External TTS state update request
[TTS-VAD] [VoiceService] _setAiSpeaking called with: true
[STATE-TRACK] [VoiceService] Current AI speaking state: false
[TTS-VAD] [VoiceService] 🔍 VoiceService._setAiSpeaking: TTS state set to true
[STATE-TRACK] [VoiceService] TTS state broadcast to listeners
```

## Debugging Flow

The logs create a clear audit trail showing:

1. **TTS Start**: When TTS begins (TTSService + VoiceService)
2. **VAD Pause**: When VAD is paused due to TTS (EnhancedVADManager)
3. **Audio Playback**: When audio starts/stops playing (AudioPlayerManager)
4. **TTS Completion**: When TTS finishes (TTSService WebSocket "done" signal)
5. **VAD Resume**: When VAD is resumed after TTS completion (AutoListeningCoordinator)
6. **State Coordination**: How VoiceSessionBloc coordinates the entire flow

## Usage

To debug TTS/VAD coordination issues:

1. **Run the app in debug mode** - All logs are wrapped in `if (kDebugMode)` checks
2. **Filter logs by prefix** - Use grep or IDE filtering to focus on specific aspects:
   - `grep "\[TTS-VAD\]"` - TTS/VAD coordination events
   - `grep "\[AUDIO-FLOW\]"` - Audio playback issues
   - `grep "\[STATE-TRACK\]"` - State synchronization problems
   - `grep "\[TIMING\]"` - Timing and delay issues

3. **Look for specific patterns**:
   - Maya detecting her own voice: Look for premature VAD resume
   - VAD not resuming: Check TTS completion signals
   - Audio playback issues: Monitor AudioPlayerManager state changes
   - State desynchronization: Track state transitions across components

## Expected Flow

A normal TTS/VAD coordination flow should show:

1. `[TTS-VAD] TTS started` → VAD paused
2. `[AUDIO-FLOW] Audio playback started`
3. `[AUDIO-FLOW] Audio playback completed`
4. `[TTS-VAD] Backend sent "done" signal`
5. `[TTS-VAD] TTS stopped` → VAD resume ready
6. `[TIMING] Buffer delay` → Prevent false triggering
7. `[TTS-VAD] Auto mode enabled` → VAD active again

Any deviations from this flow indicate timing issues that need investigation.