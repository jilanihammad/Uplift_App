// lib/services/voice_session_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../di/interfaces/i_voice_service.dart';
import '../di/interfaces/i_audio_recording_service.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../di/interfaces/i_audio_file_manager.dart';
import '../utils/disposable.dart';
import 'base_voice_service.dart';
import 'voice_service.dart';
import 'auto_listening_coordinator.dart' show AutoListeningState;
import 'auto_listening_snapshot_source.dart';
import '../config/llm_config.dart';
class VoiceSessionCoordinator with SessionDisposable implements IVoiceService {
  final IAudioRecordingService _recordingService;
  final ITTSService _ttsService;
  final IWebSocketAudioManager _wsManager;
  final IAudioFileManager _fileManager;
  bool _isInitialized = false;
  String? _currentSessionId;
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  VoiceSessionCoordinator({
    required IAudioRecordingService recordingService,
    required ITTSService ttsService,
    required IWebSocketAudioManager wsManager,
    required IAudioFileManager fileManager,
  })  : _recordingService = recordingService,
        _ttsService = ttsService,
        _wsManager = wsManager,
        _fileManager = fileManager {
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
    await _recordingService.startRecording();
  }
  @override
  Future<String> stopRecording() async {
    return await _recordingService.stopRecording();
  }
  @override
  Future<String?> tryStopRecording() async {
    return await _recordingService.tryStopRecording();
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
  bool get hasPendingOrActiveTts => _ttsService.hasPendingOrActiveTts;
  @override
  Future<String> generateSpeech(String text, {String? voice}) async {
    final selectedVoice = voice ?? LLMConfig.activeTTSVoice;
    return await _ttsService.generateSpeech(text, voice: selectedVoice);
  }
  @override
  Future<void> speakText(String text, {String? voice}) async {
    final selectedVoice = voice ?? LLMConfig.activeTTSVoice;
    await _ttsService.speak(text, voice: selectedVoice, makeBackupFile: false);
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
    return audioData;
  }
  @override
  Future<String> processRecordedAudioFile(String audioPath) async {
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        return await legacyVoiceService.processRecordedAudioFile(audioPath);
      }
    } catch (e) {}
    throw UnimplementedError(
        'Audio transcription not yet implemented in VoiceSessionCoordinator');
  }
  @override
  void setSpeakerMuted(bool isMuted) {
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        legacyVoiceService.setSpeakerMuted(isMuted);
        return;
      }
    } catch (e) {}
  }
  @override
  Future<void> connectToBackend() async {
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
    _currentSessionId = sessionId;
    await _wsManager.startSession(sessionId);
  }
  @override
  Future<void> endSession() async {
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
  void updateTTSSpeakingState(bool isSpeaking, {int? playbackToken}) {
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        final legacyVoiceService = serviceLocator<VoiceService>();
        // CRITICAL FIX: Update legacy TTS state so streams stay consistent
        legacyVoiceService.updateTTSSpeakingState(isSpeaking,
            playbackToken: playbackToken);
      } else {
      }
    } catch (e) {}
  }
  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    try {
      await Future.wait([
        _recordingService.initialize(),
        _ttsService.initialize(),
        _wsManager.initialize(),
        _fileManager.initialize(),
      ]);
      _isInitialized = true;
    } catch (e) {
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
    // IMPORTANT: Do not dispose the app-scoped WebSocketAudioManager here.
    try {
      _wsManager.endSession();
    } catch (_) {}
    try {
      _wsManager.disconnectFromBackend();
    } catch (_) {}
    _audioLevelController.close();
    _isInitialized = false;
    super.dispose();
  }
  @override
  void performDisposal() {
  }
  @override
  Future<void> cleanupTempFiles() async {
    await _fileManager.cleanupTempFiles();
  }
  @override
  Future<String> getAudioUrl(String audioPath) async {
    if (audioPath.startsWith('http')) {
      return audioPath;
    }
    if (await _fileManager.fileExists(audioPath)) {
      return audioPath; // Return local path
    }
    throw Exception('Audio file not found: $audioPath');
  }
  // ========== Additional Coordination Methods ==========
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
  }) async {
    try {
      await _ttsService.speak(text, makeBackupFile: false);
      if (onDone != null) onDone();
    } catch (e) {
      if (onError != null) onError(e.toString());
    }
  }
  VoiceService? _resolveLegacyVoiceService() {
    try {
      final serviceLocator = GetIt.instance;
      if (serviceLocator.isRegistered<VoiceService>()) {
        return serviceLocator<VoiceService>();
      }
    } catch (e) {}
    return null;
  }
  @override
  Future<void> enableAutoMode() async {
    final legacyVoiceService = _resolveLegacyVoiceService();
    if (legacyVoiceService != null) {
      await legacyVoiceService.enableAutoMode();
      return;
    }
  }
  @override
  Future<void> disableAutoMode() async {
    final legacyVoiceService = _resolveLegacyVoiceService();
    if (legacyVoiceService != null) {
      await legacyVoiceService.disableAutoMode();
      return;
    }
  }
  Stream<RecordingState> get recordingStateStream =>
      _recordingService.recordingStateStream;
  @override
  Stream<bool> get isTtsActuallySpeaking => _ttsService.speakingStateStream;
  Stream<bool> get audioPlaybackStream => _ttsService.playbackStateStream;
  @override
  void resetTTSState() {
    _ttsService.resetTTSState();
  }
  @override
  Future<void> initializeAutoListening() async {
    final legacyVoiceService = _resolveLegacyVoiceService();
    if (legacyVoiceService != null) {
      await legacyVoiceService.initializeAutoListening();
      return;
    }
  }
  @override
  void resetAutoListening({bool full = false, bool? preserveAutoMode}) {
    final legacyVoiceService = _resolveLegacyVoiceService();
    legacyVoiceService?.resetAutoListening(
        full: full, preserveAutoMode: preserveAutoMode);
  }
  @override
  void setAutoListeningRecordingCallback(
      void Function(String audioPath)? callback) {
    final legacyVoiceService = _resolveLegacyVoiceService();
    legacyVoiceService?.setAutoListeningRecordingCallback(callback);
  }
  @override
  void setAutoListeningTtsActivityStream(Stream<bool> stream) {
    final legacyVoiceService = _resolveLegacyVoiceService();
    legacyVoiceService?.setAutoListeningTtsActivityStream(stream);
  }
  @override
  AutoListeningState get autoListeningState {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.autoListeningState ?? AutoListeningState.idle;
  }
  @override
  Stream<AutoListeningState> get autoListeningStateStream {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.autoListeningStateStream ?? const Stream.empty();
  }
  @override
  Stream<bool> get autoListeningModeEnabledStream {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.autoListeningModeEnabledStream ??
        const Stream.empty();
  }
  @override
  bool get isAutoModeEnabled {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.isAutoModeEnabled ?? false;
  }
  @override
  AutoListeningSnapshotSource? get autoListeningSnapshotSource {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.autoListeningSnapshotSource;
  }
  @override
  dynamic get autoListeningVadManager {
    final legacyVoiceService = _resolveLegacyVoiceService();
    return legacyVoiceService?.autoListeningVadManager;
  }
  @override
  void triggerListening() {
    final legacyVoiceService = _resolveLegacyVoiceService();
    legacyVoiceService?.triggerListening();
  }
}
