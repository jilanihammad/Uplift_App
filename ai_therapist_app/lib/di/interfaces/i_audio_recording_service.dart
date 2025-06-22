// lib/di/interfaces/i_audio_recording_service.dart

import 'dart:async';
import '../../services/base_voice_service.dart';

/// Interface for audio recording service operations
/// Handles all audio recording functionality with proper state management
abstract class IAudioRecordingService {
  // Recording state
  bool get isRecording;
  Stream<RecordingState> get recordingStateStream;
  Stream<double> get audioLevelStream;
  bool get isInitialized;
  
  // Recording operations
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<void> cancelRecording();
  
  // Permission management
  Future<bool> requestMicrophonePermission();
  Future<bool> hasMicrophonePermission();
  
  // Configuration
  void setAudioQuality(String quality);
  void setRecordingSettings(Map<String, dynamic> settings);
  
  // Initialization and cleanup
  Future<void> initialize();
  void dispose();
  
  // File management
  String? get lastRecordingPath;
  Future<void> cleanupRecordingFiles();
}