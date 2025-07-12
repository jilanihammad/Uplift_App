// lib/di/interfaces/i_voice_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:ai_therapist_app/services/auto_listening_coordinator.dart';

/// Interface for voice service operations
/// Provides contract for all voice-related functionality
abstract class IVoiceService {
  // Recording state
  bool get isRecording;
  bool get isInitialized;
  Stream<double> get audioLevelStream;
  
  // Recording operations
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<void> cancelRecording();
  
  // Audio playback
  Future<void> playAudio(String audioPath);
  Future<void> stopPlayback();
  Future<void> stopAudio(); // Legacy compatibility
  Future<void> pausePlayback();
  Future<void> resumePlayback();
  bool get isPlaying;
  
  // Text-to-Speech
  Future<String> generateSpeech(String text, {String voice = 'alloy'});
  Future<void> speakText(String text, {String voice = 'alloy'});
  Future<void> stopSpeaking();
  
  // TTS State Management (for auto-listening coordination)
  void updateTTSSpeakingState(bool isSpeaking);
  Stream<bool> get isTtsActuallySpeaking;
  void resetTTSState();
  
  // Audio processing
  Future<Uint8List?> processAudioWithRNNoise(Uint8List audioData);
  Future<String> processRecordedAudioFile(String audioPath);
  
  // WebSocket streaming
  Future<void> connectToBackend();
  Future<void> disconnectFromBackend();
  Future<void> streamAudio(Uint8List audioData);
  bool get isConnectedToBackend;
  
  // Session management
  Future<void> startSession(String sessionId);
  Future<void> endSession();
  String? get currentSessionId;
  
  // Configuration
  void setAudioQuality(String quality);
  void setVoiceSettings(Map<String, dynamic> settings);
  void setSpeakerMuted(bool isMuted);
  
  // Auto-listening mode
  Future<void> enableAutoMode();
  Future<void> disableAutoMode();
  AutoListeningCoordinator get autoListeningCoordinator;
  
  // Lifecycle
  Future<void> initialize();
  Future<void> initializeOnlyIfNeeded();
  void dispose();
  
  // File management
  Future<void> cleanupTempFiles();
  Future<String> getAudioUrl(String audioPath);
}