import 'dart:async';
import 'dart:io';

/// Base interface for voice services
///
/// This interface defines the core functionality that any voice service
/// implementation must provide. It allows for dependency injection and
/// easier testing with mock implementations.
abstract class BaseVoiceService {
  /// Stream that emits the current recording state
  Stream<RecordingState> get recordingStateStream;

  /// Stream that emits when audio is playing
  Stream<bool> get isPlayingStream;

  /// Stream that emits the current voice processing error
  Stream<String?> get errorStream;

  /// Initialize the voice service
  Future<void> initialize();

  /// Start recording audio
  Future<void> startRecording();

  /// Stop recording and return the file path
  Future<String> stopRecording();

  /// Transcribe audio from a file path
  Future<String> transcribeAudio(String audioFilePath);

  /// Generate audio from text and return the file path
  Future<String> generateAudio(String text);

  /// Play audio from a file
  Future<void> playAudio(String audioPath);

  /// Stop playing audio
  Future<void> stopAudio();

  /// Generate audio from text and play it
  Future<void> speak(String text);

  /// Use local text-to-speech as a fallback
  Future<void> speakWithTts(String text);

  /// Clean up resources
  Future<void> dispose();

  /// Enable automatic listening mode
  Future<void> enableAutoMode();

  /// Disable automatic listening mode
  Future<void> disableAutoMode();

  /// Check if automatic listening mode is enabled
  bool get isAutoModeEnabled;
}

/// Represents the current state of audio recording
enum RecordingState {
  /// Not recording
  stopped,

  /// Currently recording
  recording,

  /// Processing the recorded audio
  processing,

  /// Error occurred during recording
  error
}
