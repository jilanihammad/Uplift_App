# Voice Service

## Overview
The `VoiceService` is a comprehensive audio management service that handles voice recording, processing, Text-to-Speech (TTS), audio session management, and noise reduction. It serves as the central hub for all voice-related functionality in the AI therapy app.

## Key Components

### `VoiceService` Class
- **Type**: Service Class
- **Purpose**: Unified voice processing and audio management
- **Key Features**:
  - Audio recording with noise reduction
  - Real-time audio streaming
  - TTS generation and playback
  - Audio session lifecycle management
  - Integration with RNNoise for noise cancellation

### `FileCleanupManager` Class
- **Type**: Utility Class
- **Purpose**: Manage temporary audio file lifecycle
- **Key Features**:
  - Automatic cleanup of temporary files
  - Storage optimization
  - Resource management

## Core Functionality

### Audio Recording
- **Recording Control**: Start, stop, pause, resume recording
- **Format Support**: WAV, MP3, OGG formats
- **Quality Settings**: Configurable bitrate and sample rate
- **Real-time Processing**: Live audio enhancement during recording

### Noise Reduction
- **RNNoise Integration**: Real-time noise cancellation
- **Adaptive Filtering**: Dynamic noise reduction based on environment
- **Quality Enhancement**: Audio clarity improvement
- **Background Noise Suppression**: Filter out ambient sounds

### Text-to-Speech (TTS)
- **Multiple Providers**: Support for various TTS engines
- **Voice Selection**: Different voice options and languages
- **Speech Rate Control**: Adjustable speaking speed
- **SSML Support**: Speech Synthesis Markup Language
- **Audio Quality**: High-quality voice generation

### Audio Playback
- **Multiple Format Support**: Play various audio formats
- **Playback Controls**: Play, pause, stop, seek functionality
- **Volume Control**: Audio level management
- **Streaming Support**: Progressive audio playback

## Integration Features

### Backend Communication
- **Real-time Streaming**: Stream audio to backend services
- **Transcription Integration**: Send audio for speech-to-text
- **TTS Requests**: Request AI-generated speech
- **Error Handling**: Robust error recovery

### Voice Activity Detection (VAD)
- **Smart Detection**: Identify speech vs silence
- **Automatic Recording**: Start/stop based on voice activity
- **Timeout Handling**: Automatic session management
- **Threshold Adjustment**: Adaptive sensitivity

### Session Management
- **Session Lifecycle**: Handle recording sessions
- **Context Preservation**: Maintain audio context
- **Concurrent Sessions**: Manage multiple audio streams
- **Resource Allocation**: Efficient resource usage

## Configuration Options

### Audio Settings
```dart
class AudioConfig {
  int sampleRate;        // Audio sample rate (default: 16000)
  int bitRate;           // Audio bit rate (default: 64000)
  String format;         // Audio format ('wav', 'mp3', 'ogg')
  bool noiseReduction;   // Enable RNNoise (default: true)
  double vadThreshold;   // Voice activity threshold (0.0-1.0)
}
```

### TTS Configuration
```dart
class TTSConfig {
  String provider;       // TTS provider ('openai', 'google', 'azure')
  String voice;          // Voice selection
  double rate;           // Speaking rate (0.5-2.0)
  double pitch;          // Voice pitch (0.5-2.0)
  String language;       // Language code
}
```

## Methods

### Recording Methods
- `startRecording()`: Begin audio recording
- `stopRecording()`: End recording and return file
- `pauseRecording()`: Temporarily pause recording
- `resumeRecording()`: Continue paused recording
- `cancelRecording()`: Cancel current recording

### TTS Methods
- `generateSpeech(String text)`: Create TTS audio
- `speakText(String text)`: Immediate text-to-speech
- `stopSpeaking()`: Stop current TTS playback
- `setSpeechRate(double rate)`: Adjust speaking speed

### Playback Methods
- `playAudio(String audioPath)`: Play audio file
- `stopPlayback()`: Stop current playback
- `pausePlayback()`: Pause audio playback
- `resumePlayback()`: Resume paused audio

### Utility Methods
- `isRecording()`: Check recording status
- `isPlaying()`: Check playback status
- `getAudioLevel()`: Current audio input level
- `cleanup()`: Clean up resources and temporary files

## Error Handling
- **Permission Errors**: Handle microphone access denials
- **Hardware Issues**: Manage audio device problems
- **Network Failures**: Backend communication errors
- **File System Errors**: Storage and file access issues
- **Format Errors**: Unsupported audio format handling

## Platform Support
- **iOS**: AVAudioSession integration
- **Android**: MediaRecorder and AudioManager
- **Web**: WebRTC audio APIs
- **Desktop**: Platform-specific audio libraries

## Dependencies
- `record`: Audio recording functionality
- `just_audio`: Audio playback
- `flutter_tts`: Text-to-speech
- `permission_handler`: Audio permissions
- `path_provider`: File system access
- RNNoise plugin for noise reduction

## Usage Example
```dart
final voiceService = serviceLocator<VoiceService>();

// Start recording
await voiceService.startRecording();

// Stop and get audio file
final audioFile = await voiceService.stopRecording();

// Generate TTS
await voiceService.speakText("Hello, how are you feeling today?");

// Cleanup
voiceService.cleanup();
```

## Performance Optimization
- **Memory Management**: Efficient audio buffer handling
- **CPU Usage**: Optimized noise reduction algorithms
- **Battery Life**: Power-efficient recording modes
- **Storage**: Automatic cleanup of temporary files

## Security Features
- **Permission Handling**: Proper audio permission management
- **Data Privacy**: Secure audio data handling
- **Encryption**: Audio data encryption in transit
- **Local Processing**: Minimize cloud audio transmission

## Related Files
- `lib/services/rnnoise_service.dart` - Noise reduction
- `lib/services/transcription_service.dart` - Speech-to-text
- `lib/services/audio_player_manager.dart` - Playback management
- `lib/services/recording_manager.dart` - Recording control
- `lib/services/vad_manager.dart` - Voice activity detection
- `lib/services/path_manager.dart` - File management