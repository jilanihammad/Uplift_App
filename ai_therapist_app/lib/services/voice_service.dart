// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:mutex/mutex.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart'; // Import AppConfig
import 'package:audio_session/audio_session.dart';
import 'auto_listening_coordinator.dart';
import 'auto_listening_snapshot_source.dart';
import '../services/pipeline/voice_pipeline_controller.dart';
import 'vad_manager.dart';
import 'audio_player_manager.dart';
import 'recording_manager.dart';
import 'audio_recording_service.dart';
import 'base_voice_service.dart' as base_voice;
import 'path_manager.dart';
import '../di/interfaces/i_audio_settings.dart';
import 'config_service.dart';
import 'gemini_live_duplex_controller.dart';
import '../di/dependency_container.dart';
class FileCleanupManager {
  static final Set<String> _deletingFiles = <String>{};
  static Future<void> safeDelete(String filePath) async {
    if (_deletingFiles.contains(filePath)) {
      return;
    }
    _deletingFiles.add(filePath);
    try {
      final file = io.File(filePath);
      if (await file.exists()) {
        await file.delete();
      } else {
      }
    } catch (e) {
    } finally {
      _deletingFiles.remove(filePath);
    }
  }
}
enum TranscriptionModel { gpt4oMini, deepgramAI, assembly }
Future<Map<String, dynamic>> processAudioFileInIsolate(
    Map<String, dynamic> args) async {
  final String recordedFilePath = args['recordedFilePath'] as String;
  final file = io.File(recordedFilePath);
  bool fileExists = await file.exists();
  if (!fileExists) {
    return {'error': 'Audio file does not exist at path: $recordedFilePath'};
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return {'error': 'Audio file is empty.'};
  }
  String base64Audio = base64Encode(bytes);
  while (base64Audio.length % 4 != 0) {
    base64Audio += '=';
  }
  return {
    'base64Audio': base64Audio,
    'fileSize': bytes.length,
  };
}
class PlaybackException implements Exception {
  final String message;
  PlaybackException(this.message);
  @override
  String toString() => 'PlaybackException: $message';
}
class VoiceService {
  static VoiceService? _instance;
  final Mutex _ttsLock = Mutex();
  String? _lastPlayedFile;
  Timer? _playbackDebounceTimer;
  Stream<base_voice.RecordingState> get recordingState =>
      _audioRecordingService.recordingStateStream;
  String? _csmPath;
  final int _userSpeakerId = 0; // Speaker A
  final int _aiSpeakerId = 1; // Speaker B
  List<Map<String, dynamic>> _conversationContext = [];
  String? _lastGeneratedAudioPath;
  String?
      _recordingPath; // This might still be useful if VoiceService needs to know the last path
  final ApiClient _apiClient;
  final IAudioSettings? _audioSettings;
  late String _backendUrl;
  String get apiUrl => _backendUrl;
  final bool _isWeb = kIsWeb;
  bool _isInitialized = false;
  bool _disposed = false;
  Future<void>? _initFuture;
  final StreamController<bool> _audioPlaybackController =
      StreamController<bool>.broadcast();
  Stream<bool> get audioPlaybackStream => _audioPlaybackController.stream;
  final StreamController<bool> _ttsSpeakingStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get isTtsActuallySpeaking => _ttsSpeakingStateController.stream;
  bool isAiSpeaking = false;
  bool _currentTtsState = false;
  int? _currentPlaybackToken;
  int? _lastPlaybackToken;
  bool _ttsActive = false;
  bool _recordingActive = false;
  bool get isTtsActive => _ttsActive;
  bool get isRecordingActive =>
      _recordingActive ||
      _audioRecordingService.isRecording ||
      _autoListeningCoordinator.isRecording;
  int? get currentPlaybackToken => _currentPlaybackToken;
  int? get lastPlaybackToken => _lastPlaybackToken;
  bool Function()? canStartListeningCallback;
  bool Function()? _isVoiceModeCallback;
  bool Function()? get isVoiceModeCallback => _isVoiceModeCallback;
  set isVoiceModeCallback(bool Function()? callback) {
    _isVoiceModeCallback = callback;
    _autoListeningCoordinator.isVoiceModeCallback = callback;
  }
  bool Function()? _isSessionValidCallback;
  set isSessionValidCallback(bool Function()? callback) {
    _isSessionValidCallback = callback;
  }
  late final VADManager _vadManager;
  late final AutoListeningCoordinator _autoListeningCoordinator;
  AutoListeningSnapshotSource? _autoListeningSnapshot;
  late final AudioPlayerManager _audioPlayerManager;
  late final RecordingManager _recordingManager;
  late final AudioRecordingService _audioRecordingService;
  final ConfigService? _configService;
  final GeminiLiveDuplexController? _geminiDuplexController;
  StreamSubscription<GeminiLiveEvent>? _geminiEventSubscription;
  bool _geminiSessionActive = false;
  bool get _useGeminiLive =>
      (_configService?.geminiLiveDuplexEnabled ?? false) &&
      _geminiDuplexController != null;
  Stream<AutoListeningState> get autoListeningStateStream =>
      _autoListeningCoordinator.stateStream;
  Stream<bool> get autoListeningModeEnabledStream =>
      _autoListeningCoordinator.autoModeEnabledStream;
  AutoListeningState get autoListeningState =>
      _autoListeningCoordinator.currentState;
  bool get isAutoModeEnabled => _autoListeningCoordinator.autoModeEnabled;
  AutoListeningSnapshotSource? get autoListeningSnapshotSource =>
      _autoListeningSnapshot ??=
          AutoListeningCoordinatorSnapshotSource(_autoListeningCoordinator);
  dynamic get autoListeningVadManager => _autoListeningCoordinator.vadManager;
  bool get geminiLiveEnabled => _useGeminiLive;
  Future<void> enableAutoMode() async {
    await _voicePipelineController?.requestEnableAutoMode();
  }
  Future<void> disableAutoMode() async {
    await _voicePipelineController?.requestDisableAutoMode();
  }
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    await _voicePipelineController?.requestEnableAutoMode();
  }
  Future<void> initializeAutoListening() async {
  }
  void resetAutoListening({bool full = false, bool? preserveAutoMode}) {
  }
  void setAutoListeningRecordingCallback(
      void Function(String audioPath)? callback) {
    _autoListeningCoordinator.onRecordingCompleteCallback = callback;
  }
  void setAutoListeningTtsActivityStream(Stream<bool> stream) {
    _autoListeningCoordinator.setTtsActivityStream(stream);
  }
  void triggerListening() {
    _voicePipelineController?.requestTriggerListening();
  }
  Future<void> enableAutoModeWhenPlaybackCompletes({
    required int playbackToken,
  }) async {
    await _voicePipelineController?.requestEnableAutoMode();
  }
  factory VoiceService({
    required ApiClient apiClient,
    IAudioSettings? audioSettings,
  }) {
    if (_instance != null) {
      return _instance!;
    }
    _instance = VoiceService._internal(
      apiClient: apiClient,
      audioSettings: audioSettings,
    );
    return _instance!;
  }
  VoiceService._internal({
    required ApiClient apiClient,
    IAudioSettings? audioSettings,
  })  : _apiClient = apiClient,
        _audioSettings = audioSettings,
        _configService = GetIt.instance.isRegistered<ConfigService>()
            ? GetIt.instance<ConfigService>()
            : null,
        _geminiDuplexController =
            GetIt.instance.isRegistered<GeminiLiveDuplexController>()
                ? GetIt.instance<GeminiLiveDuplexController>()
                : null {
    _audioPlayerManager = AudioPlayerManager(audioSettings: audioSettings);
    _recordingManager = RecordingManager(); // Already initialized here
    _audioRecordingService = AudioRecordingService(
        recordingManager:
            _recordingManager); // Phase 2.1.1: Inject shared RecordingManager
    _vadManager = VADManager();
    _autoListeningCoordinator = AutoListeningCoordinator(
      audioPlayerManager: _audioPlayerManager,
      recordingManager: _recordingManager,
      voiceService: this,
    );
  }
  void attachPipelineController(VoicePipelineController? controller) {
    _voicePipelineController = controller;
  }
  VoicePipelineController? _voicePipelineController;
  bool get _controllerRecordingEnabled =>
      _voicePipelineController?.supportsRecording == true;
  bool get _controllerPlaybackEnabled =>
      _voicePipelineController?.supportsPlayback == true;
  bool get isInitialized => _isInitialized;
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
  Future<void> initialize() {
    if (_isInitialized) {
      return Future.value();
    }
    final existing = _initFuture;
    if (existing != null) {
      return existing;
    }
    _initFuture = _doInitialize();
    return _initFuture!;
  }
  Future<void> _doInitialize() async {
    try {
      _backendUrl = AppConfig().backendUrl;
      if (_isWeb) {
        _isInitialized = true;
        return;
      }
      _conversationContext = [];
      await _audioRecordingService.initialize();
      _isInitialized = true;
    } catch (e) {
      rethrow;
    } finally {
      _initFuture = null;
    }
  }
  Future<void> startRecording() async {
    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.startMicStream();
        _recordingActive = true;
      } catch (e) {
        rethrow;
      }
      return;
    }
    if (_isWeb) {
    }
    if (_controllerRecordingEnabled) {
      await _voicePipelineController?.requestStartRecording();
    }
    await _audioRecordingService.startRecording();
    _recordingActive = true;
  }
  Future<String?> stopRecording() async {
    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.stopMicStream();
      } catch (e) {}
      _recordingActive = false;
      return null;
    }
    String? recordedFilePath;
    if (!_isWeb) {
      try {
        if (_controllerRecordingEnabled) {
          recordedFilePath =
              await _voicePipelineController?.requestStopRecording();
        }
        recordedFilePath =
            recordedFilePath ?? await _audioRecordingService.stopRecording();
        _recordingPath = recordedFilePath;
        _recordingActive = false;
      } on NotRecordingException catch (e) {
        _recordingActive = false;
        return null;
      } catch (e) {
        rethrow;
      }
    }
    _recordingActive = _audioRecordingService.isRecording ||
        _autoListeningCoordinator.isRecording;
    return recordedFilePath;
  }
  Future<String?> tryStopRecording() async {
    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.stopMicStream();
      } catch (e) {}
      _recordingActive = false;
      return null;
    }
    String? recordedFilePath;
    if (_audioRecordingService.isRecording ||
        _autoListeningCoordinator.isRecording) {
      recordedFilePath = await _audioRecordingService.tryStopRecording();
      _recordingPath = recordedFilePath;
      if (recordedFilePath != null && recordedFilePath.isNotEmpty) {
        try {
          _autoListeningCoordinator.onRecordingCompleteCallback
              ?.call(recordedFilePath);
        } catch (error, stack) {}
      }
    }
    _recordingActive = _audioRecordingService.isRecording ||
        _autoListeningCoordinator.isRecording;
    return recordedFilePath;
  }
  Future<void> startGeminiLiveSession({String? userId}) async {
    if (!_useGeminiLive) {
      return;
    }
    if (_geminiSessionActive) {
      return;
    }
    try {
      await _geminiDuplexController!.connect(userId: userId);
      _setupGeminiEventSubscription();
      _geminiSessionActive = true;
    } catch (e) {
      rethrow;
    }
  }
  Future<void> stopGeminiLiveSession() async {
    if (!_useGeminiLive) {
      return;
    }
    _geminiSessionActive = false;
    await _geminiDuplexController?.disconnect();
    await _geminiEventSubscription?.cancel();
    _geminiEventSubscription = null;
    _setAiSpeaking(false);
  }
  Future<void> sendGeminiLiveText(String text,
      {bool turnComplete = false}) async {
    if (!_useGeminiLive) {
      throw StateError('Gemini Live duplex mode is disabled');
    }
    await _geminiDuplexController?.sendText(text, turnComplete: turnComplete);
  }
  Stream<GeminiLiveEvent> get geminiLiveEventStream =>
      _geminiDuplexController?.events ?? const Stream<GeminiLiveEvent>.empty();
  void _setupGeminiEventSubscription() {
    _geminiEventSubscription?.cancel();
    if (_geminiDuplexController == null) {
      return;
    }
    _geminiEventSubscription = _geminiDuplexController!.events.listen((event) {
      if (event is GeminiLiveAudioStartedEvent) {
        _setAiSpeaking(true);
      } else if (event is GeminiLiveAudioCompletedEvent ||
          event is GeminiLiveDisconnectedEvent) {
        _setAiSpeaking(false);
      } else if (event is GeminiLiveErrorEvent) {
      }
    });
  }
  Future<String> processRecordedAudioFile(String recordedFilePath) async {
    if (_useGeminiLive) {
      return '';
    }
    if (recordedFilePath.isEmpty) {
      return "Error: No audio file path provided.";
    }
    try {
      final result = await compute(
          processAudioFileInIsolate, {'recordedFilePath': recordedFilePath});
      if (result['error'] != null) {
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: ${result['error']} Please try again.";
      }
      final String base64Audio = result['base64Audio'];
      final int fileSize = result['fileSize'];
      try {
        final startTime = DateTime.now();
        final response = await _transcribeWithCustomTimeout({
          'audio_data': base64Audio,
          'audio_format': 'm4a',
          'model': 'gpt-4o-mini-transcribe'
        });
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        final transcription = response['text'] as String;
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return transcription.isNotEmpty ? transcription : "";
      } catch (e) {
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: Unable to transcribe audio. Please try again.";
      }
    } catch (e) {
      try {
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        final file = io.File(recordedFilePath);
        if (await file.exists()) {
          await FileCleanupManager.safeDelete(recordedFilePath);
        }
      } catch (delErr) {}
      return "Error: Problem processing audio. Please try again.";
    }
  }
  // Note: File deletion is now handled by FileCleanupManager.safeDelete
  Future<dynamic> _transcribeWithCustomTimeout(
      Map<String, dynamic> body) async {
    try {
      const transcriptionTimeout = Duration(seconds: 45);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await http
          .post(
            Uri.parse('$_backendUrl/voice/transcribe'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(transcriptionTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'Transcription API returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
  Future<void> playAudio(String audioPath) async {
    _audioPlaybackController.add(true);
    if (_controllerPlaybackEnabled) {
      await _voicePipelineController!.requestPlayAudio(audioPath);
      return;
    }
    try {
      await _audioPlayerManager.stopAudio();
      final session = await AudioSession.instance;
      final focusGranted = await session.setActive(true);
      if (!focusGranted) {
        _audioPlaybackController.add(false);
        return;
      } else {
      }
      session.becomingNoisyEventStream.listen((_) {
        stopAudio();
      });
      session.interruptionEventStream.listen((event) {
        if (event.begin) stopAudio();
      });
      if (audioPath.startsWith('local_tts://')) {
        await _useTtsBackup();
        _audioPlaybackController
            .add(false); // Signal general audio playback ended
        return;
      }
      if (audioPath.startsWith('http')) {
        if (!_isWeb) {
          try {
            final localPath = await _downloadAndCacheAudio(audioPath);
            if (localPath != null) {
              await _audioPlayerManager.playAudio(localPath);
              _audioPlayerManager.isPlayingStream.listen((isPlaying) {
                _audioPlaybackController.add(isPlaying);
              });
            } else {
              throw Exception('Failed to download audio from URL');
            }
          } catch (e) {
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS if URL play fails
          }
        } else {
          await Future.delayed(const Duration(seconds: 2));
          _audioPlaybackController.add(false);
        }
      } else if (!_isWeb) {
        final file = io.File(audioPath);
        if (await file.exists()) {
          try {
            await _audioPlayerManager.playAudio(audioPath);
            _audioPlayerManager.isPlayingStream.listen((isPlaying) {
              _audioPlaybackController.add(isPlaying);
            });
          } catch (e) {
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS
          }
        } else {
          _audioPlaybackController.add(false);
          await _useTtsBackup();
        }
      } else {
        _audioPlaybackController.add(false);
        await _useTtsBackup();
      }
    } catch (e) {
      _audioPlaybackController.add(false);
      await _useTtsBackup(); // Fallback to TTS on any error
    }
  }
  Future<void> stopAudio() async {
    if (_controllerPlaybackEnabled) {
      _audioPlaybackController.add(false);
      await _voicePipelineController!.requestStopAudio(clearQueue: true);
      return;
    }
    try {
      _audioPlaybackController.add(false);
      await _audioPlayerManager.stopAudio();
      _audioPlayerManager
          .forceStopState(); // Force the state to false immediately
    } catch (e) {
      try {
        _audioPlaybackController.add(false);
        _audioPlayerManager.forceStopState(); // Force stop even on error
      } catch (_) {}}
  }
  Future<String?> _downloadAndCacheAudio(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final cacheDir = PathManager.instance.cacheDir;
      final filePath = p.join(cacheDir, fileName);
      final file = io.File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }
  Future<void> _useTtsBackup() async {
    try {
      String textToSpeak =
          "I'm sorry, I couldn't play the audio right now."; // Default error
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedText = prefs.getString('last_tts_text');
        if (savedText != null && savedText.isNotEmpty) {
          textToSpeak = savedText;
        }
      } catch (e) {}
    } catch (e) {}
  }
  Future<void> playStreamingAudio(String audioUrl) async {
    try {
      if (_isWeb) {
        await playAudio(audioUrl);
        return;
      }
      try {
        final response = await http.head(Uri.parse(audioUrl));
        if (response.statusCode != 200) {
          await _useTtsBackup();
          return;
        }
      } catch (e) {
        await _useTtsBackup();
        return;
      }
      final player = AudioPlayer();
      try {
        await player.setAudioSource(
          ProgressiveAudioSource(
            Uri.parse(audioUrl),
            headers: {
              'Range': 'bytes=0-'
            }, // Request range to enable progressive playback
          ),
          preload: false, // Don't preload the entire audio file
        );
        final playbackStartTime = DateTime.now();
        await player.play();
        await player.processingStateStream.firstWhere(
          (state) => state == ProcessingState.completed,
        );
      } catch (e) {
        try {
          await playAudio(audioUrl);
        } catch (fallbackError) {
          await _useTtsBackup();
        }
      } finally {
        await player.dispose();
      }
    } catch (e) {
      await _useTtsBackup();
    }
  }
  Future<bool> isPlaying() async {
    try {
      final player = AudioPlayer();
      final isPlaying = player.playing;
      await player.dispose();
      return isPlaying;
    } catch (e) {
      return false;
    }
  }
  void dispose() {
    _disposed = true;
    _ttsActive = false;
    _currentTtsState = false;
    _currentPlaybackToken = null;
    _lastPlaybackToken = null;
    _recordingActive = false;
    if (_useGeminiLive) {
      unawaited(stopGeminiLiveSession());
    }
    _playbackDebounceTimer?.cancel();
    if (!_audioPlaybackController.isClosed) {
      _audioPlaybackController.close();
    }
    if (!_ttsSpeakingStateController.isClosed) {
      _ttsSpeakingStateController.close();
    }
    _recordingManager.dispose();
    _audioRecordingService.dispose();
    if (!_isWeb &&
        _lastGeneratedAudioPath != null &&
        !_lastGeneratedAudioPath!.startsWith('http')) {
      try {
        final file = io.File(_lastGeneratedAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {}
    }
  }
  AudioPlayerManager getAudioPlayerManager() {
    return _audioPlayerManager;
  }
  RecordingManager getRecordingManager() {
    return _recordingManager;
  }
  // CRITICAL FIX: Method to play audio with debounce to prevent duplicate calls
  Future<void> playAudioWithCallbacks(
    String filePath, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    if (_lastPlayedFile == filePath) {
      onDone?.call();
      return;
    }
    _playbackDebounceTimer?.cancel();
    _lastPlayedFile = filePath;
    _setAiSpeaking(true);
    try {
      await _audioPlayerManager.playAudio(filePath);
      onDone?.call();
    } catch (e) {
      onError?.call('Error playing audio: ${e.toString()}');
    } finally {
      _setAiSpeaking(false);
      _playbackDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        _lastPlayedFile = null;
      });
    }
  }
  void _setAiSpeaking(bool speaking) {
    isAiSpeaking = speaking;
    _ttsActive = speaking;
    _ttsSpeakingStateController.add(speaking);
  }
  void updateTTSSpeakingState(bool isSpeaking, {int? playbackToken}) {
    final guarded = _ttsLock.protect(() async {
      final tokenChanged =
          playbackToken != null && playbackToken != _currentPlaybackToken;
      if (!tokenChanged && _currentTtsState == isSpeaking) {
        return;
      }
      if (isSpeaking && playbackToken != null) {
        _currentPlaybackToken = playbackToken;
        unawaited(enableAutoModeWhenPlaybackCompletes(
          playbackToken: playbackToken,
        ));
      }
      if (!isSpeaking && playbackToken != null) {
        if (_currentPlaybackToken != null &&
            playbackToken != _currentPlaybackToken) {
          return;
        }
      }
      _currentTtsState = isSpeaking; // Update tracked state
      _setAiSpeaking(isSpeaking);
      if (isSpeaking) {
        await _drainRecordingBeforePlayback();
      } else {
        await _handleTtsCompletion();
      }
    });
    unawaited(guarded.catchError((error, stackTrace) {
    }));
  }
  Future<void> _drainRecordingBeforePlayback() async {
    if (isRecordingActive) {
      try {
        await tryStopRecording();
      } catch (e, stack) {}
    }
    _autoListeningCoordinator.stopListening();
  }
  Future<void> _handleTtsCompletion() async {
    final completedPlaybackToken = _currentPlaybackToken;
    if (completedPlaybackToken != null) {
      _lastPlaybackToken = completedPlaybackToken;
    }
    _currentPlaybackToken = null;
    if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
      return;
    }
  }
  Future<void> pauseVAD() async {
  }
  Future<void> resumeVAD() async {
  }
  bool get hasPendingOrActiveTts {
    try {
      return DependencyContainer().ttsService.hasPendingOrActiveTts;
    } catch (e) {
      return _currentTtsState;
    }
  }
  void resetTTSState() {
    _currentTtsState = false;
    _currentPlaybackToken = null;
    _lastPlaybackToken = null;
    _setAiSpeaking(false);
  }
  Future<void> setSpeakerMuted(bool muted) async {
    if (_audioSettings != null) {
      _audioSettings!.setMuted(muted);
    } else {
      final volume = muted ? 0.0 : 1.0;
      await _audioPlayerManager.setVolume(volume);
    }
  }
}
