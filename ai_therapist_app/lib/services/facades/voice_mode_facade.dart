// lib/services/facades/voice_mode_facade.dart
// Voice-mode facade that owns the lifecycle of VoiceService and its
// supporting coordination services. The facade serializes start/stop flows
// so chat mode never observes voice callbacks.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../di/interfaces/i_therapy_service.dart';
import '../simple_tts_service.dart';
import '../voice_service.dart';
import 'session_voice_facade.dart';
class VoiceModeFacade implements SessionVoiceFacade {
  VoiceModeFacade({
    required VoiceService voiceService,
    required SimpleTTSService ttsService,
    required ITherapyService therapyService,
  })  : _voiceService = voiceService,
        _ttsService = ttsService,
        _therapyService = therapyService;
  final VoiceService _voiceService;
  final SimpleTTSService _ttsService;
  final ITherapyService _therapyService;
  StreamSubscription<bool>? _ttsSpeakingSub;
  final List<StreamSubscription<dynamic>> _sessionSubscriptions = [];
  Completer<void>? _transitionCompleter;
  bool _isTransitioning = false;
  int _sessionGeneration = 0;
  int? _activeGeneration;
  SimpleTTSService get rawTtsService => _ttsService;
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
      } catch (_) {}
    }
  }
  @override
  Future<void> startSession() async {
    await _awaitTransition();
    if (_activeGeneration != null) {
      return;
    }
    _isTransitioning = true;
    final transition = Completer<void>();
    _transitionCompleter = transition;
    final generation = ++_sessionGeneration;
    try {
      await _voiceService.initializeOnlyIfNeeded();
      _voiceService.isVoiceModeCallback = () => true;
      _voiceService.resetAutoListening(full: true, preserveAutoMode: false);
      await _voiceService.initializeAutoListening();
      _ttsService.setVoiceServiceUpdateCallback(
        _voiceService.updateTTSSpeakingState,
      );
      _ttsSpeakingSub =
          _voiceService.isTtsActuallySpeaking.listen(_handleTtsState);
      if (_ttsSpeakingSub != null) {
        _sessionSubscriptions.add(_ttsSpeakingSub!);
      }
      _activeGeneration = generation;
    } catch (error) {
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
  }
  @override
  Future<void> endSession() async {
    await _awaitTransition();
    if (_activeGeneration == null &&
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
      await _voiceService.disableAutoMode();
      _voiceService.resetAutoListening(full: true);
      _voiceService.isVoiceModeCallback = null;
      _voiceService.canStartListeningCallback = null;
      _voiceService.resetTTSState();
      _activeGeneration = null;
    } catch (error) {
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
    _voiceService.resetAutoListening(full: true);
    _voiceService.canStartListeningCallback = null;
    _voiceService.isVoiceModeCallback = null;
    _activeGeneration = null;
  }
  Future<void> _rollbackTeardown() async {
    _voiceService.resetAutoListening(full: true);
    _voiceService.canStartListeningCallback = null;
    _voiceService.isVoiceModeCallback = null;
    _activeGeneration = null;
  }
}
