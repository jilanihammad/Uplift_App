import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';
import 'audio_player_manager.dart';
import 'base_voice_service.dart' as base_voice;
import 'recording_manager.dart';
import 'vad_manager.dart';
import 'enhanced_vad_manager.dart';
import 'voice_service.dart';
import '../utils/logging_config.dart';
import '../utils/disposable.dart';
import '../utils/box_logger.dart';
import '../utils/log_channels.dart';
import '../utils/feature_flags.dart';
class AutoListeningCoordinator with SessionDisposable {
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final VoiceService _voiceService;
  late final Stream<bool> _aiAudioActiveStream;
  final BehaviorSubject<bool> _aiAudioActivitySubject =
      BehaviorSubject<bool>.seeded(false);
  StreamSubscription<bool>? _aiAudioSourceSub;
  StreamSubscription<bool>? _startListeningSub;
  StreamSubscription<String>? _vadErrorSub;
  Completer<void>? _pendingDisableCompleter;
  bool _aiAudioActive = false;
  bool _autoModeEnabledDuringAiAudio = false;
  Timer? _aiAudioGuardTimer;
  static const Duration _aiAudioGuardTimeout = Duration(seconds: 30);
  final bool _voiceGuardEnabled;
  Stream<bool>? _ttsActivityStream;
  static bool _useEnhancedVAD =
      false; // Disabled for simulator runs to avoid mic-permission hard fails
  late final dynamic _vadManager; // Can be VADManager or EnhancedVADManager
  bool get _vadTraceEnabled => kDebugMode && LogChannels.vadTrace;
  bool get _isPipelineIdle => !_isRecordingActive && !_isVadActive && !_aiAudioActive;
  void _logAutoEvent(
    String message, {
    String emoji = '🎤',
    Map<String, String>? details,
    bool trace = false,
  }) {
    if (trace && !_vadTraceEnabled) {
      return;
    }
    BoxLogger.debug(emoji, 'AutoListening', message, details: details);
  }
  void _trace(String message) {
    if (_vadTraceEnabled) {
    }
  }
  void _traceEntryPoint(String method) {
  }
  static void setEnhancedVAD(bool enabled) {
    _useEnhancedVAD = enabled;
  }
  static bool get isEnhancedVADEnabled => _useEnhancedVAD;
  dynamic get vadManager => _vadManager;
  final StreamController<bool> _autoModeEnabledController =
      StreamController<bool>.broadcast();
  final StreamController<AutoListeningState> _stateController =
      StreamController<AutoListeningState>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  Stream<bool> get autoModeEnabledStream => _autoModeEnabledController.stream;
  Stream<AutoListeningState> get stateStream => _stateController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  bool _autoModeEnabled = false;
  bool get autoModeEnabled => _autoModeEnabled;
  AutoListeningState _currentState = AutoListeningState.idle;
  AutoListeningState get currentState => _currentState;
  bool get isRecording => _isRecordingActive;
  Timer? _speechEndDebounceTimer;
  Timer? _stuckStateTimer;
  Timer? _pendingSpeechEndTimer;
  bool _hasPendingSpeechEnd = false;
  int _speechSeq = 0;
  DateTime? _lastSpeechStartTime;
  bool _inSpeechSession = false;
  static const Duration _minSpeechGap = Duration(milliseconds: 300);
  int _speechBurstCount = 0;
  DateTime? _lastSpeechEndTime;
  static const Duration _burstResetThreshold = Duration(seconds: 3);
  static const Duration _baseSpeechTimeout = Duration(milliseconds: 1500);
  static const Duration _secondBurstTimeout = Duration(milliseconds: 1000);
  static const Duration _subsequentBurstTimeout = Duration(milliseconds: 800);
  static const Duration kPostStopDelay = Duration(milliseconds: 120);
  static const Duration kRingDownDelay = Duration(milliseconds: 100);
  static const Duration kWorkerSyncDelay = Duration(
      milliseconds: 50); // Extra safety buffer for worker thread cleanup
  Function()? onSpeechDetectedCallback;
  Function(String audioPath)? onRecordingCompleteCallback;
  bool Function()? isVoiceModeCallback;
  bool _isStoppingRecording = false;
  bool _isVadActive = false;
  bool _isRecordingActive = false;
  bool _isTransitionInProgress = false;
  bool _awaitingPlaybackEnd = false;
  // CRITICAL: Guard flag to prevent multiple VAD restart attempts
  bool _vadRestartScheduled = false;
  Completer<void>? _vadTransitionLock;
  int _vadGeneration = 0;
  int _activeListeningGeneration = 0;
  static const int _maxVadRetries = 3;
  static const List<int> _retryDelays = [
    100,
    200,
    400
  ]; // Exponential backoff in milliseconds
  Future<void> _awaitVadTransition() async {
    final lock = _vadTransitionLock;
    if (lock != null && !lock.isCompleted) {
      await lock.future;
    }
  }
  Completer<void> _beginVadTransition() {
    final lock = Completer<void>();
    _vadTransitionLock = lock;
    _logAutoEvent(
      'Transition begin',
      details: {
        'gen': '$_vadGeneration',
        'timestamp': DateTime.now().toIso8601String(),
      },
      trace: true,
    );
    return lock;
  }
  void _endVadTransition(Completer<void> lock) {
    if (!lock.isCompleted) {
      lock.complete();
    }
    if (identical(_vadTransitionLock, lock)) {
      _vadTransitionLock = null;
    }
    _logAutoEvent(
      'Transition end',
      details: {
        'gen': '$_vadGeneration',
        'timestamp': DateTime.now().toIso8601String(),
      },
      trace: true,
    );
  }
  int _nextVadGeneration() => ++_vadGeneration;
  void _invalidateVadGeneration() {
    _vadGeneration++;
    _activeListeningGeneration = _vadGeneration;
  }
  void _cancelAllTimers({String reason = 'transition'}) {
    _cancelSpeechEndTimer(reason: reason);
    _pendingSpeechEndTimer?.cancel();
    _pendingSpeechEndTimer = null;
    _stuckStateTimer?.cancel();
    _stuckStateTimer = null;
    _cancelAiAudioGuardTimer();
  }
  void _markAutoModeAwaitingAiSilence() {
    if (!_voiceGuardEnabled || !_autoModeEnabled) {
      return;
    }
    _autoModeEnabledDuringAiAudio = true;
    _startAiAudioGuardTimer();
  }
  void _clearAutoModeAwaitingAiSilence({bool cancelTimer = true}) {
    if (!_voiceGuardEnabled) {
      return;
    }
    _autoModeEnabledDuringAiAudio = false;
    if (cancelTimer) {
      _cancelAiAudioGuardTimer();
    }
  }
  void _startAiAudioGuardTimer() {
    if (!_voiceGuardEnabled) {
      return;
    }
    _aiAudioGuardTimer?.cancel();
    _aiAudioGuardTimer = Timer(_aiAudioGuardTimeout, () {
      if (!_autoModeEnabledDuringAiAudio || !_autoModeEnabled) {
        return;
      }
      final stillActive =
          _audioPlayerManager.isPlaybackActive || _voiceService.isTtsActive;
      if (stillActive) {
        _startAiAudioGuardTimer();
        return;
      }
      _forceAiAudioIdle();
      unawaited(_startListeningAfterDelay());
    });
  }
  void _cancelAiAudioGuardTimer() {
    if (!_voiceGuardEnabled) {
      return;
    }
    _aiAudioGuardTimer?.cancel();
    _aiAudioGuardTimer = null;
  }
  void _forceAiAudioIdle() {
    _aiAudioActive = false;
    _clearAutoModeAwaitingAiSilence();
    _cancelAiAudioGuardTimer();
    if (!_aiAudioActivitySubject.isClosed) {
      _aiAudioActivitySubject.add(false);
    }
  }
  Future<void> _waitForAiAudioSilence() async {
    if (!_aiAudioActive) {
      return;
    }
    try {
      await _aiAudioActiveStream
          .firstWhere((active) => !active)
          .timeout(const Duration(seconds: 2));
    } catch (e) {}
  }
  void _completeDisableIfIdle() {
    final completer = _pendingDisableCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (!_isPipelineIdle) {
      return;
    }
    completer.complete();
    _pendingDisableCompleter = null;
  }
  void _setAutoModeEnabled(bool value, {String context = ''}) {
    if (_autoModeEnabled == value) {
      return;
    }
    _autoModeEnabled = value;
    if (!value) {
      _clearAutoModeAwaitingAiSilence();
    }
    _logAutoEvent(
      'Auto mode ${value ? 'enabled' : 'disabled'}'
      '${context.isNotEmpty ? ' ($context)' : ''}',
      emoji: value ? '🟢' : '⚪️',
    );
    _autoModeEnabledController.add(value);
  }
  AutoListeningCoordinator({
    required AudioPlayerManager audioPlayerManager,
    required RecordingManager recordingManager,
    required VoiceService voiceService,
    Stream<bool>? ttsActivityStream, // Optional unified TTS state stream
    dynamic vadManager,
  })  : _audioPlayerManager = audioPlayerManager,
        _recordingManager = recordingManager,
        _voiceService = voiceService,
        _voiceGuardEnabled = FeatureFlags.isCoordinatorVoiceGuardEnabled {
    _vadManager = vadManager ??
        (_useEnhancedVAD ? EnhancedVADManager() : VADManager());
    _ttsActivityStream = ttsActivityStream;
    _aiAudioActiveStream = _aiAudioActivitySubject.stream;
    _rebuildAiAudioActiveStream();
    _aiAudioActive = _voiceGuardEnabled
        ? (_audioPlayerManager.isPlaybackActive || _voiceService.isTtsActive)
        : false;
    _aiAudioActivitySubject.add(_aiAudioActive);
    _setupListeners();
  }
  void setTtsActivityStream(Stream<bool> ttsActivityStream) {
    _ttsActivityStream = ttsActivityStream;
    _rebuildAiAudioActiveStream();
  }
  void _rebuildAiAudioActiveStream() {
    _aiAudioSourceSub?.cancel();
    final combined = Rx.combineLatest2<bool, bool, bool>(
      _audioPlayerManager
          .isPlayingStream, // true while audio player outputs sound
      _ttsActivityStream ??
          Stream.periodic(const Duration(milliseconds: 100),
              (_) => _voiceService.isAiSpeaking).distinct(),
      (playing, speaking) => playing || speaking,
    ).distinct();
    _aiAudioSourceSub = combined.listen((isActive) {
      if (_aiAudioActivitySubject.isClosed) {
        return;
      }
      _aiAudioActivitySubject.add(isActive);
    });
  }
  Future<bool> _startVADWithRetry() async {
    if (_isVadActive) {
      return true;
    }
    for (int attempt = 1; attempt <= _maxVadRetries; attempt++) {
      try {
        final success = await _vadManager.startListening();
        if (success) {
          _isVadActive = true;
          return true;
        } else {
        }
      } catch (e) {}
      if (attempt < _maxVadRetries) {
        final delayMs = _retryDelays[attempt - 1];
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    _isVadActive = false;
    _errorController
        .add('VAD startup failed after $_maxVadRetries retry attempts');
    _updateState(AutoListeningState.idle);
    return false;
  }
  Future<void> _safeStopVAD() async {
    if (!_isVadActive) {
      return;
    }
    try {
      await _vadManager.stopListening();
      _isVadActive = false;
    } catch (e) {
      _isVadActive = false; // Ensure state is consistent even on failure
    }
  }
  Future<void> _safeStartRecording() async {
    if (_isRecordingActive) {
      return;
    }
    try {
      await _recordingManager.startRecording();
      _isRecordingActive = true;
    } catch (e) {}
  }
  void _setupListeners() {
    _audioPlayerManager.playbackActiveStream.listen((isPlaying) {
      if (_autoModeEnabled) {
        if (!isPlaying) {
        } else {
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        }
      }
    });
    _subscribeToAiAudioActivity();
    _vadManager.onSpeechStart.listen((_) {
      if (_autoModeEnabled) {
        final now = DateTime.now();
        final isNewSession = !_inSpeechSession ||
            (_lastSpeechStartTime != null &&
                now.difference(_lastSpeechStartTime!) > _minSpeechGap);
        if (isNewSession) {
          _speechSeq++;
          _inSpeechSession = true;
          _lastSpeechStartTime = now;
          if (_lastSpeechEndTime != null) {
            final timeSinceLastEnd = now.difference(_lastSpeechEndTime!);
            if (timeSinceLastEnd <= _burstResetThreshold) {
              _speechBurstCount++;
            } else {
              _speechBurstCount = 1; // Reset burst count after long pause
            }
          } else {
            _speechBurstCount = 1; // First speech of session
          }
        } else {
        }
        if (_currentState == AutoListeningState.listening) {
          _cancelSpeechEndTimer();
          // CRITICAL FIX: Always transition to userSpeaking, even if recording was already active
          if (!_isRecordingActive) {
            _startRecording(_activeListeningGeneration);
          } else {
          }
          _updateState(AutoListeningState.userSpeaking);
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Cancel pending speech end if user resumes speaking
          _cancelPendingSpeechEnd();
        }
      }
    });
    _vadManager.onSpeechEnd.listen((_) {
      if (_autoModeEnabled) {
        if (_currentState == AutoListeningState.userSpeaking) {
          final now = DateTime.now();
          if (_lastSpeechStartTime != null) {
            final timeSinceSpeechStart = now.difference(_lastSpeechStartTime!);
            if (timeSinceSpeechStart < const Duration(milliseconds: 200)) {
              return; // Ignore this speech end event
            }
          }
          _startSpeechEndTimer();
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Handle speech end during processing with debounce
          _handleSpeechEndDuringProcessing();
        } else if (_currentState == AutoListeningState.listening) {
          // CRITICAL FIX: Handle stray recording when stuck in listening state
          if (_isRecordingActive) {
            _stopRecording();
          }
        }
      }
    });
    _recordingManager.recordingStateStream.listen((state) {
      if (state == base_voice.RecordingState.recording) {
        _updateState(AutoListeningState.userSpeaking);
      } else if (state == base_voice.RecordingState.stopped &&
          _currentState == AutoListeningState.userSpeaking) {
        _updateState(AutoListeningState.processing);
      }
    });
    _vadErrorSub = _vadManager.onError.listen((error) {
      _errorController.add('VAD error: $error');
    });
  }
  void _subscribeToAiAudioActivity() {
    if (_aiAudioActivitySubject.isClosed) {
      return;
    }
    _startListeningSub?.cancel();
    _startListeningSub =
        _aiAudioActiveStream.listen(_handleAiAudioActivityChange);
  }
  void _handleAiAudioActivityChange(bool aiAudioActive) {
    _aiAudioActive = aiAudioActive;
    if (!_autoModeEnabled) {
      _clearAutoModeAwaitingAiSilence();
      return;
    }
    if (!_voiceGuardEnabled) {
      if (aiAudioActive) {
        _updateState(AutoListeningState.aiSpeaking);
        _stopListeningAndRecording();
      } else if ((_currentState == AutoListeningState.aiSpeaking ||
              _currentState == AutoListeningState.idle) &&
          !_vadRestartScheduled) {
        _vadRestartScheduled = true;
        _enterAiSpeakingCompleteWithDebounce();
      }
      return;
    }
    if (aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      _vadRestartScheduled = false;
      _updateState(AutoListeningState.aiSpeaking);
      _stopListeningAndRecording();
    } else {
      _cancelAiAudioGuardTimer();
      if (!_autoModeEnabledDuringAiAudio) {
        return;
      }
      if ((_currentState == AutoListeningState.aiSpeaking ||
              _currentState == AutoListeningState.idle) &&
          !_vadRestartScheduled) {
        _vadRestartScheduled = true;
        _enterAiSpeakingCompleteWithDebounce();
      }
    }
  }
  Future<void> _enterAiSpeakingCompleteWithDebounce() async {
    if (_awaitingPlaybackEnd) {
      return;
    }
    _awaitingPlaybackEnd = true;
    try {
      await Future.delayed(kRingDownDelay);
      await Future.delayed(kWorkerSyncDelay);
      if (_currentState == AutoListeningState.aiSpeaking &&
          _autoModeEnabled &&
          _vadRestartScheduled) {
        final vadStarted = await _startVADWithRetry();
        if (vadStarted) {
          await _startListeningAfterDelay();
        } else {
          _updateState(AutoListeningState.idle);
        }
      } else {
      }
    } catch (e) {
      _updateState(AutoListeningState.idle);
    } finally {
      _awaitingPlaybackEnd = false;
      _vadRestartScheduled = false;
    }
  }
  Future<void> _enterAiSpeakingComplete() async {
    if (_awaitingPlaybackEnd) {
      return;
    }
    _awaitingPlaybackEnd = true;
    try {
      await _aiAudioActiveStream.firstWhere((busy) => !busy);
      if (_currentState == AutoListeningState.aiSpeaking &&
          _autoModeEnabled &&
          _vadRestartScheduled) {
        final vadStarted = await _startVADWithRetry();
        if (vadStarted) {
          await _startListeningAfterDelay();
        } else {
          _updateState(AutoListeningState.idle);
        }
      }
    } catch (error) {
      _updateState(AutoListeningState.idle);
    } finally {
      _awaitingPlaybackEnd = false;
      _vadRestartScheduled =
          false; // Clear restart flag when operation completes
    }
  }
  Future<bool> _beginListeningIfAllowed({
    required String context,
    int? expectedGeneration,
    Set<AutoListeningState>? allowedStates,
    required Future<void> Function() onAllowed,
  }) async {
    final states = allowedStates ??
        {AutoListeningState.idle, AutoListeningState.aiSpeaking};
    if (expectedGeneration != null && expectedGeneration != _vadGeneration) {
      return false;
    }
    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      return false;
    }
    if (!_autoModeEnabled) {
      return false;
    }
    if (!states.contains(_currentState)) {
      return false;
    }
    await onAllowed();
    return true;
  }
  Future<void> _startListeningAfterDelay() async {
    _trace(
        '[AutoListeningCoordinator] [VAD] _startListeningAfterDelay called | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      return;
    }
    _clearAutoModeAwaitingAiSilence();
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) return;
    await _beginListeningIfAllowed(
      context: 'deferred',
      allowedStates: {
        AutoListeningState.idle,
        AutoListeningState.aiSpeaking,
      },
      onAllowed: () async {
        await _awaitVadTransition();
        final transitionLock = _beginVadTransition();
        if (_isTransitionInProgress) {
          _trace(
              '[AutoListeningCoordinator] [VAD] Transition already in progress, ignoring duplicate call');
          _endVadTransition(transitionLock);
          return;
        }
        _isTransitionInProgress = true;
        _cancelAllTimers(reason: 'startListeningAfterDelay');
        final currentGeneration = _nextVadGeneration();
        try {
          _trace(
              '[AutoListeningCoordinator] [TRACE] startListeningAfterDelay begin gen=$currentGeneration time=${DateTime.now().toIso8601String()} state=$_currentState');
          if (_currentState == AutoListeningState.idle) {
            _updateState(AutoListeningState.listening);
            await _executeListeningStart(currentGeneration);
            return;
          }
          _updateState(AutoListeningState.listeningForVoice);
          _stuckStateTimer?.cancel();
          _stuckStateTimer = Timer(const Duration(seconds: 1), () {
            if (_currentState == AutoListeningState.listeningForVoice) {
              _trace(
                  '[AutoListeningCoordinator] [VAD] Stuck in listeningForVoice state, resetting to idle');
              _updateState(AutoListeningState.idle);
              _startListeningAfterDelay();
            }
          });
          if (!_autoModeEnabled) {
            _stuckStateTimer?.cancel();
            return;
          }
          await _executeListeningStart(currentGeneration);
        } finally {
          _isTransitionInProgress = false;
          _trace(
              '[AutoListeningCoordinator] [TRACE] startListeningAfterDelay end gen=$currentGeneration time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
          _endVadTransition(transitionLock);
        }
      },
    );
  }
  Future<void> _executeListeningStart(int generation) async {
    _trace('[AutoListeningCoordinator] [VAD] Starting listening '
        '(generation=$generation, currentState=$_currentState, '
        'autoMode=$_autoModeEnabled, aiAudio=$_aiAudioActive)');
    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      return;
    }
    if (_audioPlayerManager.isPlaybackActive) {
      await _voiceService.stopAudio();
    }
    try {
      final vadStarted = await _startVADWithRetry();
      if (!vadStarted) {
        return;
      }
      if (generation != _vadGeneration) {
        return;
      }
      try {
        _activeListeningGeneration = generation;
        await _startRecording(generation);
        _updateState(AutoListeningState.listening);
        _stuckStateTimer?.cancel();
      } catch (e) {
        await _safeStopVAD();
      }
    } catch (e) {}
    _trace('[AutoListeningCoordinator] [TRACE] _executeListeningStart completed '
        'gen=$generation state=$_currentState autoMode=$_autoModeEnabled '
        'time=${DateTime.now().toIso8601String()}');
  }
  Future<void> _startListening([int? generationOverride]) async {
    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      return;
    }
    _clearAutoModeAwaitingAiSilence();
    await _beginListeningIfAllowed(
      context: 'direct',
      allowedStates: {
        AutoListeningState.idle,
        AutoListeningState.processing,
      },
      onAllowed: () async {
        await _awaitVadTransition();
        final transitionLock = _beginVadTransition();
        final generation = generationOverride ?? _nextVadGeneration();
        _cancelAllTimers(reason: 'startListening');
        try {
          _trace(
              '[AutoListeningCoordinator] [TRACE] _startListening begin gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
          try {
            final success = await _startVADWithRetry();
            if (success && generation == _vadGeneration) {
              _activeListeningGeneration = generation;
              _updateState(AutoListeningState.listening);
              _logAutoEvent(
                'Listening for voice activity',
                details: {
                  'gen': '$generation',
                  'state': _currentState.name,
                },
              );
            } else if (!success && kDebugMode) {
              _logAutoEvent(
                'VAD startup failed after retries',
                emoji: '⚠️',
                details: {'state': _currentState.name},
              );
            }
          } catch (e) {
            _errorController.add('Failed to start VAD listening: $e');
            _logAutoEvent('VAD listening error: $e', emoji: '❌');
          }
        } finally {
          _endVadTransition(transitionLock);
          _trace(
              '[AutoListeningCoordinator] [TRACE] _startListening end gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
        }
      },
    );
  }
  Future<void> _startRecording(int generation) async {
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      _logAutoEvent('Start recording blocked - not in voice mode', emoji: '⚠️');
      return;
    }
    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      return;
    }
    if (generation != _vadGeneration) {
      _trace(
          '[AutoListeningCoordinator] [RECORDING] Generation mismatch ($generation vs $_vadGeneration) - aborting start');
      return;
    }
    if (_currentState == AutoListeningState.listening) {
      try {
        _trace(
            '[AutoListeningCoordinator] [TRACE] _startRecording begin gen=$generation time=${DateTime.now().toIso8601String()}');
        await _safeStartRecording();
        if (onSpeechDetectedCallback != null) {
          onSpeechDetectedCallback!();
        }
        _logAutoEvent(
          'Recording started',
          details: {
            'gen': '$generation',
            'state': _currentState.name,
          },
        );
      } catch (e) {
        _errorController.add('Failed to start recording: $e');
        _logAutoEvent('Recording error: $e', emoji: '❌');
      }
    } else {
      _trace(
          '[AutoListeningCoordinator] [TRACE] _startRecording skipped - state=$_currentState gen=$generation time=${DateTime.now().toIso8601String()}');
    }
  }
  void _startSpeechEndTimer() {
    _cancelSpeechEndTimer(reason: 'Starting new timer');
    final int currentSeq = _speechSeq;
    final int currentGen = _activeListeningGeneration;
    final Duration timeout = _getAdaptiveSpeechTimeout();
    _trace(
        '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Starting ${timeout.inMilliseconds}ms timer (burst: $_speechBurstCount). Current state: $_currentState, sequence: $currentSeq');
    if (_vadTraceEnabled && loggingConfig.isVerboseDebugEnabled) {
    }
    _speechEndDebounceTimer = Timer(timeout, () {
      _trace(
          '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired. Current state: $_currentState, timer seq: $currentSeq, current seq: $_speechSeq');
      if (_vadTraceEnabled && loggingConfig.isVerboseDebugEnabled) {
      }
      if (currentGen == _activeListeningGeneration &&
          currentSeq == _speechSeq &&
          _currentState == AutoListeningState.userSpeaking) {
        _inSpeechSession = false;
        _lastSpeechEndTime = DateTime.now();
        _stopRecording();
      } else {
      }
    });
  }
  void _cancelSpeechEndTimer({String reason = 'unknown'}) {
    if (_speechEndDebounceTimer != null && _speechEndDebounceTimer!.isActive) {
      _speechEndDebounceTimer?.cancel();
    }
  }
  Duration _getAdaptiveSpeechTimeout() {
    if (_speechBurstCount == 1) {
      return _baseSpeechTimeout;
    } else if (_speechBurstCount == 2) {
      return _secondBurstTimeout;
    } else {
      return _subsequentBurstTimeout;
    }
  }
  // CRITICAL FIX: Handle speech end during processing with immediate response and debounce
  void _handleSpeechEndDuringProcessing() {
    _cancelPendingSpeechEnd();
    final int currentSeq = _speechSeq;
    _hasPendingSpeechEnd = true;
    _pendingSpeechEndTimer = Timer(const Duration(milliseconds: 200), () {
      if (_hasPendingSpeechEnd &&
          currentSeq == _speechSeq &&
          _currentState == AutoListeningState.processing) {
        if (_isRecordingActive) {
          _lastSpeechEndTime = DateTime.now();
          _stopRecording();
        }
        _hasPendingSpeechEnd = false;
      }
    });
  }
  // CRITICAL FIX: Cancel pending speech end (called when user resumes speaking)
  void _cancelPendingSpeechEnd() {
    if (_pendingSpeechEndTimer != null && _pendingSpeechEndTimer!.isActive) {
      _pendingSpeechEndTimer?.cancel();
    }
    _hasPendingSpeechEnd = false;
  }
  Future<void> _stopRecording() async {
    if (_isStoppingRecording) {
      return;
    }
    _isStoppingRecording = true;
    try {
      if (_currentState == AutoListeningState.userSpeaking) {
        // CRITICAL FIX: Stop VAD before stopping recording to prevent buffer race (with crash protection)
        try {
          await _vadManager.stopListening();
          _isVadActive = false; // Update state tracking
        } catch (e) {
          _isVadActive = false; // Ensure consistent state even on failure
        }
        final audioPath = await _recordingManager.tryStopRecording();
        if (audioPath != null && audioPath.isNotEmpty) {
          _recordingManager.markFileAsPendingTranscription(audioPath);
          if (onRecordingCompleteCallback != null) {
            onRecordingCompleteCallback!(audioPath);
          }
        }
        _cancelSpeechEndTimer(reason: 'Recording stopped successfully');
        _updateState(AutoListeningState.processing);
      } else {
      }
    } finally {
      // CRITICAL FIX: Always clear recording flag, even on error (engineer's fix)
      _isRecordingActive = false;
      _isStoppingRecording = false;
    }
  }
  Future<void> _stopListeningAndRecording() async {
    await _awaitVadTransition();
    final transitionLock = _beginVadTransition();
    final generation = _nextVadGeneration();
    try {
      _cancelAllTimers(reason: 'stopListening');
      // CRITICAL FIX: Stop VAD stream FIRST and wait for complete shutdown
      await _safeStopVAD();
      await Future.delayed(kPostStopDelay);
      if (_currentState == AutoListeningState.userSpeaking) {
        await _stopRecording();
      }
      _activeListeningGeneration = generation;
    } catch (e) {
      _errorController.add('Error stopping listening/recording: $e');
    } finally {
      _endVadTransition(transitionLock);
    }
  }
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    _traceEntryPoint('enableAutoModeWithAudioState');
    if (!_autoModeEnabled) {
      _setAutoModeEnabled(true,
          context:
              'enableAutoModeWithAudioState(isAudioPlaying=$isAudioPlaying)');
      final shouldDefer = isAudioPlaying || _aiAudioActive;
      if (shouldDefer) {
        _markAutoModeAwaitingAiSilence();
        _updateState(AutoListeningState.aiSpeaking);
      } else {
        _clearAutoModeAwaitingAiSilence();
        await _startListening();
      }
    }
  }
  Future<void> enableAutoMode() async {
    _traceEntryPoint('enableAutoMode');
    if (_autoModeEnabled && _vadTransitionLock == null) {
      return;
    }
    if (_currentState != AutoListeningState.idle) {
      final shouldResetState =
          !_voiceGuardEnabled || _currentState != AutoListeningState.aiSpeaking;
      if (shouldResetState) {
        _updateState(AutoListeningState.idle);
      } else if (kDebugMode) {
        AppLogger.w(
            '⚪️ [ALS] enableAutoMode called while aiSpeaking; guard will handle restart');
      }
    }
    if (_vadRestartScheduled || _speechSeq > 0 || _inSpeechSession) {
    }
    if (!_autoModeEnabled) {
      _setAutoModeEnabled(true, context: 'enableAutoMode');
      final isAudioPlaying =
          _audioPlayerManager.isPlaybackActive || _aiAudioActive || _voiceService.isTtsActive;
      if (isAudioPlaying) {
        _markAutoModeAwaitingAiSilence();
        _updateState(AutoListeningState.aiSpeaking);
      } else {
        _clearAutoModeAwaitingAiSilence();
        await _startListening();
      }
    }
  }
  Future<void> disableAutoMode() {
    _traceEntryPoint('disableAutoMode');
    final existing = _pendingDisableCompleter;
    if (existing != null) {
      return existing.future;
    }
    if (!_autoModeEnabled &&
        !_isVadActive &&
        !_isRecordingActive &&
        _currentState == AutoListeningState.idle) {
      return Future.value();
    }
    final completer = Completer<void>();
    _pendingDisableCompleter = completer;
    () async {
      try {
        _cancelAllTimers(reason: 'disableAutoMode');
        final wasEnabled = _autoModeEnabled;
        if (wasEnabled) {
        }
        await _stopListeningAndRecording();
        await _waitForAiAudioSilence();
        if (wasEnabled && _autoModeEnabled) {
          _setAutoModeEnabled(false, context: 'disableAutoMode');
        }
        _invalidateVadGeneration();
        _forceAiAudioIdle();
        _updateState(AutoListeningState.idle);
        _completeDisableIfIdle();
      } catch (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
        _pendingDisableCompleter = null;
        return;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
      _pendingDisableCompleter = null;
    }();
    return completer.future;
  }
  bool _isValidTransition(AutoListeningState from, AutoListeningState to) {
    const validTransitions = {
      AutoListeningState.idle: {
        AutoListeningState.aiSpeaking,
        AutoListeningState.listening,
      },
      AutoListeningState.aiSpeaking: {
        AutoListeningState.idle,
        AutoListeningState.listening,
        AutoListeningState.listeningForVoice,
      },
      AutoListeningState.listening: {
        AutoListeningState.userSpeaking,
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
      },
      AutoListeningState.userSpeaking: {
        AutoListeningState.processing,
        AutoListeningState.aiSpeaking, // Emergency transition
        AutoListeningState.idle,
      },
      AutoListeningState.processing: {
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
        AutoListeningState.listening,
      },
      AutoListeningState.listeningForVoice: {
        AutoListeningState.listening,
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
      },
    };
    return validTransitions[from]?.contains(to) ?? false;
  }
  void _updateState(AutoListeningState newState) {
    final previousState = _currentState;
    final changed = previousState != newState;
    if (changed && !_isValidTransition(previousState, newState)) {
      _logAutoEvent(
        'Blocked transition ${previousState.name} → ${newState.name}',
        emoji: '⚠️',
        trace: true,
      );
      return; // Prevent invalid transitions
    }
    _currentState = newState;
    _stateController.add(_currentState);
    if (changed) {
      BoxLogger.stateChange(
        'AutoListening',
        previousState.name,
        newState.name,
        emoji: '🎤',
        generation: _vadGeneration,
      );
    }
    if (newState == AutoListeningState.idle ||
        newState == AutoListeningState.listening) {
      _inSpeechSession = false;
      if (_vadTraceEnabled && _lastSpeechStartTime != null) {
        _logAutoEvent(
          'Speech session reset',
          trace: true,
          details: {'state': newState.name},
        );
      }
    }
  }
  void reset({bool full = false, bool? preserveAutoMode}) {
    _traceEntryPoint('reset(full: $full, preserveAutoMode: $preserveAutoMode)');
    final int oldSeq = _speechSeq;
    final bool shouldPreserveAutoMode = preserveAutoMode ?? !full;
    _cancelAllTimers(reason: 'reset');
    _autoModeEnabledDuringAiAudio = false;
    _invalidateVadGeneration();
    _forceAiAudioIdle();
    _subscribeToAiAudioActivity();
    _speechSeq = 0;
    _speechBurstCount = 0;
    _inSpeechSession = false;
    _lastSpeechStartTime = null;
    _lastSpeechEndTime = null;
    _vadRestartScheduled = false;
    _awaitingPlaybackEnd = false;
    _isTransitionInProgress = false;
    _isStoppingRecording = false;
    _hasPendingSpeechEnd = false;
    _updateState(AutoListeningState.idle);
    if (!shouldPreserveAutoMode) {
      _setAutoModeEnabled(false,
          context: full ? 'reset(full)' : 'reset(partial)');
    }
    if (full) {
      _isVadActive = false;
      _isRecordingActive = false;
      _startListeningSub?.cancel();
      _startListeningSub = null;
    }
  }
  @override
  void performDisposal() {
    reset(full: true);
    _aiAudioSourceSub?.cancel();
    _aiAudioSourceSub = null;
    _startListeningSub?.cancel();
    _startListeningSub = null;
    _vadErrorSub?.cancel();
    _vadErrorSub = null;
    _aiAudioActivitySubject.close();
    _autoModeEnabledController.close();
    _stateController.close();
    _errorController.close();
  }
  Future<void> initialize() async {
    _traceEntryPoint('initialize');
    try {
      await _vadManager.initialize();
      _setAutoModeEnabled(false, context: 'initialize');
    } catch (e) {}
  }
  void triggerListening() {
    if (_autoModeEnabled &&
        _currentState != AutoListeningState.listeningForVoice) {
      _startListeningAfterDelay();
    }
  }
  void onProcessingComplete() {
    if (_autoModeEnabled && _currentState == AutoListeningState.processing) {
      _updateState(AutoListeningState.idle);
      _startListeningAfterDelay();
    }
  }
  void startListening() {
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      return;
    }
    if (_autoModeEnabled) {
      triggerListening();
    } else {
    }
  }
  void stopListening() {
    if (_autoModeEnabled) {
      _updateState(AutoListeningState.aiSpeaking);
      _stopListeningAndRecording();
    } else {
    }
  }
}
enum AutoListeningState {
  idle,
  aiSpeaking,
  listening,
  userSpeaking,
  processing,
  listeningForVoice
}
