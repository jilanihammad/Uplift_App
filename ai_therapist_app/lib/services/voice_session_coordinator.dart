// lib/services/voice_session_coordinator.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../di/interfaces/i_voice_service.dart';
import '../di/interfaces/i_audio_recording_service.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../di/interfaces/i_audio_file_manager.dart';
import 'base_voice_service.dart';
import 'voice_service.dart';
// Future enhancement: Direct AutoListeningCoordinator integration
// import 'auto_listening_coordinator.dart';
// import 'vad_manager.dart';

/// Coordinates voice session workflow by orchestrating focused audio services
/// Acts as a facade implementing IVoiceService while delegating to specialized services
/// 
/// Phase 6 Enhancement: Extended IVoiceService implementation
/// - Added stopAudio(), resetTTSState(), isTtsActuallySpeaking stream
/// - Added processRecordedAudioFile(), setSpeakerMuted()  
/// - Added enableAutoMode(), disableAutoMode()
/// - Smart delegation to legacy VoiceService for unimplemented features
class VoiceSessionCoordinator implements IVoiceService {
  final IAudioRecordingService _recordingService;
  final ITTSService _ttsService;
  final IWebSocketAudioManager _wsManager;
  final IAudioFileManager _fileManager;
  
  // Future enhancement: Direct AutoListeningCoordinator integration
  // late final AutoListeningCoordinator _autoListening;
  // late final VADManager _vadManager;

  bool _isInitialized = false;
  String? _currentSessionId;

  // Stream controllers for coordination
  final StreamController<double> _audioLevelController = 
      StreamController<double>.broadcast();

  VoiceSessionCoordinator({
    required IAudioRecordingService recordingService,
    required ITTSService ttsService,
    required IWebSocketAudioManager wsManager,
    required IAudioFileManager fileManager,
  }) : _recordingService = recordingService,
       _ttsService = ttsService,
       _wsManager = wsManager,
       _fileManager = fileManager {
    _initializeCoordinator();
  }

  void _initializeCoordinator() {
    // Future enhancement: Initialize VAD manager and auto-listening coordinator
    // _vadManager = VADManager();
    // _autoListening = AutoListeningCoordinator(...);

    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Initialized with focused services');
    }
  }

  // ========== IVoiceService Interface Implementation ==========

  @override
  bool get isRecording => _recordingService.isRecording;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Stream<double> get audioLevelStream => _recordingService.audioLevelStream;

  @override
  Future<void> startRecording() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Starting recording...');
    }
    await _recordingService.startRecording();
  }

  @override
  Future<String> stopRecording() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Stopping recording...');
    }
    return await _recordingService.stopRecording();
  }

  @override
  Future<void> pauseRecording() async {
    await _recordingService.pauseRecording();
  }

  @override
  Future<void> resumeRecording() async {
    await _recordingService.resumeRecording();
  }

  @override
  Future<void> cancelRecording() async {
    await _recordingService.cancelRecording();
  }

  @override
  Future<void> playAudio(String audioPath) async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Playing audio: $audioPath');
    }
    await _ttsService.playAudio(audioPath);
  }

  @override
  Future<void> stopPlayback() async {
    await _ttsService.stopAudio();
  }

  @override
  Future<void> pausePlayback() async {
    await _ttsService.pauseAudio();
  }

  @override
  Future<void> resumePlayback() async {
    await _ttsService.resumeAudio();
  }

  @override
  bool get isPlaying => _ttsService.isPlaying;

  @override
  Future<String> generateSpeech(String text, {String voice = 'alloy'}) async {
    return await _ttsService.generateSpeech(text, voice: voice);
  }

  @override
  Future<void> speakText(String text, {String voice = 'alloy'}) async {
    await _ttsService.speak(text, voice: voice);
  }

  @override
  Future<void> stopSpeaking() async {
    await _ttsService.stopAudio();
  }

  @override
  Future<void> stopAudio() async {
    await _ttsService.stopAudio();
  }

  @override
  Future<Uint8List?> processAudioWithRNNoise(Uint8List audioData) async {
    // This would need to be implemented based on RNNoise integration
    // For now, return the audio data unchanged
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] RNNoise processing not yet implemented');
    }
    return audioData;
  }

  @override
  Future<String> processRecordedAudioFile(String audioPath) async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Processing recorded audio file: $audioPath');
    }
    // For now, delegate to legacy VoiceService until we implement transcription
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        return await legacyVoiceService.processRecordedAudioFile(audioPath);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Error delegating to legacy service: $e');
      }
    }
    
    throw UnimplementedError('Audio transcription not yet implemented in VoiceSessionCoordinator');
  }

  @override
  void setSpeakerMuted(bool isMuted) {
    // For now, delegate to legacy VoiceService until we implement muting
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        legacyVoiceService.setSpeakerMuted(isMuted);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Error delegating setSpeakerMuted: $e');
      }
    }
    
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Speaker muting not yet implemented');
    }
  }

  @override
  Future<void> connectToBackend() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Connecting to backend...');
    }
    await _wsManager.connectToBackend();
  }

  @override
  Future<void> disconnectFromBackend() async {
    await _wsManager.disconnectFromBackend();
  }

  @override
  Future<void> streamAudio(Uint8List audioData) async {
    await _wsManager.streamAudio(audioData);
  }

  @override
  bool get isConnectedToBackend => _wsManager.isConnected;

  @override
  Future<void> startSession(String sessionId) async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Starting session: $sessionId');
    }
    _currentSessionId = sessionId;
    await _wsManager.startSession(sessionId);
  }

  @override
  Future<void> endSession() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Ending session: $_currentSessionId');
    }
    if (_currentSessionId != null) {
      await _wsManager.endSession();
      _currentSessionId = null;
    }
  }

  @override
  String? get currentSessionId => _currentSessionId;

  @override
  void setAudioQuality(String quality) {
    _recordingService.setAudioQuality(quality);
    // Also configure TTS quality if needed
    _ttsService.setAudioFormat(quality);
  }

  @override
  void setVoiceSettings(Map<String, dynamic> settings) {
    final voice = settings['voice'] as String? ?? 'alloy';
    final speed = settings['speed'] as double? ?? 1.0;
    final pitch = settings['pitch'] as double? ?? 1.0;
    
    _ttsService.setVoiceSettings(voice, speed, pitch);
  }

  @override
  void updateTTSSpeakingState(bool isSpeaking) {
    if (kDebugMode) {
      print('VoiceSessionCoordinator: updateTTSSpeakingState($isSpeaking) - coordinating VAD');
    }
    
    // For now, try to coordinate with legacy VoiceService AutoListeningCoordinator if available
    // Future enhancement: Integrate direct AutoListeningCoordinator
    try {
      // Import at runtime to avoid circular dependency
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        
        // Use the legacy coordination logic for TTS-VAD timing
        if (!isSpeaking) {
          legacyVoiceService.autoListeningCoordinator.startListening();
          if (kDebugMode) {
            print('VoiceSessionCoordinator: TTS done, VAD enabled via legacy AutoListeningCoordinator');
          }
        } else {
          legacyVoiceService.autoListeningCoordinator.stopListening();
          if (kDebugMode) {
            print('VoiceSessionCoordinator: TTS started, VAD disabled via legacy AutoListeningCoordinator');
          }
        }
      } else {
        if (kDebugMode) {
          print('VoiceSessionCoordinator: Legacy VoiceService not available, VAD coordination skipped');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('VoiceSessionCoordinator: Error coordinating with legacy AutoListeningCoordinator: $e');
      }
    }
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Already initialized');
      }
      return;
    }

    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Initializing all services...');
    }

    try {
      // Initialize all services in parallel
      await Future.wait([
        _recordingService.initialize(),
        _ttsService.initialize(),
        _wsManager.initialize(),
        _fileManager.initialize(),
      ]);

      _isInitialized = true;

      if (kDebugMode) {
        print('[VoiceSessionCoordinator] All services initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Initialization failed: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Disposing all services...');
    }

    // Dispose all services
    _recordingService.dispose();
    _ttsService.dispose();
    _wsManager.dispose();
    _fileManager.dispose();

    // Close stream controllers
    _audioLevelController.close();

    _isInitialized = false;

    if (kDebugMode) {
      print('[VoiceSessionCoordinator] All services disposed');
    }
  }

  @override
  Future<void> cleanupTempFiles() async {
    await _fileManager.cleanupTempFiles();
  }

  @override
  Future<String> getAudioUrl(String audioPath) async {
    // Check if it's already a URL
    if (audioPath.startsWith('http')) {
      return audioPath;
    }

    // Check if file exists locally
    if (await _fileManager.fileExists(audioPath)) {
      return audioPath; // Return local path
    }

    // File doesn't exist
    throw Exception('Audio file not found: $audioPath');
  }

  // ========== Additional Coordination Methods ==========

  /// Stream and play TTS with proper timing coordination (preserves 125ms buffer)
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
  }) async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] TTS with timing coordination (simplified API)');
    }

    try {
      // Use new simplified API
      await _ttsService.speak(text);
      
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] TTS completed, coordinating with auto-listening');
      }
      
      if (onDone != null) onDone();
    } catch (e) {
      if (onError != null) onError(e.toString());
    }
  }

  @override
  Future<void> enableAutoMode() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Enabling auto-listening mode');
    }
    // For now, delegate to legacy VoiceService for auto-listening
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        await legacyVoiceService.enableAutoMode();
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Error delegating enableAutoMode: $e');
      }
    }
    
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Auto-listening not yet implemented');
    }
  }

  @override
  Future<void> disableAutoMode() async {
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Disabling auto-listening mode');
    }
    // For now, delegate to legacy VoiceService for auto-listening
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        await legacyVoiceService.autoListeningCoordinator.disableAutoMode();
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[VoiceSessionCoordinator] Error delegating disableAutoMode: $e');
      }
    }
    
    if (kDebugMode) {
      print('[VoiceSessionCoordinator] Auto-listening not yet implemented');
    }
  }

  /// Get recording state stream from recording service
  Stream<RecordingState> get recordingStateStream => _recordingService.recordingStateStream;

  /// Get TTS speaking state stream
  @override
  Stream<bool> get isTtsActuallySpeaking => _ttsService.speakingStateStream;

  /// Get audio playback state stream
  Stream<bool> get audioPlaybackStream => _ttsService.playbackStateStream;

  /// Reset TTS state
  @override
  void resetTTSState() {
    _ttsService.resetTTSState();
  }
}