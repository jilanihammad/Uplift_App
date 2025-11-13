// lib/services/pipeline/voice_pipeline_controller.dart
// Phase 1 skeleton: mirrors existing voice pipeline state without mutating behavior.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../auto_listening_coordinator.dart';
import '../voice_service.dart';
import '../voice_session_coordinator.dart';
import '../audio_player_manager.dart';
import '../recording_manager.dart';
import '../../utils/box_logger.dart';
import '../../utils/disposable.dart';
import 'voice_pipeline_dependencies.dart';
import 'audio_capture.dart';
import 'audio_playback.dart';
import 'ai_gateway.dart';
import 'mic_auto_mode_controller.dart';

typedef VoicePipelineControllerFactory = VoicePipelineController Function({
  required VoicePipelineDependencies dependencies,
  bool Function()? micMutedGetter,
});

/// Coarse phases that the upcoming controller will expose to the UI and services.
enum VoicePipelinePhase {
  idle,
  greeting,
  listening,
  recording,
  transcribing,
  speaking,
  cooldown,
}

@immutable
class VoicePipelineSnapshot {
  final VoicePipelinePhase phase;
  final bool micMuted;
  final bool autoModeEnabled;
  final bool isTtsActive;
  final AutoListeningState coordinatorState;
  final int generation;
  final DateTime timestamp;

  const VoicePipelineSnapshot({
    required this.phase,
    required this.micMuted,
    required this.autoModeEnabled,
    required this.isTtsActive,
    required this.coordinatorState,
    required this.generation,
    required this.timestamp,
  });

  VoicePipelineSnapshot copyWith({
    VoicePipelinePhase? phase,
    bool? micMuted,
    bool? autoModeEnabled,
    bool? isTtsActive,
    AutoListeningState? coordinatorState,
    int? generation,
    DateTime? timestamp,
  }) {
    return VoicePipelineSnapshot(
      phase: phase ?? this.phase,
      micMuted: micMuted ?? this.micMuted,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      isTtsActive: isTtsActive ?? this.isTtsActive,
      coordinatorState: coordinatorState ?? this.coordinatorState,
      generation: generation ?? this.generation,
      timestamp: timestamp ?? DateTime.now(),
    );
  }
}

/// Minimal configuration placeholder – will be expanded as the controller
/// begins to own pipeline responsibilities instead of merely mirroring state.
class VoiceSessionConfig {
  final String? sessionId;
  final Duration? targetDuration;
  const VoiceSessionConfig({this.sessionId, this.targetDuration});
}

/// Placeholder audio plan description for greeting flows.
class AudioPlan {
  final String? description;
  final Duration? expectedDuration;
  const AudioPlan({this.description, this.expectedDuration});
}

class VoicePipelineController with SessionDisposable {
  VoicePipelineController({
    required VoicePipelineDependencies dependencies,
    bool Function()? micMutedGetter,
  })  : _autoListening = dependencies.autoListening,
        _voiceService = dependencies.voiceService,
        _legacyCoordinator = dependencies.sessionCoordinator,
        _audioPlayerManager = dependencies.audioPlayerManager,
        _recordingManager = dependencies.recordingManager,
        _audioCapture = dependencies.audioCapture,
        _audioPlayback = dependencies.audioPlayback,
        _aiGateway = dependencies.aiGateway,
        _micController = dependencies.micController,
        _micMutedGetter = micMutedGetter ?? (() => false) {
    _operationTail = Future.value();
    _snapshot = VoicePipelineSnapshot(
      phase: VoicePipelinePhase.idle,
      micMuted: _micMutedGetter(),
      autoModeEnabled: _autoListening.autoModeEnabled,
      isTtsActive: _voiceService.isTtsActive,
      coordinatorState: _autoListening.currentState,
      generation: 0,
      timestamp: DateTime.now(),
    );
    _snapshotController = StreamController<VoicePipelineSnapshot>.broadcast(
      onListen: () => _snapshotController.add(_snapshot),
    );
    _wireMirrors();
    if (kDebugMode) {
      debugPrint('[VoicePipelineController] Mirror mode active '
          '(legacy=${_legacyCoordinator != null} '
          'player=${_audioPlayerManager != null} '
          'rec=${_recordingManager != null})');
    }
  }

  final AutoListeningCoordinator _autoListening;
  final VoiceService _voiceService;
  final VoiceSessionCoordinator? _legacyCoordinator;
  final AudioPlayerManager? _audioPlayerManager;
  final RecordingManager? _recordingManager;
  // ignore: unused_field
  final AudioCapture? _audioCapture;
  // ignore: unused_field
  final AudioPlayback? _audioPlayback;
  // ignore: unused_field
  final AiGateway? _aiGateway;
  final MicAutoModeController? _micController;
  final bool Function() _micMutedGetter;

  late VoicePipelineSnapshot _snapshot;
  late StreamController<VoicePipelineSnapshot> _snapshotController;
  late Future<void> _operationTail;
  StreamSubscription<AutoListeningState>? _autoStateSub;
  StreamSubscription<bool>? _autoModeSub;
  StreamSubscription<bool>? _ttsSub;
  bool _disposed = false;
  bool _welcomeInProgress = false;

  VoicePipelineSnapshot get current => _snapshot;
  Stream<VoicePipelineSnapshot> get snapshots => _snapshotController.stream;
  bool get supportsRecording => _audioCapture != null;
  bool get supportsPlayback => _audioPlayback != null;
  bool get supportsAutoMode => _micController != null;

  Future<void> startSession(VoiceSessionConfig config) async {
    return _enqueue(() {
      _welcomeInProgress = false;
      _updateSnapshot(
        phase: VoicePipelinePhase.idle,
        reason: 'startSession sessionId=${config.sessionId}',
      );
    });
  }

  Future<void> enterGreeting(AudioPlan plan) {
    return _enqueue(() {
      _welcomeInProgress = true;
      _updateSnapshot(
        phase: VoicePipelinePhase.greeting,
        reason: 'enterGreeting ${plan.description ?? 'default'}',
      );
    });
  }

  Future<void> armListening({String context = 'manual'}) {
    return _enqueue(() {
      _welcomeInProgress = false;
      _updateSnapshot(
        phase: VoicePipelinePhase.listening,
        reason: 'armListening($context)',
      );
    });
  }

  Future<void> onUserSpeechCaptured(String path) {
    return _enqueue(() {
      _updateSnapshot(
        phase: VoicePipelinePhase.transcribing,
        reason: 'onUserSpeechCaptured($path)',
      );
    });
  }

  Future<void> onAiResponse(Stream<List<int>> chunkStream) {
    return _enqueue(() async {
      _updateSnapshot(
        phase: VoicePipelinePhase.speaking,
        reason: 'onAiResponse:stream',
      );
      // We intentionally do not consume the stream yet—VoiceService remains the owner
      await Future<void>.value();
    });
  }

  Future<void> teardown() {
    return _enqueue(() async {
      _welcomeInProgress = false;
      _updateSnapshot(phase: VoicePipelinePhase.idle, reason: 'teardown');
    });
  }

  void updateExternalMicState(bool micMuted) {
    _updateSnapshot(micMuted: micMuted, reason: 'externalMicUpdate');
  }

  Future<void> requestStartRecording() async {
    if (_audioCapture == null) {
      return;
    }
    await _enqueue(() async {
      await _audioCapture!.start();
      _updateSnapshot(
        phase: VoicePipelinePhase.recording,
        reason: 'requestStartRecording',
      );
    });
  }

  Future<String?> requestStopRecording() async {
    if (_audioCapture == null) {
      return null;
    }
    String? result;
    await _enqueue(() async {
      result = await _audioCapture!.stop();
      _updateSnapshot(
        phase: VoicePipelinePhase.transcribing,
        reason: 'requestStopRecording',
      );
    });
    return result;
  }

  Future<void> requestPlayAudio(String audioPath) async {
    if (_audioPlayback == null) {
      return;
    }
    await _enqueue(() async {
      await _audioPlayback!.playFile(audioPath);
      _updateSnapshot(
        phase: VoicePipelinePhase.speaking,
        isTtsActive: true,
        reason: 'requestPlayAudio',
      );
    });
  }

  Future<void> requestStopAudio({bool clearQueue = true}) async {
    if (_audioPlayback == null) {
      return;
    }
    await _enqueue(() async {
      await _audioPlayback!.stop(clearQueue: clearQueue);
      _updateSnapshot(
        phase: VoicePipelinePhase.cooldown,
        isTtsActive: false,
        reason: 'requestStopAudio',
      );
    });
  }

  Future<void> requestEnableAutoMode() async {
    if (_micController == null) {
      return;
    }
    await _enqueue(() async {
      await _micController!.enableAutoMode();
      _updateSnapshot(
        autoModeEnabled: true,
        phase: VoicePipelinePhase.listening,
        reason: 'requestEnableAutoMode',
      );
    });
  }

  Future<void> requestDisableAutoMode() async {
    if (_micController == null) {
      return;
    }
    await _enqueue(() async {
      await _micController!.disableAutoMode();
      _updateSnapshot(
        autoModeEnabled: false,
        phase: VoicePipelinePhase.idle,
        reason: 'requestDisableAutoMode',
      );
    });
  }

  void requestTriggerListening() {
    if (_micController == null) {
      return;
    }
    _enqueue(() async {
      _micController!.triggerListening();
      _updateSnapshot(
        phase: VoicePipelinePhase.listening,
        reason: 'requestTriggerListening',
      );
    });
  }

  void _wireMirrors() {
    _autoStateSub = _autoListening.stateStream.listen((state) {
      _enqueue(() {
        _updateSnapshot(
          phase: _phaseFromState(state, _snapshot.isTtsActive),
          coordinatorState: state,
          reason: 'autoState:${state.name}',
        );
      });
    });

    _autoModeSub = _autoListening.autoModeEnabledStream.listen((enabled) {
      _enqueue(() {
        _updateSnapshot(
          autoModeEnabled: enabled,
          reason: 'autoMode:$enabled',
        );
      });
    });

    _ttsSub = _voiceService.isTtsActuallySpeaking.listen((isSpeaking) {
      _enqueue(() {
        final nextPhase = isSpeaking
            ? VoicePipelinePhase.speaking
            : _phaseFromState(_snapshot.coordinatorState, isSpeaking);
        _updateSnapshot(
          isTtsActive: isSpeaking,
          phase: nextPhase,
          reason: 'tts:$isSpeaking',
        );
      });
    });
  }

  VoicePipelinePhase _phaseFromState(
      AutoListeningState state, bool isTtsActive) {
    if (isTtsActive || state == AutoListeningState.aiSpeaking) {
      return VoicePipelinePhase.speaking;
    }
    switch (state) {
      case AutoListeningState.listening:
      case AutoListeningState.listeningForVoice:
        return VoicePipelinePhase.listening;
      case AutoListeningState.userSpeaking:
        return VoicePipelinePhase.recording;
      case AutoListeningState.processing:
        return VoicePipelinePhase.transcribing;
      case AutoListeningState.idle:
        return _welcomeInProgress
            ? VoicePipelinePhase.greeting
            : VoicePipelinePhase.idle;
      default:
        return VoicePipelinePhase.idle;
    }
  }

  Future<void> _enqueue(FutureOr<void> Function() work) {
    if (_disposed) {
      return Future.value();
    }
    _operationTail = _operationTail.then((_) => Future.sync(work));
    return _operationTail.catchError((error, stack) {
      if (kDebugMode) {
        debugPrint('[VoicePipelineController] Work item error: $error');
        debugPrint(stack.toString());
      }
    });
  }

  void _updateSnapshot({
    VoicePipelinePhase? phase,
    bool? micMuted,
    bool? autoModeEnabled,
    bool? isTtsActive,
    AutoListeningState? coordinatorState,
    String? reason,
  }) {
    if (_disposed) {
      return;
    }
    final next = _snapshot.copyWith(
      phase: phase,
      micMuted: micMuted ?? _micMutedGetter(),
      autoModeEnabled: autoModeEnabled,
      isTtsActive: isTtsActive,
      coordinatorState: coordinatorState,
      generation: _snapshot.generation + 1,
      timestamp: DateTime.now(),
    );
    _snapshot = next;
    if (reason != null && kDebugMode) {
      BoxLogger.debug('🎛', 'VoicePipelineController', 'snapshot update',
          details: {
            'reason': reason,
            'phase': next.phase.name,
            'autoMode': next.autoModeEnabled.toString(),
            'tts': next.isTtsActive.toString(),
          });
    }
    if (!_snapshotController.isClosed) {
      _snapshotController.add(next);
    }
  }

  @override
  void performDisposal() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _autoStateSub?.cancel();
    _autoModeSub?.cancel();
    _ttsSub?.cancel();
    _snapshotController.close();
  }
}
