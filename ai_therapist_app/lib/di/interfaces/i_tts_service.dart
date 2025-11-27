// lib/di/interfaces/i_tts_service.dart

import 'dart:async';

/// Interface for Text-to-Speech service operations
/// Handles speech generation, streaming, and playback functionality
abstract class ITTSService {
  // Primary TTS method - simple and clean API
  Future<void> speak(String text,
      {String? voice, String format = 'auto', bool makeBackupFile = true});

  // TTS generation (legacy)
  Future<String> generateSpeech(String text, {String? voice});
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  });

  // Streaming with intelligent chunking
  Future<void> streamAndPlayTTSChunked(
    Stream<String> textStream, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  });

  // Playback controls
  Future<void> playAudio(String audioPath);
  Future<void> stopAudio();
  Future<void> pauseAudio();
  Future<void> resumeAudio();

  // Stream management
  Future<void> cancelAllStreams();

  // State management
  bool get isPlaying;
  bool get isSpeaking;
  bool get hasPendingOrActiveTts; // Race condition guard for reset operations
  Stream<bool> get playbackStateStream;
  Stream<bool> get speakingStateStream;

  // Audio configuration
  void setVoiceSettings(String voice, double speed, double pitch);
  void setAudioFormat(String format);

  // State control
  void resetTTSState();
  void setAiSpeaking(bool speaking);

  // Initialization and cleanup
  Future<void> initialize();
  void dispose();

  // Audio utilities
  Future<String?> downloadAndCacheAudio(String url);
  Future<void> cleanupAudioFiles();
}
