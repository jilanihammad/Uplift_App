// lib/di/interfaces/i_voice_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:ai_therapist_app/services/auto_listening_coordinator.dart'
    show AutoListeningState;
import 'package:ai_therapist_app/services/auto_listening_snapshot_source.dart';
abstract class IVoiceService {
  bool get isRecording;
  bool get isInitialized;
  Stream<double> get audioLevelStream;
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<String?> tryStopRecording(); // Thread-safe idempotent version
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<void> cancelRecording();
  Future<void> playAudio(String audioPath);
  Future<void> stopPlayback();
  Future<void> stopAudio(); // Legacy compatibility
  Future<void> pausePlayback();
  Future<void> resumePlayback();
  bool get isPlaying;
  Future<String> generateSpeech(String text, {String? voice});
  Future<void> speakText(String text, {String? voice});
  Future<void> stopSpeaking();
  void updateTTSSpeakingState(bool isSpeaking, {int? playbackToken});
  Stream<bool> get isTtsActuallySpeaking;
  bool get hasPendingOrActiveTts; // Race condition guard for reset operations
  void resetTTSState();
  Future<Uint8List?> processAudioWithRNNoise(Uint8List audioData);
  Future<String> processRecordedAudioFile(String audioPath);
  Future<void> connectToBackend();
  Future<void> disconnectFromBackend();
  Future<void> streamAudio(Uint8List audioData);
  bool get isConnectedToBackend;
  Future<void> startSession(String sessionId);
  Future<void> endSession();
  String? get currentSessionId;
  void setAudioQuality(String quality);
  void setVoiceSettings(Map<String, dynamic> settings);
  void setSpeakerMuted(bool isMuted);
  Future<void> enableAutoMode();
  Future<void> disableAutoMode();
  Future<void> initializeAutoListening();
  void resetAutoListening({bool full = false, bool? preserveAutoMode});
  void setAutoListeningRecordingCallback(
      void Function(String audioPath)? callback);
  void setAutoListeningTtsActivityStream(Stream<bool> stream);
  AutoListeningState get autoListeningState;
  Stream<AutoListeningState> get autoListeningStateStream;
  Stream<bool> get autoListeningModeEnabledStream;
  bool get isAutoModeEnabled;
  AutoListeningSnapshotSource? get autoListeningSnapshotSource;
  dynamic get autoListeningVadManager;
  void triggerListening();
  Future<void> initialize();
  Future<void> initializeOnlyIfNeeded();
  void dispose();
  Future<void> cleanupTempFiles();
  Future<String> getAudioUrl(String audioPath);
}
