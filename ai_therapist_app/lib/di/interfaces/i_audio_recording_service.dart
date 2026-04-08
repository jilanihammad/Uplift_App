// lib/di/interfaces/i_audio_recording_service.dart
import 'dart:async';
import 'dart:typed_data';
import '../../services/base_voice_service.dart';
abstract class IAudioRecordingService {
  bool get isRecording;
  Stream<RecordingState> get recordingStateStream;
  Stream<double> get audioLevelStream;
  bool get isInitialized;
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<String?> tryStopRecording(); // Thread-safe idempotent version
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<void> cancelRecording();
  Future<Stream<Uint8List>> startStreaming({int sampleRate = 24000, int numChannels = 1});
  Future<void> stopStreaming();
  Future<bool> requestMicrophonePermission();
  Future<bool> hasMicrophonePermission();
  void setAudioQuality(String quality);
  void setRecordingSettings(Map<String, dynamic> settings);
  Future<void> initialize();
  void dispose();
  String? get lastRecordingPath;
  Future<void> cleanupRecordingFiles();
}
