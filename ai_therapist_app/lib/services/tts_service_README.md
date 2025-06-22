# TTSService Implementation

## Overview

The `TTSService` class is a focused, single-responsibility service that extracts all Text-to-Speech functionality from the monolithic `VoiceService`. It implements the `ITTSService` interface and provides robust TTS generation, streaming, and playback capabilities.

## Key Features

### 🎯 **Extracted TTS Functionality**
- **Speech Generation**: Generate TTS audio from text with multiple voice options
- **Streaming TTS**: Real-time TTS streaming with progress callbacks
- **Audio Playback**: Integrated with existing `AudioPlayerManager`
- **State Management**: Proper `isPlaying` and `isSpeaking` state tracking
- **WebSocket Support**: Reusable WebSocket connections for streaming TTS

### ⏱️ **Critical Timing Fix Preserved**
- **125ms Buffer**: Maintains the critical timing fix that prevents Maya from detecting her own voice
- **Timing Diagnostics**: Comprehensive timing logging for performance monitoring
- **State Coordination**: Proper coordination with `VoiceSessionBloc` for timing

### 🔄 **Streaming Architecture**
- **Session Isolation**: Each TTS request gets a unique session ID
- **Concurrent Handling**: Multiple TTS requests can be handled simultaneously
- **Connection Reuse**: WebSocket connections are reused for efficiency
- **Automatic Fallback**: WAV → MP3 fallback for maximum compatibility

### 🛡️ **Error Handling & Robustness**
- **Mutex Protection**: Prevents concurrent TTS operations that could cause race conditions
- **File Cleanup**: Automatic cleanup of temporary audio files
- **Connection Recovery**: Automatic WebSocket reconnection on failures
- **Graceful Degradation**: Comprehensive error handling with callbacks

## Implementation Details

### Dependencies
- `AudioPlayerManager`: For audio playback (preserves existing infrastructure)
- `ApiClient`: For backend TTS requests
- `PathManager`: For secure file path generation
- `WebSocketChannel`: For streaming TTS connections

### Key Methods

#### Core TTS Operations
```dart
Future<String> generateSpeech(String text, {String voice = 'alloy'})
Future<void> streamAndPlayTTS(String text, {callbacks...})
```

#### Audio Control
```dart
Future<void> playAudio(String audioPath)
Future<void> stopAudio()
Future<void> pauseAudio()
Future<void> resumeAudio()
```

#### State Management
```dart
bool get isPlaying
bool get isSpeaking
Stream<bool> get playbackStateStream
Stream<bool> get speakingStateStream
```

#### Configuration
```dart
void setVoiceSettings(String voice, double speed, double pitch)
void setAudioFormat(String format)
void resetTTSState()
```

### Preserved Critical Features

1. **125ms Buffer Timing**: 
   ```dart
   // CRITICAL: 125ms buffer timing fix to prevent Maya from detecting her own voice
   await Future.delayed(const Duration(milliseconds: 125));
   ```

2. **Session-based WebSocket Handling**:
   ```dart
   final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
   final sessionController = StreamController<dynamic>.broadcast();
   _activeSessions[sessionId] = sessionController;
   ```

3. **Comprehensive Timing Diagnostics**:
   ```dart
   final totalStopwatch = Stopwatch()..start();
   final wsConnectStopwatch = Stopwatch();
   final firstChunkStopwatch = Stopwatch();
   ```

## Integration

### Service Registration
The service is registered in `ServicesModule`:

```dart
// Register AudioPlayerManager (no dependencies)
locator.registerLazySingleton<AudioPlayerManager>(
  () => AudioPlayerManager(),
);

// Register TTSService with dependencies
locator.registerLazySingleton<TTSService>(
  () => TTSService(
    audioPlayerManager: locator<AudioPlayerManager>(),
    apiClient: locator<ApiClient>(),
  ),
);

// Register interface for TTSService
locator.registerLazySingleton<ITTSService>(
  () => locator<TTSService>(),
);
```

### Usage Example
```dart
final ttsService = serviceLocator<ITTSService>();

// Initialize the service
await ttsService.initialize();

// Stream and play TTS with callbacks
await ttsService.streamAndPlayTTS(
  'Hello, this is a test message',
  onDone: () => print('TTS completed'),
  onError: (error) => print('TTS error: $error'),
  onProgress: (progress) => print('Progress: $progress'),
);

// Control playback
if (ttsService.isPlaying) {
  await ttsService.stopAudio();
}

// Cleanup
ttsService.dispose();
```

## File Structure

```
lib/services/
├── tts_service.dart                 # Main TTS service implementation
├── audio_player_manager.dart        # Audio playback (reused)
├── path_manager.dart               # File path management (reused)
└── voice_service.dart              # Original service (to be refactored)

lib/di/interfaces/
├── i_tts_service.dart              # TTS service interface
└── interfaces.dart                 # Interface exports

lib/di/modules/
└── services_module.dart            # Service registration
```

## Benefits of This Implementation

1. **Single Responsibility**: TTS service now has a focused, single purpose
2. **Maintainability**: Easier to test, debug, and extend TTS functionality
3. **Timing Preservation**: All critical timing fixes are preserved
4. **Error Resilience**: Robust error handling and recovery mechanisms
5. **Performance**: Efficient WebSocket reuse and connection management
6. **Clean Architecture**: Proper dependency injection and interface-based design

## Next Steps

1. **VoiceService Refactoring**: Remove TTS code from VoiceService and use TTSService
2. **Testing**: Add comprehensive unit tests for TTSService
3. **Performance Optimization**: Monitor and optimize WebSocket connection pooling
4. **Feature Enhancement**: Add support for SSML, voice cloning, and advanced audio effects

---

✅ **Status**: Implementation Complete - Ready for integration and testing