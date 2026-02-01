// lib/services/pipeline/voice_pipeline_controller.dart
// Comprehensive rewrite - Consolidates AutoListeningCoordinator functionality

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../voice_service.dart';
import '../audio_player_manager.dart';
import '../recording_manager.dart';
import '../vad_manager.dart';
import '../../utils/app_logger.dart';
import '../../utils/disposable.dart';
import 'voice_pipeline_dependencies.dart';

/// Voice pipeline phases for clear state machine transitions
enum VoicePipelinePhase {
  idle,
  greeting,
  listening,
  recording,
  transcribing,
  speaking,
  cooldown,
  error,
}

/// Immutable snapshot of pipeline state
@immutable
class VoicePipelineSnapshot {
  final VoicePipelinePhase phase;
  final bool micMuted;
  final bool autoModeEnabled;
  final bool isTtsActive;
  final bool isRecording;
  final double? amplitude;
  final int generation;
  final DateTime timestamp;
  final String? errorMessage;

  const VoicePipelineSnapshot({
    required this.phase,
    required this.micMuted,
    required this.autoModeEnabled,
    required this.isTtsActive,
    required this.isRecording,
    this.amplitude,
    required this.generation,
    required this.timestamp,
    this.errorMessage,
  });

  /// Initial state factory
  factory VoicePipelineSnapshot.initial() => VoicePipelineSnapshot(
        phase: VoicePipelinePhase.idle,
        micMuted: false,
        autoModeEnabled: false,
        isTtsActive: false,
        isRecording: false,
        generation: 0,
        timestamp: DateTime.now(),
      );

  VoicePipelineSnapshot copyWith({
    VoicePipelinePhase? phase,
    bool? micMuted,
    bool? autoModeEnabled,
    bool? isTtsActive,
    bool? isRecording,
    double? amplitude,
    int? generation,
    DateTime? timestamp,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VoicePipelineSnapshot(
      phase: phase ?? this.phase,
      micMuted: micMuted ?? this.micMuted,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      isTtsActive: isTtsActive ?? this.isTtsActive,
      isRecording: isRecording ?? this.isRecording,
      amplitude: amplitude ?? this.amplitude,
      generation: generation ?? this.generation,
      timestamp: timestamp ?? DateTime.now(),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() {
    return 'VoicePipelineSnapshot(phase: ${phase.name}, micMuted: $micMuted, '
        'autoMode: $autoModeEnabled, ttsActive: $isTtsActive, recording: $isRecording, '
        'gen: $generation)';
  }
}

/// Configuration for voice session
class VoiceSessionConfig {
  final String? sessionId;
  final Duration? targetDuration;
  final bool enableVAD;
  final Duration silenceTimeout;
  final Duration maxRecordingDuration;

  const VoiceSessionConfig({
    this.sessionId,
    this.targetDuration,
    this.enableVAD = true,
    this.silenceTimeout = const Duration(seconds: 2),
    this.maxRecordingDuration = const Duration(minutes: 2),
  });
}

/// Audio plan for greeting flows
class AudioPlan {
  final String? text;
  final Duration? expectedDuration;
  final String? audioPath;

  const AudioPlan({
    this.text,
    this.expectedDuration,
    this.audioPath,
  });
}

/// Single controller that manages the entire voice pipeline
/// Replaces: AutoListeningCoordinator + VoiceSessionCoordinator + legacy VoiceService state management
class VoicePipelineController with SessionDisposable implements AsyncDisposable {
  // Dependencies
  final VoiceService _voiceService;
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final VADManager _vadManager;
  final bool Function() _micMutedGetter;

  // State
  late VoicePipelineSnapshot _snapshot;
  int _generation = 0;
  bool _disposed = false;
  bool _welcomeInProgress = false;
  Timer? _silenceTimer;
  Timer? _maxRecordingTimer;
  String? _currentRecordingPath;
  
  // Callbacks
  void Function(String audioPath)? _onRecordingComplete;
  void Function(String error)? _onError;
  bool Function()? _canStartListening;

  // Streams
  late final StreamController<VoicePipelineSnapshot> _snapshotController;
  StreamSubscription<bool>? _playbackSub;
  StreamSubscription<bool>? _ttsSub;
  StreamSubscription<double>? _amplitudeSub;

  VoicePipelineController({
    required VoicePipelineDependencies dependencies,
    bool Function()? micMutedGetter,
    bool Function()? canStartListening,
  })  : _voiceService = dependencies.voiceService,
        _audioPlayerManager = dependencies.audioPlayerManager!,
        _recordingManager = dependencies.recordingManager!,
        _vadManager = VADManager(),
        _micMutedGetter = micMutedGetter ?? (() => false),
        _canStartListening = canStartListening {
    _snapshot = VoicePipelineSnapshot.initial().copyWith(
      micMuted: _micMutedGetter(),
    );
    _snapshotController = StreamController<VoicePipelineSnapshot>.broadcast(
      onListen: () => _safeAddSnapshot(_snapshot),
    );
    _wireStreams();
    logger.info('[VoicePipelineController] Initialized');
  }

  // Public getters
  VoicePipelineSnapshot get current => _snapshot;
  Stream<VoicePipelineSnapshot> get snapshots => _snapshotController.stream;
  bool get supportsRecording => true;
  bool get supportsPlayback => true;
  bool get supportsAutoMode => true;
  bool get isDisposed => _disposed;

  // Session lifecycle

  Future<void> startSession(VoiceSessionConfig config) async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Starting session: ${config.sessionId}');
    
    _welcomeInProgress = false;
    _generation++;
    
    await _vadManager.initialize();
    
    _updateSnapshot(
      phase: VoicePipelinePhase.idle,
      generation: _generation,
      clearError: true,
      reason: 'sessionStart',
    );
  }

  Future<void> enterGreeting(AudioPlan plan) async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Entering greeting phase');
    _welcomeInProgress = true;
    
    _updateSnapshot(
      phase: VoicePipelinePhase.greeting,
      reason: 'greetingStart',
    );
  }

  Future<void> armListening({String context = 'manual'}) async {
    if (_disposed) return;
    if (_snapshot.micMuted) {
      logger.info('[VoicePipelineController] Cannot arm listening - mic muted');
      return;
    }
    
    logger.info('[VoicePipelineController] Arming listening (context: $context)');
    _welcomeInProgress = false;
    
    _updateSnapshot(
      phase: VoicePipelinePhase.listening,
      autoModeEnabled: true,
      reason: 'armListening:$context',
    );
    
    // Start VAD listening
    _startVADListening();
  }

  Future<void> requestEnableAutoMode() async {
    if (_disposed) return;
    if (_snapshot.micMuted) {
      logger.info('[VoicePipelineController] Cannot enable auto mode - mic muted');
      return;
    }
    
    logger.info('[VoicePipelineController] Enabling auto mode');
    
    // Wait for any TTS to complete
    if (_snapshot.isTtsActive) {
      logger.info('[VoicePipelineController] Waiting for TTS to complete before enabling auto mode');
      await _waitForPlaybackIdle();
    }
    
    _updateSnapshot(
      autoModeEnabled: true,
      phase: VoicePipelinePhase.listening,
      reason: 'enableAutoMode',
    );
    
    _startVADListening();
  }

  Future<void> requestDisableAutoMode() async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Disabling auto mode');
    
    _stopVADListening();
    _silenceTimer?.cancel();
    
    _updateSnapshot(
      autoModeEnabled: false,
      phase: VoicePipelinePhase.idle,
      reason: 'disableAutoMode',
    );
  }

  Future<void> requestStartRecording() async {
    if (_disposed) return;
    if (_snapshot.isRecording) {
      logger.info('[VoicePipelineController] Already recording');
      return;
    }
    
    logger.info('[VoicePipelineController] Starting recording');
    
    try {
      _currentRecordingPath = await _recordingManager.startRecording();
      
      _updateSnapshot(
        phase: VoicePipelinePhase.recording,
        isRecording: true,
        reason: 'startRecording',
      );
      
      // Start max recording timer
      _maxRecordingTimer?.cancel();
      _maxRecordingTimer = Timer(const Duration(minutes: 2), () {
        logger.info('[VoicePipelineController] Max recording duration reached');
        requestStopRecording();
      });
      
    } catch (e) {
      logger.error('[VoicePipelineController] Failed to start recording', error: e);
      _updateSnapshot(
        phase: VoicePipelinePhase.error,
        errorMessage: 'Failed to start recording: $e',
        reason: 'recordingError',
      );
    }
  }

  Future<String?> requestStopRecording() async {
    if (_disposed) return null;
    if (!_snapshot.isRecording) {
      logger.info('[VoicePipelineController] Not recording');
      return null;
    }
    
    logger.info('[VoicePipelineController] Stopping recording');
    
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();
    
    String? path;
    try {
      path = await _recordingManager.stopRecording();
      _currentRecordingPath = path;
      
      _updateSnapshot(
        phase: VoicePipelinePhase.transcribing,
        isRecording: false,
        reason: 'stopRecording',
      );
      
      // Notify callback
      if (path != null && path.isNotEmpty) {
        _onRecordingComplete?.call(path);
      }
      
    } catch (e) {
      logger.error('[VoicePipelineController] Failed to stop recording', error: e);
      _updateSnapshot(
        phase: VoicePipelinePhase.error,
        isRecording: false,
        errorMessage: 'Failed to stop recording: $e',
        reason: 'recordingError',
      );
    }
    
    return path;
  }

  Future<void> requestPlayAudio(String audioPath) async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Playing audio: $audioPath');
    
    _updateSnapshot(
      phase: VoicePipelinePhase.speaking,
      isTtsActive: true,
      reason: 'playAudio',
    );
    
    try {
      await _audioPlayerManager.playAudio(audioPath);
    } catch (e) {
      logger.error('[VoicePipelineController] Failed to play audio', error: e);
      _updateSnapshot(
        phase: VoicePipelinePhase.error,
        isTtsActive: false,
        errorMessage: 'Failed to play audio: $e',
        reason: 'playbackError',
      );
    }
  }

  Future<void> requestStopAudio({bool clearQueue = true}) async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Stopping audio');
    
    await _audioPlayerManager.stopAudio();
    
    _updateSnapshot(
      phase: VoicePipelinePhase.cooldown,
      isTtsActive: false,
      reason: 'stopAudio',
    );
  }

  void notifyListeningReady({String context = 'manual'}) {
    if (_disposed) return;
    if (_snapshot.micMuted) {
      logger.info('[VoicePipelineController] Listening ready but mic is muted');
      return;
    }
    if (_canStartListening?.call() == false) {
      logger.info('[VoicePipelineController] Listening ready but callback vetoed');
      return;
    }
    
    logger.info('[VoicePipelineController] Listening ready (context: $context)');
    
    if (!_snapshot.isTtsActive && _snapshot.autoModeEnabled) {
      _startVADListening();
    }
  }

  void requestTriggerListening() {
    notifyListeningReady(context: 'trigger');
  }

  void updateExternalMicState(bool micMuted) {
    if (_disposed) return;
    
    _updateSnapshot(
      micMuted: micMuted,
      reason: 'micStateChange',
    );
    
    if (micMuted) {
      // If mic is muted, stop any active listening/recording
      if (_snapshot.isRecording) {
        requestStopRecording();
      }
      _stopVADListening();
    } else if (_snapshot.autoModeEnabled) {
      // If unmuted and auto mode is on, restart listening
      _startVADListening();
    }
  }

  void setRecordingCompleteCallback(void Function(String path)? callback) {
    _onRecordingComplete = callback;
  }

  void setErrorCallback(void Function(String error)? callback) {
    _onError = callback;
  }

  void setCanStartListeningCallback(bool Function()? callback) {
    _canStartListening = callback;
  }

  Future<void> teardown() async {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Tearing down');
    
    _welcomeInProgress = false;
    
    await requestStopAudio();
    await requestDisableAutoMode();
    
    if (_snapshot.isRecording) {
      await requestStopRecording();
    }
    
    _updateSnapshot(
      phase: VoicePipelinePhase.idle,
      autoModeEnabled: false,
      isTtsActive: false,
      isRecording: false,
      reason: 'teardown',
    );
  }

  // Private methods

  void _wireStreams() {
    // Playback state stream
    _playbackSub = _audioPlayerManager.playbackActiveStream.listen((isActive) {
      if (_disposed) return;
      
      if (!isActive && _snapshot.isTtsActive) {
        // Playback completed
        logger.info('[VoicePipelineController] Playback completed');
        
        _updateSnapshot(
          phase: _snapshot.autoModeEnabled && !_snapshot.micMuted
              ? VoicePipelinePhase.listening
              : VoicePipelinePhase.idle,
          isTtsActive: false,
          reason: 'playbackComplete',
        );
        
        // Restart listening if auto mode is enabled
        if (_snapshot.autoModeEnabled && !_snapshot.micMuted) {
          _startVADListening();
        }
      }
    });
    
    // TTS state stream from VoiceService
    _ttsSub = _voiceService.isTtsActuallySpeaking.listen((isSpeaking) {
      if (_disposed) return;
      
      _updateSnapshot(
        isTtsActive: isSpeaking,
        phase: isSpeaking ? VoicePipelinePhase.speaking : _snapshot.phase,
        reason: 'ttsState:$isSpeaking',
      );
      
      if (!isSpeaking && _snapshot.autoModeEnabled && !_snapshot.micMuted) {
        // TTS completed, restart listening
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!_disposed && !_snapshot.isTtsActive) {
            _startVADListening();
          }
        });
      }
    });
    
    // VAD amplitude stream
    _amplitudeSub = _vadManager.amplitudeStream.listen((amplitude) {
      if (_disposed) return;
      
      _handleVADAmplitude(amplitude);
      
      // Update amplitude in snapshot for UI
      if (_snapshot.phase == VoicePipelinePhase.listening ||
          _snapshot.phase == VoicePipelinePhase.recording) {
        _updateSnapshot(
          amplitude: amplitude,
          reason: 'amplitudeUpdate',
        );
      }
    });
  }

  void _handleVADAmplitude(double amplitude) {
    if (!_snapshot.autoModeEnabled || _snapshot.micMuted) return;
    
    final isSpeech = _vadManager.isSpeechDetected(amplitude);
    
    if (isSpeech) {
      // Speech detected
      if (_snapshot.phase == VoicePipelinePhase.listening) {
        // Start recording
        logger.info('[VoicePipelineController] Speech detected, starting recording');
        requestStartRecording();
      }
      
      // Reset silence timer
      _silenceTimer?.cancel();
    } else if (_snapshot.isRecording) {
      // No speech detected while recording - start silence timer
      _silenceTimer ??= Timer(const Duration(seconds: 2), () {
        logger.info('[VoicePipelineController] Silence timeout, stopping recording');
        requestStopRecording();
      });
    }
  }

  void _startVADListening() {
    if (_disposed) return;
    if (_snapshot.micMuted) return;
    if (_snapshot.isRecording) return;
    if (_snapshot.isTtsActive) return;
    
    logger.info('[VoicePipelineController] Starting VAD listening');
    
    _updateSnapshot(
      phase: VoicePipelinePhase.listening,
      reason: 'startVAD',
    );
  }

  void _stopVADListening() {
    if (_disposed) return;
    
    logger.info('[VoicePipelineController] Stopping VAD listening');
    
    _silenceTimer?.cancel();
    _silenceTimer = null;
    
    if (_snapshot.phase == VoicePipelinePhase.listening) {
      _updateSnapshot(
        phase: VoicePipelinePhase.idle,
        reason: 'stopVAD',
      );
    }
  }

  Future<void> _waitForPlaybackIdle() async {
    try {
      await _audioPlayerManager.playbackActiveStream
          .firstWhere((active) => !active)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout - proceed anyway
    }
  }

  void _updateSnapshot({
    VoicePipelinePhase? phase,
    bool? micMuted,
    bool? autoModeEnabled,
    bool? isTtsActive,
    bool? isRecording,
    double? amplitude,
    int? generation,
    String? errorMessage,
    bool clearError = false,
    required String reason,
  }) {
    if (_disposed) return;
    
    final next = _snapshot.copyWith(
      phase: phase,
      micMuted: micMuted,
      autoModeEnabled: autoModeEnabled,
      isTtsActive: isTtsActive,
      isRecording: isRecording,
      amplitude: amplitude,
      generation: generation,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    
    if (kDebugMode) {
      logger.debug('[VoicePipelineController] State: ${_snapshot.phase.name} -> ${next.phase.name} ($reason)');
    }
    
    _snapshot = next;
    _safeAddSnapshot(next);
  }

  void _safeAddSnapshot(VoicePipelineSnapshot snapshot) {
    if (!_snapshotController.isClosed && !_disposed) {
      _snapshotController.add(snapshot);
    }
  }

  @override
  Future<void> performAsyncDisposal() async {
    if (_disposed) return;
    _disposed = true;
    
    logger.info('[VoicePipelineController] Disposing');
    
    // Cancel timers
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();
    
    // Cancel subscriptions
    await _playbackSub?.cancel();
    await _ttsSub?.cancel();
    await _amplitudeSub?.cancel();
    
    _playbackSub = null;
    _ttsSub = null;
    _amplitudeSub = null;
    
    // Close stream controller
    await _snapshotController.close();
    
    logger.info('[VoicePipelineController] Disposed');
  }
}
