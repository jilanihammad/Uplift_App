// lib/services/facades/legacy_voice_facade.dart
// Simple facade used when the new voice orchestration is disabled. It keeps
// the legacy behaviour intact while satisfying the SessionVoiceFacade
// contract so consumers can remain agnostic.

import '../../di/interfaces/i_therapy_service.dart';
import '../voice_service.dart';
import 'session_voice_facade.dart';

class LegacyVoiceFacade implements SessionVoiceFacade {
  LegacyVoiceFacade({
    required VoiceService voiceService,
    ITherapyService? therapyService,
  })  : _voiceService = voiceService,
        _therapyService = therapyService;

  final VoiceService _voiceService;
  final ITherapyService? _therapyService;
  bool _isTransitioning = false;

  @override
  bool get supportsVoice => true;

  @override
  bool get isTransitioning => _isTransitioning;

  @override
  VoiceService get voiceService => _voiceService;

  @override
  Future<void> startSession() async {
    _isTransitioning = true;
    try {
      await _voiceService.initializeOnlyIfNeeded();
    } finally {
      _isTransitioning = false;
    }
  }

  @override
  Future<void> endSession() async {
    _isTransitioning = true;
    _isTransitioning = false;
  }

  @override
  Future<void> sendText(String text) async {
    if (_therapyService != null) {
      await _therapyService!.processUserMessage(text);
    }
  }
}
