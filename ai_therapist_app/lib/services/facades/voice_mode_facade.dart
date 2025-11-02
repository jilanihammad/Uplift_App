// lib/services/facades/voice_mode_facade.dart
// Voice-mode facade that owns the lifecycle of VoiceService and its
// supporting coordination services. The facade serializes start/stop flows
// so chat mode never observes voice callbacks.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../di/interfaces/i_therapy_service.dart';
import '../auto_listening_coordinator.dart';
import '../simple_tts_service.dart';
import '../voice_service.dart';
import 'session_voice_facade.dart';

typedef AutoListeningCoordinatorFactory = AutoListeningCoordinator Function({
  required VoiceService voiceService,
});

/// Concrete facade for live voice sessions. Lazily boots the voice pipeline
/// and ensures teardown happens in a controlled order.
class VoiceModeFacade implements SessionVoiceFacade {
  VoiceModeFacade({
    required VoiceService voiceService,
    required SimpleTTSService ttsService,
    required ITherapyService therapyService,
    required AutoListeningCoordinatorFactory coordinatorFactory,
  })  : _voiceService = voiceService,
        _ttsService = ttsService,
        _therapyService = therapyService,
        _coordinatorFactory = coordinatorFactory;

  final VoiceService _voiceService;
  final SimpleTTSService _ttsService;
  final ITherapyService _therapyService;
  final AutoListeningCoordinatorFactory _coordinatorFactory;

  AutoListeningCoordinator? _autoCoordinator;
  StreamSubscription<bool>? _ttsSpeakingSub;
  final List<StreamSubscription<dynamic>> _sessionSubscriptions = [];
  Completer<void>? _transitionCompleter;

  bool _isTransitioning = false;
  int _sessionGeneration = 0;
  int? _activeGeneration;

  SimpleTTSService get rawTtsService => _ttsService;
  AutoListeningCoordinator? get autoListeningCoordinator => _autoCoordinator;
  int? get activeGeneration => _activeGeneration;

  @override
  bool get supportsVoice => true;

  @override
  bool get isTransitioning => _isTransitioning;

  @override
  VoiceService get voiceService => _voiceService;

  Future<void> _awaitTransition() async {
    final completer = _transitionCompleter;
    if (completer != null) {
      try {
        await completer.future;
      } catch (_) {
        // Rollbacks already handled the failure case.
      }
    }
  }

  @override
  Future<void> startSession() async {
    await _awaitTransition();
    if (_autoCoordinator != null) {
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] startSession skipped - already active');
      }
      return;
    }

    _isTransitioning = true;
    final transition = Completer<void>();
    _transitionCompleter = transition;

    final generation = ++_sessionGeneration;
    try {
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] Initializing voice pipeline (gen $generation)');
      }

      await _voiceService.initializeOnlyIfNeeded();

      _autoCoordinator = _coordinatorFactory(voiceService: _voiceService);
      _autoCoordinator?.isVoiceModeCallback = () => true;
      await _autoCoordinator?.initialize();

      _voiceService.isVoiceModeCallback = () => true;
      _ttsService.setVoiceServiceUpdateCallback(
        _voiceService.updateTTSSpeakingState,
      );

      _ttsSpeakingSub = _voiceService.isTtsActuallySpeaking.listen(_handleTtsState);
      if (_ttsSpeakingSub != null) {
        _sessionSubscriptions.add(_ttsSpeakingSub!);
      }

      _activeGeneration = generation;
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] voice pipeline ready (gen $_activeGeneration)');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] startSession failed: $error');
      }
      await _rollbackInitialization();
      rethrow;
    } finally {
      _isTransitionInProgressCleanup();
    }
  }

  void _handleTtsState(bool isSpeaking) {
    final generation = _activeGeneration;
    if (generation == null) {
      return;
    }
    if (kDebugMode) {
      debugPrint('[VoiceModeFacade] TTS speaking: $isSpeaking (gen $generation)');
    }
  }

  @override
  Future<void> endSession() async {
    await _awaitTransition();
    if (_autoCoordinator == null &&
        _ttsSpeakingSub == null &&
        _sessionSubscriptions.isEmpty) {
      return;
    }

    _isTransitioning = true;
    final transition = Completer<void>();
    _transitionCompleter = transition;

    try {
      await _disposeSubscriptions();

      _ttsService.setVoiceServiceUpdateCallback(null);

      await _autoCoordinator?.disableAutoMode();
      _autoCoordinator?.reset(full: true);
      _autoCoordinator?.isVoiceModeCallback = null;
      _autoCoordinator = null;

      _voiceService.isVoiceModeCallback = null;
      _voiceService.canStartListeningCallback = null;
      _voiceService.resetTTSState();

      _activeGeneration = null;
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] voice pipeline torn down');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[VoiceModeFacade] endSession failed: $error');
      }
      await _rollbackTeardown();
      rethrow;
    } finally {
      _isTransitionInProgressCleanup();
    }
  }

  void _isTransitionInProgressCleanup() {
    _isTransitioning = false;
    final completer = _transitionCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _transitionCompleter = null;
  }

  @override
  Future<void> sendText(String text) async {
    await _awaitTransition();
    await _therapyService.processUserMessage(text);
  }

  Future<void> _disposeSubscriptions() async {
    if (_ttsSpeakingSub != null) {
      await _ttsSpeakingSub?.cancel();
      _ttsSpeakingSub = null;
    }
    if (_sessionSubscriptions.isEmpty) {
      return;
    }
    for (final sub in _sessionSubscriptions) {
      await sub.cancel();
    }
    _sessionSubscriptions.clear();
  }

  Future<void> _rollbackInitialization() async {
    await _disposeSubscriptions();
    _ttsService.setVoiceServiceUpdateCallback(null);
    _autoCoordinator?.reset(full: true);
    _autoCoordinator?.isVoiceModeCallback = null;
    _autoCoordinator = null;
    _voiceService.canStartListeningCallback = null;
    _voiceService.isVoiceModeCallback = null;
    _activeGeneration = null;
  }

  Future<void> _rollbackTeardown() async {
    _autoCoordinator?.reset(full: true);
    _voiceService.canStartListeningCallback = null;
    _voiceService.isVoiceModeCallback = null;
    _activeGeneration = null;
  }
}
