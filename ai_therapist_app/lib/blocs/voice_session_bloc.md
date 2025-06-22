# Voice Session BLoC

## Overview
The `VoiceSessionBloc` manages the state of voice-enabled therapy sessions, coordinating real-time audio interactions, recording states, playback controls, and integration between voice services and the chat interface.

## Key Components

### `VoiceSessionBloc` Class
- **Type**: BLoC (Business Logic Component)
- **Purpose**: Coordinate voice session state and events
- **Key Features**:
  - Voice recording state management
  - Audio playback coordination
  - Real-time session updates
  - Error handling and recovery
  - Integration with voice services

## State Management

### State Classes
Defined in `voice_session_state.dart`:

#### `VoiceSessionInitial`
- **Purpose**: Initial state before session starts
- **Properties**: None
- **Usage**: Default state when bloc is created

#### `VoiceSessionIdle`
- **Purpose**: Session ready but not actively recording
- **Properties**: 
  - `isConnected`: Backend connection status
  - `sessionId`: Current session identifier
- **Usage**: Ready to start recording or playback

#### `VoiceSessionRecording`
- **Purpose**: Currently recording user audio
- **Properties**:
  - `duration`: Current recording duration
  - `audioLevel`: Real-time audio input level
  - `isNoiseReduced`: RNNoise status
- **Usage**: Active recording with visual feedback

#### `VoiceSessionProcessing`
- **Purpose**: Processing recorded audio (transcription/AI response)
- **Properties**:
  - `status`: Processing stage (transcribing, generating, synthesizing)
  - `progress`: Processing progress percentage
- **Usage**: Show processing indicators

#### `VoiceSessionPlaying`
- **Purpose**: Playing AI response audio
- **Properties**:
  - `audioUrl`: URL of audio being played
  - `duration`: Total audio duration
  - `position`: Current playback position
- **Usage**: Audio playback with controls

#### `VoiceSessionError`
- **Purpose**: Error state with recovery options
- **Properties**:
  - `error`: Error message or exception
  - `isRecoverable`: Whether error can be recovered
  - `retryAction`: Suggested recovery action
- **Usage**: Error display and recovery

## Event Classes
Defined in `voice_session_event.dart`:

### Recording Events
- `StartRecording`: Begin voice recording
- `StopRecording`: End voice recording
- `PauseRecording`: Temporarily pause recording
- `ResumeRecording`: Continue paused recording
- `CancelRecording`: Cancel current recording

### Playback Events
- `PlayAudio`: Start audio playback
- `PausePlayback`: Pause current playback
- `ResumePlayback`: Resume paused playback
- `StopPlayback`: Stop current playback
- `SeekPlayback`: Seek to position in audio

### Session Events
- `InitializeSession`: Start new voice session
- `EndSession`: Terminate current session
- `UpdateSessionSettings`: Change session configuration
- `CheckConnectionStatus`: Verify backend connectivity

### Error Events
- `RecoverFromError`: Attempt error recovery
- `ReportError`: Report new error condition
- `ClearError`: Clear current error state

## Event Handling

### Recording Flow
```dart
@override
Stream<VoiceSessionState> mapEventToState(VoiceSessionEvent event) async* {
  if (event is StartRecording) {
    try {
      yield VoiceSessionRecording(
        duration: Duration.zero,
        audioLevel: 0.0,
        isNoiseReduced: true,
      );
      
      await _voiceService.startRecording();
      yield* _monitorRecording();
    } catch (e) {
      yield VoiceSessionError(
        error: e.toString(),
        isRecoverable: true,
        retryAction: 'Retry Recording',
      );
    }
  }
}
```

### Processing Flow
```dart
Stream<VoiceSessionState> _processRecording(String audioPath) async* {
  yield VoiceSessionProcessing(
    status: 'Transcribing audio...',
    progress: 0.3,
  );
  
  final transcript = await _transcriptionService.transcribe(audioPath);
  
  yield VoiceSessionProcessing(
    status: 'Generating response...',
    progress: 0.6,
  );
  
  final response = await _therapyService.generateResponse(transcript);
  
  yield VoiceSessionProcessing(
    status: 'Creating audio...',
    progress: 0.9,
  );
  
  final audioUrl = await _voiceService.generateSpeech(response);
  
  yield VoiceSessionPlaying(
    audioUrl: audioUrl,
    duration: await _getAudioDuration(audioUrl),
    position: Duration.zero,
  );
}
```

## Service Integration

### Voice Service Integration
- **Recording Control**: Start/stop/pause recording
- **Audio Processing**: Handle audio file management
- **Quality Monitoring**: Monitor recording quality
- **Noise Reduction**: Coordinate RNNoise processing

### Therapy Service Integration
- **Message Processing**: Send transcribed messages
- **Response Generation**: Trigger AI response generation
- **Context Management**: Maintain conversation context
- **Session Tracking**: Update session progress

### Backend Service Integration
- **Real-time Communication**: WebSocket message handling
- **File Upload**: Upload recorded audio files
- **Status Updates**: Receive processing status updates
- **Error Handling**: Handle backend service errors

## Real-time Updates

### Audio Level Monitoring
```dart
Stream<VoiceSessionState> _monitorRecording() async* {
  await for (final audioLevel in _voiceService.audioLevelStream) {
    if (state is VoiceSessionRecording) {
      final currentState = state as VoiceSessionRecording;
      yield currentState.copyWith(audioLevel: audioLevel);
    }
  }
}
```

### Playback Progress
```dart
Stream<VoiceSessionState> _monitorPlayback() async* {
  await for (final position in _audioPlayer.positionStream) {
    if (state is VoiceSessionPlaying) {
      final currentState = state as VoiceSessionPlaying;
      yield currentState.copyWith(position: position);
    }
  }
}
```

## Error Handling

### Error Types
- **Permission Errors**: Microphone access denied
- **Network Errors**: Backend connectivity issues
- **Recording Errors**: Audio recording failures
- **Processing Errors**: Transcription or AI failures
- **Playback Errors**: Audio playback issues

### Recovery Strategies
```dart
Future<void> _handleError(Exception error) async {
  if (error is PermissionException) {
    add(RecoverFromError(action: 'request_permissions'));
  } else if (error is NetworkException) {
    add(RecoverFromError(action: 'retry_connection'));
  } else {
    add(ReportError(error: error));
  }
}
```

## Performance Optimization

### Memory Management
- **Audio Buffer Management**: Efficient audio data handling
- **State Cleanup**: Proper state disposal
- **Resource Release**: Clean up audio resources
- **Garbage Collection**: Minimize memory leaks

### Battery Optimization
- **Recording Efficiency**: Optimize recording algorithms
- **Processing Optimization**: Efficient audio processing
- **Background Handling**: Proper background state management
- **Wake Lock Management**: Coordinate with wake lock service

## Testing Support

### Mock Events
```dart
// Test helper for generating mock events
class MockVoiceSessionEvents {
  static StartRecording startRecording() => StartRecording();
  static StopRecording stopRecording() => StopRecording();
  static PlayAudio playAudio(String url) => PlayAudio(audioUrl: url);
}
```

### State Verification
```dart
// Test utilities for state verification
void expectRecordingState(VoiceSessionState state) {
  expect(state, isA<VoiceSessionRecording>());
  final recordingState = state as VoiceSessionRecording;
  expect(recordingState.duration, isNotNull);
}
```

## Dependencies
- `flutter_bloc`: BLoC pattern implementation
- `equatable`: State comparison
- Voice services for audio operations
- Therapy services for AI interactions
- Backend services for communication

## Usage Example
```dart
// Initialize bloc
final voiceSessionBloc = VoiceSessionBloc();

// Start recording
voiceSessionBloc.add(StartRecording());

// Listen to state changes
voiceSessionBloc.stream.listen((state) {
  if (state is VoiceSessionRecording) {
    // Update UI for recording
  } else if (state is VoiceSessionPlaying) {
    // Update UI for playback
  }
});
```

## Related Files
- `lib/blocs/voice_session_event.dart` - Event definitions
- `lib/blocs/voice_session_state.dart` - State definitions
- `lib/services/voice_service.dart` - Voice operations
- `lib/services/therapy_service.dart` - AI interactions
- `lib/screens/chat_screen.dart` - UI integration