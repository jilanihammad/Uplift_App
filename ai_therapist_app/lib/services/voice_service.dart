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
import '../utils/app_logger.dart';
import 'audio_player_manager.dart';
import 'recording_manager.dart';
import 'audio_recording_service.dart';
import 'base_voice_service.dart' as base_voice;
import 'path_manager.dart';
import '../di/interfaces/i_audio_settings.dart';
import 'config_service.dart';
import 'gemini_live_duplex_controller.dart';
import '../di/dependency_container.dart';

/// File cleanup manager to prevent race conditions from multiple deletion attempts
class FileCleanupManager {
  static final Set<String> _deletingFiles = <String>{};

  /// Safely delete a file, preventing race conditions from multiple deletion attempts
  static Future<void> safeDelete(String filePath) async {
    if (_deletingFiles.contains(filePath)) {
      if (kDebugMode) {
        debugPrint('🗑️ File deletion already in progress for: $filePath');
      }
      return;
    }

    _deletingFiles.add(filePath);
    try {
      final file = io.File(filePath);
      if (await file.exists()) {
        await file.delete();
        if (kDebugMode) {
          debugPrint('🗑️ Successfully deleted file: $filePath');
        }
      } else {
        if (kDebugMode) {
          debugPrint('🗑️ File already deleted: $filePath');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🗑️ Error deleting file $filePath: $e');
      }
    } finally {
      _deletingFiles.remove(filePath);
    }
  }
}

// Recording states
// enum RecordingState { ready, recording, stopped, paused, error } // Now defined in base_voice_service.dart or RecordingManager

// Transcription models
enum TranscriptionModel { gpt4oMini, deepgramAI, assembly }

// Top-level function for Isolate file processing (must be outside any class for compute)
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

/// Exception class for playback errors
class PlaybackException implements Exception {
  final String message;
  PlaybackException(this.message);
  @override
  String toString() => 'PlaybackException: $message';
}

class VoiceService {
  // Singleton instance
  static VoiceService? _instance;

  // Mutex to prevent concurrent TTS operations
  final Mutex _ttsLock = Mutex();

  // NEW: Debounce mechanism to prevent duplicate playback calls
  String? _lastPlayedFile;
  Timer? _playbackDebounceTimer;

  // Stream controllers for voice recording states - REMOVED
  // StreamController<RecordingState>? _recordingStateController;
  // Stream<RecordingState>? _recordingStateStream;
  // Stream<RecordingState> get recordingState {
  //   _ensureStreamControllerIsActive();
  //   return _recordingStateStream!;
  // }
  // Phase 2.1.1: Expose AudioRecordingService's stream (delegates to RecordingManager)
  Stream<base_voice.RecordingState> get recordingState =>
      _audioRecordingService.recordingStateStream;

  // Current state of recording - REMOVED
  // RecordingState _currentState = RecordingState.ready;

  // Path to the CSM directory
  String? _csmPath;

  // Speaker IDs
  final int _userSpeakerId = 0; // Speaker A
  final int _aiSpeakerId = 1; // Speaker B

  // Audio context for the conversation
  List<Map<String, dynamic>> _conversationContext = [];

  // Generated audio path
  String? _lastGeneratedAudioPath;

  // Recording related - REMOVED
  // late final AudioRecorder _audioRecorder;
  String?
      _recordingPath; // This might still be useful if VoiceService needs to know the last path

  // API client for making requests to backend
  final ApiClient _apiClient;

  // Audio settings for global mute functionality
  final IAudioSettings? _audioSettings;

  // Backend server URL
  late String _backendUrl;

  // Getter for accessing backend URL from other services
  String get apiUrl => _backendUrl;

  // Flag to indicate if we're running in a web environment
  final bool _isWeb = kIsWeb;

  bool _isInitialized = false;
  bool _disposed = false;

  // Init-future coalescing: ensures concurrent callers await the same init
  Future<void>? _initFuture;

  // Stream controllers for audio playback states
  final StreamController<bool> _audioPlaybackController =
      StreamController<bool>.broadcast();
  Stream<bool> get audioPlaybackStream => _audioPlaybackController.stream;

  // Stream specifically for TTS speaking state - we keep this for API compatibility
  final StreamController<bool> _ttsSpeakingStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get isTtsActuallySpeaking => _ttsSpeakingStateController.stream;

  // REMOVED: AudioPlayer? _currentPlayer; // Consolidating to use only AudioPlayerManager

  bool isAiSpeaking = false;

  // RACE CONDITION FIX: Track current TTS state to prevent duplicate calls
  bool _currentTtsState = false;
  int? _currentPlaybackToken;
  int? _lastPlaybackToken;
  final Set<int> _autoModeWaitTokens = <int>{};
  bool _ttsActive = false;
  bool _recordingActive = false;
  bool _playbackActive = false;
  bool _playbackStartedForCurrentTts = false;
  StreamSubscription<bool>? _playbackActiveSub;
  bool get isTtsActive => _ttsActive;
  bool get isRecordingActive =>
      _recordingActive ||
      _audioRecordingService.isRecording ||
      _autoListeningCoordinator.isRecording;
  int? get currentPlaybackToken => _currentPlaybackToken;
  int? get lastPlaybackToken => _lastPlaybackToken;

  /// Callback for the bloc to veto automatic listening restarts while deferrals
  /// (like the initial welcome guard) are in effect.
  bool Function()? canStartListeningCallback;

  // BYPASS FIX: Callback to check if we're in voice mode and keep coordinator in sync
  bool Function()? _isVoiceModeCallback;
  bool Function()? get isVoiceModeCallback => _isVoiceModeCallback;
  set isVoiceModeCallback(bool Function()? callback) {
    _isVoiceModeCallback = callback;
    _autoListeningCoordinator.isVoiceModeCallback = callback;
  }

  // TIMING FIX: Callback to get current generation for TTS completion checks
  int Function()? getCurrentGeneration;

  // BATCH 2 PHASE 7: VoiceSessionBloc reference for session validity checks
  bool Function()? _isSessionValidCallback;
  set isSessionValidCallback(bool Function()? callback) {
    _isSessionValidCallback = callback;
  }

  // Add coordinator and VAD manager
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

  // Expose coordinator's streams
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

  // Passthrough methods for auto mode control
  Future<void> enableAutoMode() async {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] enableAutoMode called (using AudioPlayerManager state)');
    }
    if (_controllerAutoModeEnabled) {
      await _voicePipelineController?.requestEnableAutoMode();
      return;
    }
    await _autoListeningCoordinator.enableAutoMode();
  }

  Future<void> disableAutoMode() async {
    if (kDebugMode) debugPrint('[VoiceService] disableAutoMode() called');
    if (_controllerAutoModeEnabled) {
      await _voicePipelineController?.requestDisableAutoMode();
      return;
    }
    await _autoListeningCoordinator.disableAutoMode();
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] disableAutoMode() completed. autoModeEnabled=${_autoListeningCoordinator.autoModeEnabled}');
    }
  }

  // Enable auto mode with explicit audio state from Bloc
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] enableAutoModeWithAudioState called with isAudioPlaying=$isAudioPlaying');
    }
    if (_controllerAutoModeEnabled) {
      await _voicePipelineController?.requestEnableAutoMode();
      return;
    }
    await _autoListeningCoordinator
        .enableAutoModeWithAudioState(isAudioPlaying);
  }

  Future<void> initializeAutoListening() async {
    if (_controllerAutoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] initializeAutoListening skipped (controller auto mode active)');
      }
      return;
    }
    await _autoListeningCoordinator.initialize();
  }

  void resetAutoListening({bool full = false, bool? preserveAutoMode}) {
    if (_controllerAutoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] resetAutoListening skipped (controller auto mode active)');
      }
      return;
    }
    _autoListeningCoordinator.reset(
        full: full, preserveAutoMode: preserveAutoMode);
  }

  void setAutoListeningRecordingCallback(
      void Function(String audioPath)? callback) {
    // NOTE: Even when controller is "authoritative" for auto-mode, the
    // AutoListeningCoordinator still manages recordings. The callback must
    // be wired so recording completions reach the bloc.
    _autoListeningCoordinator.onRecordingCompleteCallback = callback;
  }

  void setAutoListeningTtsActivityStream(Stream<bool> stream) {
    // NOTE: Even when controller is active, AutoListeningCoordinator needs
    // the TTS stream to know when AI is speaking (for state machine transitions).
    _autoListeningCoordinator.setTtsActivityStream(stream);
  }

  void triggerListening() {
    if (_controllerAutoModeEnabled) {
      _voicePipelineController?.requestTriggerListening();
      return;
    }
    _autoListeningCoordinator.triggerListening();
  }

  Future<void> enableAutoModeWhenPlaybackCompletes({
    required int playbackToken,
  }) async {
    if (_controllerAutoModeEnabled) {
      await _voicePipelineController?.requestEnableAutoMode();
      return;
    }

    if (_disposed) {
      return;
    }

    if (!_autoModeWaitTokens.add(playbackToken)) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] enableAutoModeWhenPlaybackCompletes already scheduled for token $playbackToken');
      }
      return;
    }

    try {
      final capturedGeneration = getCurrentGeneration?.call();

      if (kDebugMode) {
        debugPrint(
            '[VoiceService] enableAutoModeWhenPlaybackCompletes called (generation=$capturedGeneration, token=$playbackToken, current=$_currentPlaybackToken, last=$_lastPlaybackToken)');
      }

      const postClearDelay = Duration(milliseconds: 100);
      const pollInterval = Duration(milliseconds: 200);
      const maxWaitDuration = Duration(seconds: 60); // Max wait for TTS playback
      var playbackCleared = false;

      // FIX: Use single long wait with state polling instead of short timeouts
      // This avoids race conditions where stream events are missed between subscriptions
      final startTime = DateTime.now();

      while (DateTime.now().difference(startTime) < maxWaitDuration) {
        // Check generation first
        final currentGeneration = getCurrentGeneration?.call();
        final generationChanged = (capturedGeneration != null &&
                currentGeneration != capturedGeneration) ||
            (capturedGeneration == null && currentGeneration != null);

        if (generationChanged) {
          if (kDebugMode) {
            debugPrint(
                '[VoiceService] Generation changed during playback wait (was $capturedGeneration, now $currentGeneration) – aborting auto-mode enable');
          }
          return;
        }

        // Check if playback completed (state-based, not stream-based)
        if (!_ttsActive && !_playbackActive) {
          // Verify token matches
          final activeToken = _currentPlaybackToken;
          final lastTokenSnapshot = _lastPlaybackToken;

          if (activeToken != null && activeToken != playbackToken) {
            if (kDebugMode) {
              debugPrint(
                  '[VoiceService] New playback detected (expected $playbackToken, active $activeToken) – aborting auto-mode enable');
            }
            return;
          }

          if (activeToken == null &&
              lastTokenSnapshot != null &&
              lastTokenSnapshot != playbackToken) {
            if (kDebugMode) {
              debugPrint(
                  '[VoiceService] Playback token mismatch after wait (expected $playbackToken, last $lastTokenSnapshot) – aborting auto-mode enable');
            }
            return;
          }

          playbackCleared = true;
          break;
        }

        // Poll at regular intervals instead of using stream subscriptions
        await Future.delayed(pollInterval);
      }

      if (!playbackCleared) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Playback wait timed out after ${maxWaitDuration.inSeconds}s – skipping auto mode enable');
        }
        return;
      }

      await Future.delayed(postClearDelay);

      final generationAfterDelay = getCurrentGeneration?.call();
      if (capturedGeneration != null &&
          generationAfterDelay != capturedGeneration) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Generation changed during post-delay check (was $capturedGeneration, now $generationAfterDelay) – skipping auto mode enable');
        }
        return;
      }

      if (_ttsActive || _playbackActive) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Playback resumed during post-delay check – skipping auto mode enable');
        }
        return;
      }

      if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Voice mode inactive after playback – skipping auto mode enable');
        }
        return;
      }

      if (_autoListeningCoordinator.autoModeEnabled) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Auto mode already enabled – no action needed');
        }
        return;
      }

      await enableAutoMode();
    } finally {
      _autoModeWaitTokens.remove(playbackToken);
    }
  }

  // Factory constructor to enforce singleton pattern
  factory VoiceService({
    required ApiClient apiClient,
    IAudioSettings? audioSettings,
  }) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        debugPrint('Reusing existing VoiceService instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = VoiceService._internal(
      apiClient: apiClient,
      audioSettings: audioSettings,
    );
    return _instance!;
  }

  // Private constructor for singleton pattern
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
    // _audioRecorder = AudioRecorder(); // REMOVED
    // _ensureStreamControllerIsActive(); // REMOVED, no local controller
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
    _playbackActiveSub =
        _audioPlayerManager.playbackActiveStream.listen((isActive) {
      _playbackActive = isActive;
      if (isActive) {
        _playbackStartedForCurrentTts = true;
      }
    });
    _playbackActive = _audioPlayerManager.isPlaybackActive;
    if (kDebugMode) {
      debugPrint('VoiceService initialized with constructor injection');
      debugPrint(
          '[VoiceService] AudioRecordingService added with shared RecordingManager - Phase 2.1.1 Hotfix');
      debugPrint(
          '[VoiceService] AutoListeningCoordinator initialized. Forcing auto mode enabled.');
    }
  }

  void attachPipelineController(VoicePipelineController? controller) {
    _voicePipelineController = controller;
  }

  VoicePipelineController? _voicePipelineController;

  bool get _controllerRecordingEnabled =>
      _voicePipelineController?.supportsRecording == true;
  bool get _controllerPlaybackEnabled =>
      _voicePipelineController?.supportsPlayback == true;
  bool get _controllerAutoModeEnabled =>
      _voicePipelineController?.supportsAutoMode == true;

  // Check if service is initialized
  bool get isInitialized => _isInitialized;

  // Method to initialize the service only if it hasn't been initialized yet
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // Method to initialize the voice service
  // Uses init-future coalescing to prevent duplicate initialization
  Future<void> initialize() {
    // Fast path: already initialized
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('VoiceService already initialized, skipping initialize()');
      }
      return Future.value();
    }

    // Coalescing: if init is in progress, return existing future so all callers await
    final existing = _initFuture;
    if (existing != null) {
      if (kDebugMode) {
        debugPrint('VoiceService init already in progress, awaiting existing future...');
      }
      return existing;
    }

    // Start new initialization and store the future for coalescing
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  // Internal initialization implementation
  Future<void> _doInitialize() async {
    try {
      // Get backend URL from AppConfig instead of hardcoding
      _backendUrl = AppConfig().backendUrl;

      if (kDebugMode) {
        debugPrint('[VoiceService] Starting initialization...');
      }

      // For web platform, use a simplified initialization
      if (_isWeb) {
        if (kDebugMode) {
          debugPrint('Initializing voice service in web mode');
        }
        _isInitialized = true;
        return;
      }

      // Reset the conversation context
      _conversationContext = [];

      // Phase 2.1.1: Initialize AudioRecordingService
      if (kDebugMode) {
        debugPrint('[VoiceService] Initializing AudioRecordingService...');
      }
      await _audioRecordingService.initialize();
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] AudioRecordingService initialized successfully');
      }

      // Mark as initialized ONLY after all steps complete successfully
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('[VoiceService] Initialization complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing voice service: $e');
      }
      // On failure: log + rethrow so callers see the failure
      // _isInitialized stays false, allowing retry on next call
      rethrow;
    } finally {
      // Clear the init future so next call can retry if needed
      _initFuture = null;
    }
  }

  // Start recording
  Future<void> startRecording() async {
    // Phase 2.1.1: Delegate to AudioRecordingService instead of RecordingManager directly
    if (kDebugMode) {
      debugPrint(
          '⏺️ VOICE DEBUG: VoiceService.startRecording called - delegating to AudioRecordingService');
    }

    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.startMicStream();
        _recordingActive = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [VoiceService] Failed to start Gemini mic stream: $e');
        }
        rethrow;
      }
      return;
    }

    if (_isWeb) {
      // Simulate recording in web mode - AudioRecordingService handles web compatibility
      if (kDebugMode) {
        debugPrint(
            'Recording started (web mode) - AudioRecordingService handles web compatibility');
      }
      // AudioRecordingService will handle web mode appropriately
    }

    // Phase 3A: delegate to pipeline controller when enabled
    if (_controllerRecordingEnabled) {
      await _voicePipelineController?.requestStartRecording();
    }

    // Phase 2.1.1: Delegate to AudioRecordingService (legacy path)
    await _audioRecordingService.startRecording();
    _recordingActive = true;

    // } catch (e) { // REMOVED
    //   _currentState = RecordingState.error;
    //   try {
    //     if (_recordingStateController != null &&
    //         !_recordingStateController!.isClosed) {
    //       _recordingStateController!.add(_currentState);
    //     }
    //   } catch (streamError) {
    //     if (kDebugMode) {
    //       debugPrint('❌ VOICE ERROR: Error sending state to stream: $streamError');
    //     }
    //   }
    //
    //   if (kDebugMode) {
    //     debugPrint('❌ VOICE ERROR: Error starting recording: $e');
    //   }
    //   if (!_isWeb) rethrow;
    // }
  }

  /// Stops the current recording session if active.
  ///
  /// Returns the path to the recorded file, or null if not recording.
  /// Throws [NotRecordingException] if called when not recording.
  Future<String?> stopRecording() async {
    if (kDebugMode) {
      debugPrint(
          '⏹️ VOICE DEBUG: VoiceService.stopRecording called - delegating to RecordingManager');
    }

    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.stopMicStream();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [VoiceService] Error stopping Gemini mic stream: $e');
        }
      }
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

        // Phase 2.1.1: Delegate to AudioRecordingService
        recordedFilePath =
            recordedFilePath ?? await _audioRecordingService.stopRecording();
        _recordingPath = recordedFilePath;
        _recordingActive = false;
      } on NotRecordingException catch (e) {
        if (kDebugMode) {
          debugPrint('⏹️ VOICE DEBUG: Not recording, nothing to stop. ($e)');
        }
        _recordingActive = false;
        return null;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⏹️ VOICE DEBUG: Error stopping recording: $e');
        }
        rethrow;
      }
    }
    _recordingActive = _audioRecordingService.isRecording ||
        _autoListeningCoordinator.isRecording;
    return recordedFilePath;
  }

  /// Thread-safe idempotent version of stopRecording that never throws
  /// Returns null if already stopped or not recording
  Future<String?> tryStopRecording() async {
    if (kDebugMode) {
      debugPrint(
          '⏹️ VOICE DEBUG: VoiceService.tryStopRecording called - delegating to AudioRecordingService');
    }

    if (_useGeminiLive) {
      try {
        await _geminiDuplexController!.stopMicStream();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '❌ [VoiceService] Error stopping Gemini mic stream (idempotent): $e');
        }
      }
      _recordingActive = false;
      return null;
    }

    String? recordedFilePath;
    if (_audioRecordingService.isRecording ||
        _autoListeningCoordinator.isRecording) {
      // Phase 2.1.1: Delegate to AudioRecordingService (idempotent version)
      recordedFilePath = await _audioRecordingService.tryStopRecording();
      _recordingPath = recordedFilePath;
      if (recordedFilePath != null && recordedFilePath.isNotEmpty) {
        try {
          _autoListeningCoordinator.onRecordingCompleteCallback
              ?.call(recordedFilePath);
        } catch (error, stack) {
          if (kDebugMode) {
            debugPrint('[VoiceService] Error forwarding recording completion: '
                '$error\n$stack');
          }
        }
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
      if (kDebugMode) {
        debugPrint('❌ [VoiceService] Failed to start Gemini Live session: $e');
      }
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
        if (kDebugMode) {
          debugPrint('❌ [VoiceService] Gemini Live error: ${event.message}');
        }
      }
    });
  }

  // New method to process an already recorded audio file
  Future<String> processRecordedAudioFile(String recordedFilePath) async {
    if (kDebugMode) {
      debugPrint(
          '⏹️ VOICE DEBUG: VoiceService.processRecordedAudioFile called with path: $recordedFilePath');
    }

    if (_useGeminiLive) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] processRecordedAudioFile bypassed - Gemini Live mode active');
      }
      return '';
    }

    if (recordedFilePath.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '❌ VOICE ERROR: processRecordedAudioFile: Empty file path provided.');
      }
      return "Error: No audio file path provided.";
    }

    try {
      // Use compute to offload file I/O and encoding
      final result = await compute(
          processAudioFileInIsolate, {'recordedFilePath': recordedFilePath});
      if (result['error'] != null) {
        if (kDebugMode) debugPrint('❌ VOICE ERROR: ${result['error']}');
        // RACE CONDITION FIX: Mark transcription complete even on file processing error
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: ${result['error']} Please try again.";
      }
      final String base64Audio = result['base64Audio'];
      final int fileSize = result['fileSize'];
      if (kDebugMode) {
        debugPrint(
            '⏹️ VOICE DEBUG: Audio file encoded in isolate, size: $fileSize bytes, base64 length: ${base64Audio.length}');
      }
      // Continue with API call as before
      try {
        final startTime = DateTime.now();
        if (kDebugMode) {
          debugPrint(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Making API call to transcribe audio...');
        }
        // Use custom timeout for transcription (longer than default 15s)
        final response = await _transcribeWithCustomTimeout({
          'audio_data': base64Audio,
          'audio_format': 'm4a',
          'model': 'gpt-4o-mini-transcribe'
        });
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        if (kDebugMode) {
          debugPrint(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Transcription API response in \\${duration}ms: $response');
        }
        final transcription = response['text'] as String;
        if (kDebugMode) {
          debugPrint(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Transcription result: $transcription');
        }
        // RACE CONDITION FIX: Mark transcription complete before file cleanup
        _recordingManager.markTranscriptionComplete(recordedFilePath);

        // Successfully transcribed, now delete the file
        await FileCleanupManager.safeDelete(recordedFilePath);
        return transcription.isNotEmpty ? transcription : "";
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '❌ VOICE ERROR: processRecordedAudioFile: Error calling transcription API: $e');
        }
        // RACE CONDITION FIX: Mark transcription complete even on error to prevent path reuse
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: Unable to transcribe audio. Please try again.";
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '❌ VOICE ERROR: processRecordedAudioFile: Error processing audio file: $e');
      }
      try {
        // RACE CONDITION FIX: Mark transcription complete even on processing error
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        final file = io.File(recordedFilePath);
        if (await file.exists()) {
          await FileCleanupManager.safeDelete(recordedFilePath);
        }
      } catch (delErr) {
        if (kDebugMode) {
          debugPrint(
              '❌ VOICE ERROR: processRecordedAudioFile: Error deleting file during cleanup: $delErr');
        }
      }
      return "Error: Problem processing audio. Please try again.";
    }
  }

  // Note: File deletion is now handled by FileCleanupManager.safeDelete

  /// Custom transcription method with extended timeout for large audio files
  Future<dynamic> _transcribeWithCustomTimeout(
      Map<String, dynamic> body) async {
    try {
      // Use a longer timeout for transcription (45 seconds instead of 15)
      const transcriptionTimeout = Duration(seconds: 45);

      if (kDebugMode) {
        debugPrint(
            '⏹️ VOICE DEBUG: Using extended timeout (45s) for transcription');
      }

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      // Build headers
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      // Make direct HTTP call with extended timeout
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
      if (kDebugMode) {
        debugPrint('❌ VOICE ERROR: _transcribeWithCustomTimeout failed: $e');
      }
      rethrow;
    }
  }

  // WebSocket TTS methods removed - now handled by TTSService

  // TTS methods removed - now handled by TTSService to eliminate duplicate calls

  // Helper TTS methods removed - handled by TTSService

  // generateAudio method removed - now handled by TTSService to eliminate duplicate calls

  // Play an audio file
  Future<void> playAudio(String audioPath) async {
    _audioPlaybackController.add(true);

    if (_controllerPlaybackEnabled) {
      await _voicePipelineController!.requestPlayAudio(audioPath);
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('🔊 VoiceService: Beginning audio playback of $audioPath');
      }

      // Stop any existing audio before starting new playback
      await _audioPlayerManager.stopAudio();

      // Request audio focus before playback
      final session = await AudioSession.instance;
      final focusGranted = await session.setActive(true);
      if (!focusGranted) {
        if (kDebugMode) {
          debugPrint('🔊 VoiceService: Audio session activation NOT granted');
        }
        _audioPlaybackController.add(false);
        return;
      } else {
        if (kDebugMode) debugPrint('🔊 VoiceService: Audio session activated');
      }

      session.becomingNoisyEventStream.listen((_) {
        if (kDebugMode) {
          debugPrint(
              '🔊 VoiceService: Audio becoming noisy (e.g. headphones unplugged)');
        }
        stopAudio();
      });
      session.interruptionEventStream.listen((event) {
        if (kDebugMode) {
          debugPrint('🔊 VoiceService: Audio interruption: $event');
        }
        if (event.begin) stopAudio();
      });

      if (audioPath.startsWith('local_tts://')) {
        if (kDebugMode) {
          debugPrint(
              '🔊 VoiceService: Detected local TTS fallback path, using text-to-speech');
        }
        // _useTtsBackup will manage the _ttsSpeakingStateController
        await _useTtsBackup();
        _audioPlaybackController
            .add(false); // Signal general audio playback ended
        return;
      }

      if (audioPath.startsWith('http')) {
        if (kDebugMode) {
          debugPrint('🔊 VoiceService: Playing audio from URL: $audioPath');
        }
        if (!_isWeb) {
          // Use AudioPlayerManager for URL playback by downloading first
          try {
            final localPath = await _downloadAndCacheAudio(audioPath);
            if (localPath != null) {
              await _audioPlayerManager.playAudio(localPath);
              // AudioPlayerManager will handle state updates
              _audioPlayerManager.isPlayingStream.listen((isPlaying) {
                _audioPlaybackController.add(isPlaying);
              });
            } else {
              throw Exception('Failed to download audio from URL');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('🔊 VoiceService: Error playing URL: $e');
            }
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS if URL play fails
          }
        } else {
          // Web playback simulation
          await Future.delayed(const Duration(seconds: 2));
          _audioPlaybackController.add(false);
        }
      } else if (!_isWeb) {
        final file = io.File(audioPath);
        if (await file.exists()) {
          if (kDebugMode) {
            debugPrint('🔊 VoiceService: Playing local audio file: $audioPath');
          }
          try {
            await _audioPlayerManager.playAudio(audioPath);
            // AudioPlayerManager will handle state updates
            _audioPlayerManager.isPlayingStream.listen((isPlaying) {
              _audioPlaybackController.add(isPlaying);
            });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('🔊 VoiceService: Error playing local file: $e');
            }
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS
          }
        } else {
          if (kDebugMode) {
            debugPrint('🔊 VoiceService: File not found $audioPath, using TTS');
          }
          _audioPlaybackController.add(false);
          await _useTtsBackup();
        }
      } else {
        // Web, non-HTTP path - likely an error or needs TTS
        if (kDebugMode) {
          debugPrint(
              '🔊 VoiceService: Unhandled audio path on web: $audioPath, using TTS');
        }
        _audioPlaybackController.add(false);
        await _useTtsBackup();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🔊 VoiceService: Error in playAudio: $e');
      _audioPlaybackController.add(false);
      await _useTtsBackup(); // Fallback to TTS on any error
      // AudioPlayerManager handles its own cleanup
    }
  }

  // Stop any ongoing audio playback
  Future<void> stopAudio() async {
    if (_controllerPlaybackEnabled) {
      _audioPlaybackController.add(false);
      await _voicePipelineController!.requestStopAudio(clearQueue: true);
      return;
    }
    try {
      if (kDebugMode) {
        debugPrint('Stopping any ongoing audio playback');
      }

      // Signal that audio playback has stopped to listeners
      _audioPlaybackController.add(false);

      // Stop the AudioPlayerManager and force its state
      await _audioPlayerManager.stopAudio();
      _audioPlayerManager
          .forceStopState(); // Force the state to false immediately

      if (kDebugMode) {
        debugPrint('Audio playback stopped successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error stopping audio: $e');
      }

      // Ensure we signal playback stopped even on error
      try {
        _audioPlaybackController.add(false);
        _audioPlayerManager.forceStopState(); // Force stop even on error
      } catch (_) {}
    }
  }

  // Download a remote audio file and cache it locally
  Future<String?> _downloadAndCacheAudio(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      // Get temporary directory for caching using PathManager
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final cacheDir = PathManager.instance.cacheDir;
      final filePath = p.join(cacheDir, fileName);

      // Write the audio data to a file
      final file = io.File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      return filePath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error downloading audio: $e');
      }
      return null;
    }
  }

  // Fallback to text-to-speech when audio file is not available
  Future<void> _useTtsBackup() async {
    if (kDebugMode) {
      AppLogger.d('TTS: Using text-to-speech fallback');
    }

    try {
      String textToSpeak =
          "I'm sorry, I couldn't play the audio right now."; // Default error

      try {
        final prefs = await SharedPreferences.getInstance();
        final savedText = prefs.getString('last_tts_text');
        if (savedText != null && savedText.isNotEmpty) {
          textToSpeak = savedText;
        }
      } catch (e) {
        if (kDebugMode) {
          AppLogger.w('TTS: Error retrieving saved text for TTS', e);
        }
      }

      if (kDebugMode) {
        AppLogger.d('TTS: Preparing to speak: "$textToSpeak"');
      }

      // Use system TTS instead of audio player for text
      // This is a simple fallback - the actual TTS implementation should be replaced
      // with proper system TTS calls
      if (kDebugMode) {
        AppLogger.d('TTS fallback would speak: $textToSpeak');
      }

      if (kDebugMode) {
        AppLogger.d('TTS: speak() called');
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.e('TTS: Error in _useTtsBackup', e);
      }
    }
  }

  // Play audio with progressive streaming (starts playing while still downloading)
  Future<void> playStreamingAudio(String audioUrl) async {
    try {
      if (kDebugMode) {
        debugPrint('Playing streaming audio from URL: $audioUrl');
      }

      if (_isWeb) {
        if (kDebugMode) {
          debugPrint(
              'Web platform does not support streaming audio, using fallback');
        }
        await playAudio(audioUrl);
        return;
      }

      // Check if the URL exists before attempting to stream
      try {
        final response = await http.head(Uri.parse(audioUrl));
        if (response.statusCode != 200) {
          if (kDebugMode) {
            debugPrint(
                'Audio URL not accessible: $audioUrl, using TTS fallback');
          }
          await _useTtsBackup();
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error checking audio URL: $e, falling back to TTS');
        }
        await _useTtsBackup();
        return;
      }

      // Create a player instance for streaming
      final player = AudioPlayer();

      try {
        // Set the audio source with low buffer size for quicker start
        await player.setAudioSource(
          ProgressiveAudioSource(
            Uri.parse(audioUrl),
            // Lower buffer size helps start playback faster
            headers: {
              'Range': 'bytes=0-'
            }, // Request range to enable progressive playback
          ),
          preload: false, // Don't preload the entire audio file
        );

        // Start playing as soon as enough is buffered
        final playbackStartTime = DateTime.now();
        await player.play();

        if (kDebugMode) {
          debugPrint(
              'Streaming audio playback started in ${DateTime.now().difference(playbackStartTime).inMilliseconds}ms');
        }

        // Wait for playback to complete
        await player.processingStateStream.firstWhere(
          (state) => state == ProcessingState.completed,
        );

        if (kDebugMode) {
          debugPrint('Streaming audio playback completed');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error streaming audio: $e');
        }
        // Try fallback to regular download and play method
        try {
          await playAudio(audioUrl);
        } catch (fallbackError) {
          if (kDebugMode) {
            debugPrint(
                'Fallback playback also failed: $fallbackError, using TTS');
          }
          await _useTtsBackup();
        }
      } finally {
        // Clean up resources
        await player.dispose();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in streaming playback: $e');
      }
      // Last resort fallback
      await _useTtsBackup();
    }
  }

  // New method to check if audio is currently playing
  Future<bool> isPlaying() async {
    try {
      // Create a temporary player to check status
      final player = AudioPlayer();

      // Check if the player is playing
      final isPlaying = player.playing;

      // Dispose the temporary player
      await player.dispose();

      return isPlaying;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking audio playback state: $e');
      }
      return false;
    }
  }

  // Cleanup resources
  void dispose() {
    if (kDebugMode) debugPrint('[VoiceService] dispose called');
    _disposed = true;
    _ttsActive = false;
    _currentTtsState = false;
    _currentPlaybackToken = null;
    _lastPlaybackToken = null;
    _autoModeWaitTokens.clear();
    _recordingActive = false;
    _playbackActive = false;
    _playbackStartedForCurrentTts = false;

    if (_useGeminiLive) {
      unawaited(stopGeminiLiveSession());
    }

    // WebSocket cleanup removed - handled by TTSService

    // Clean up debounce timer
    _playbackDebounceTimer?.cancel();

    // if (_recordingStateController != null &&
    //     !_recordingStateController!.isClosed) {
    //   _recordingStateController!.close();
    // }

    unawaited(_playbackActiveSub?.cancel());
    _playbackActiveSub = null;

    if (!_audioPlaybackController.isClosed) {
      _audioPlaybackController.close();
    }

    if (!_ttsSpeakingStateController.isClosed) {
      _ttsSpeakingStateController.close();
    }

    // AudioPlayerManager is disposed separately by its own dispose method

    // if (_recordingStateController != null && !_recordingStateController!.isClosed) {
    //   _recordingStateController!.close();
    // }

    _recordingManager.dispose();

    // Phase 2.1.1: Dispose AudioRecordingService
    _audioRecordingService.dispose();

    // Clean up any temporary files (only on non-web platforms)
    if (!_isWeb &&
        _lastGeneratedAudioPath != null &&
        !_lastGeneratedAudioPath!.startsWith('http')) {
      try {
        final file = io.File(_lastGeneratedAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error cleaning up audio file: $e');
        }
      }
    }
  }

  // Method to dispose the voice service
  // void emitRecordingState(RecordingState state) {
  //   if (_recordingStateController != null && !_recordingStateController!.isClosed) {
  //     _recordingStateController!.add(state);
  //   }
  // }

  // Method to get the AudioPlayerManager instance
  AudioPlayerManager getAudioPlayerManager() {
    return _audioPlayerManager;
  }

  // Method to get the RecordingManager instance
  RecordingManager getRecordingManager() {
    return _recordingManager;
  }

  bool get controllerAutoModeEnabled => _controllerAutoModeEnabled;

  // CRITICAL FIX: Method to play audio with debounce to prevent duplicate calls
  Future<void> playAudioWithCallbacks(
    String filePath, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    // DEBOUNCE: Prevent duplicate calls for the same file within 100ms
    if (_lastPlayedFile == filePath) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] playAudioWithCallbacks: DEBOUNCED duplicate call for $filePath');
      }
      // Still trigger callbacks since caller expects them
      onDone?.call();
      return;
    }

    // Cancel any pending debounce timer
    _playbackDebounceTimer?.cancel();

    _lastPlayedFile = filePath;
    _setAiSpeaking(true);
    if (kDebugMode) {
      debugPrint('[VoiceService] playAudioWithCallbacks: Playing $filePath');
    }

    try {
      // Ensure the AudioPlayerManager's playAudio method is awaited
      // and it signals completion appropriately for onDone/onError.
      await _audioPlayerManager.playAudio(filePath);
      onDone?.call();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ERROR playing audio with callbacks: $e');
      onError?.call('Error playing audio: ${e.toString()}');
    } finally {
      _setAiSpeaking(false);

      // Clear the debounce after a short delay
      _playbackDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        _lastPlayedFile = null;
      });
    }
  }

  void _setAiSpeaking(bool speaking) {
    isAiSpeaking = speaking;
    _ttsActive = speaking;
    _ttsSpeakingStateController.add(speaking);

    // SIMPLIFIED: Only update TTS state - AutoListeningCoordinator handles VAD coordination
    // The single TTS "done" signal approach eliminates competing VAD restart triggers
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] _setAiSpeaking: TTS state set to $speaking (VAD coordination handled by AutoListeningCoordinator)');
    }
  }

  /// Centralized callback for when TTS playback is done successfully
  void _onPlaybackDone() {
    isAiSpeaking = false; // single source of truth
    _ttsSpeakingStateController.add(false);
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] _onPlaybackDone: TTS state cleared (AutoListeningCoordinator handles VAD restart)');
    }
  }

  /// Update TTS speaking state for auto-listening coordination
  /// This is the clean interface for external TTS state updates
  void updateTTSSpeakingState(bool isSpeaking, {int? playbackToken}) {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] updateTTSSpeakingState: isSpeaking=$isSpeaking, token=$playbackToken');
    }
    final guarded = _ttsLock.protect(() async {
      final tokenChanged =
          playbackToken != null && playbackToken != _currentPlaybackToken;

      // Allow token refresh even if the boolean state is unchanged
      if (!tokenChanged && _currentTtsState == isSpeaking) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] updateTTSSpeakingState: State already $_currentTtsState, ignoring duplicate call');
        }
        return;
      }

      if (isSpeaking && playbackToken != null) {
        if (kDebugMode) {
          debugPrint('[VoiceService] Tracking playback token '
              '$playbackToken for auto-mode guard');
        }
        _currentPlaybackToken = playbackToken;
        if (!_autoModeWaitTokens.contains(playbackToken)) {
          unawaited(enableAutoModeWhenPlaybackCompletes(
            playbackToken: playbackToken,
          ));
        }
      }

      if (!isSpeaking && playbackToken != null) {
        if (_currentPlaybackToken != null &&
            playbackToken != _currentPlaybackToken) {
          if (kDebugMode) {
            debugPrint(
                '[VoiceService] updateTTSSpeakingState: Ignoring stale completion for token $playbackToken (active: $_currentPlaybackToken)');
          }
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
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] updateTTSSpeakingState error: $error\n$stackTrace');
      }
    }));
  }

  Future<void> _drainRecordingBeforePlayback() async {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] Playback lock acquired – preparing for TTS start');
    }

    _playbackStartedForCurrentTts = false;
    if (_playbackActive) {
      _playbackStartedForCurrentTts = true;
    }

    if (isRecordingActive) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] TTS starting – stopping active recording before playback');
      }
      try {
        await tryStopRecording();
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint('[VoiceService] Error stopping recording before TTS: $e');
          debugPrint('$stack');
        }
      }
    }

    _autoListeningCoordinator.stopListening();
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] updateTTSSpeakingState: TTS started, listening stopped');
    }
  }

  Future<void> _waitForPlaybackToFinish({
    Duration playbackStartTimeout = const Duration(seconds: 3),
    Duration playbackEndTimeout = const Duration(seconds: 8),
  }) async {
    if (!_playbackStartedForCurrentTts && !_playbackActive) {
      // No playback was triggered for this TTS cycle.
      return;
    }

    if (!_playbackStartedForCurrentTts) {
      try {
        await _audioPlayerManager.playbackActiveStream
            .firstWhere((active) => active)
            .timeout(playbackStartTimeout);
        _playbackStartedForCurrentTts = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] Playback start wait timed out: $e (continuing)');
        }
      }
    }

    if (!_playbackActive) {
      return;
    }

    try {
      await _audioPlayerManager.playbackActiveStream
          .firstWhere((active) => !active)
          .timeout(playbackEndTimeout);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] Playback completion wait timed out: $e (continuing)');
      }
    }
  }

  Future<void> _handleTtsCompletion() async {
    // Always update token state for cleanup
    final completedPlaybackToken = _currentPlaybackToken;
    if (completedPlaybackToken != null) {
      _lastPlaybackToken = completedPlaybackToken;
    }
    _currentPlaybackToken = null;

    // BATCH 2 PHASE 6: Guard against late TTS completion after session end
    if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] TTS completion after session ended - skipping listening restart');
      }
      return;
    }

    // CONTROLLER PATH: When controller is active, it handles TTS→listening
    // transition via its own _ttsSub listener. We only do token cleanup above.
    if (_controllerAutoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] _handleTtsCompletion: Controller handles listening restart (skipping legacy path)');
      }
      return;
    }

    // LEGACY PATH: Manual TTS completion handling for AutoListeningCoordinator

    // BYPASS FIX: Check voice mode before re-arming VAD
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] TTS done in chat mode – skipping listening restart');
      }
      return;
    }

    await _waitForPlaybackToFinish();

    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] Playback finished but voice mode exited – skipping listening restart');
      }
      return;
    }

    if (canStartListeningCallback != null && !canStartListeningCallback!()) {
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] TTS done but bloc deferred listening restart – awaiting readiness');
      }
      return;
    }

    if (!_autoListeningCoordinator.autoModeEnabled) {
      // CRITICAL FIX: If auto mode is disabled but the bloc says we CAN listen
      // (mic enabled, voice mode, greeting played), re-enable auto mode.
      // This handles mic toggle during TTS causing desync between bloc and coordinator.
      if (canStartListeningCallback != null && canStartListeningCallback!()) {
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] TTS done – autoMode disabled but bloc allows listening, re-enabling');
        }
        _autoListeningCoordinator.enableAutoMode();
        _autoListeningCoordinator.startListening();
        if (kDebugMode) {
          debugPrint(
              '[VoiceService] updateTTSSpeakingState: TTS done, auto mode re-enabled and listening restarted');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
            '[VoiceService] TTS done but autoMode disabled – skipping listening restart');
      }
      return;
    }

    _autoListeningCoordinator.startListening(); // guarantees VAD on
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] updateTTSSpeakingState: TTS done, listening restarted (legacy path)');
    }
  }

  /// Legacy VAD pause method - now no-op as echo-loop prevention removed
  Future<void> pauseVAD() async {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] pauseVAD: Legacy method - no action needed with new TTS architecture');
    }
  }

  /// Legacy VAD resume method - now no-op as echo-loop prevention removed
  Future<void> resumeVAD() async {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] resumeVAD: Legacy method - no action needed with new TTS architecture');
    }
  }

  /// Check if there are any pending or active TTS requests
  /// Used to prevent race conditions when resetting/stopping TTS
  bool get hasPendingOrActiveTts {
    try {
      return DependencyContainer().ttsService.hasPendingOrActiveTts;
    } catch (e) {
      // Fallback if TTS service not available
      return _currentTtsState;
    }
  }

  // Public method to reset TTS state
  void resetTTSState() {
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] resetTTSState: Resetting TTS state to false (VAD coordination handled by AutoListeningCoordinator)');
    }
    _currentTtsState = false;
    _currentPlaybackToken = null;
    _lastPlaybackToken = null;
    _setAiSpeaking(false);
  }

  /// Mute or unmute the speaker (local device only, does not affect streams)
  Future<void> setSpeakerMuted(bool muted) async {
    // Use AudioSettings if available for global mute
    if (_audioSettings != null) {
      _audioSettings!.setMuted(muted);
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] Updated global mute to $muted via AudioSettings');
      }
    } else {
      // Fallback to old behavior for backward compatibility
      final volume = muted ? 0.0 : 1.0;
      await _audioPlayerManager.setVolume(volume);
      if (kDebugMode) {
        debugPrint(
            '[VoiceService] setSpeakerMuted: muted=$muted (volume=$volume) - legacy mode');
      }
    }
  }
}
