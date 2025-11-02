// lib/services/facades/chat_voice_facade.dart
// Chat-only implementation of the session facade contract. Provides a
// lightweight shim so chat flows can opt out of VoiceService entirely while
// still sharing the same bloc/controller interfaces.

import 'package:flutter/foundation.dart';

import '../../di/interfaces/i_therapy_service.dart';
import '../voice_service.dart';
import 'session_voice_facade.dart';

class ChatVoiceFacade implements SessionVoiceFacade {
  ChatVoiceFacade({
    required ITherapyService therapyService,
  }) : _therapyService = therapyService;

  final ITherapyService _therapyService;
  bool _isTransitioning = false;

  @override
  bool get supportsVoice => false;

  @override
  bool get isTransitioning => _isTransitioning;

  @override
  VoiceService? get voiceService => null;

  @override
  Future<void> startSession() async {
    _isTransitioning = true;
    if (kDebugMode) {
      debugPrint('[ChatVoiceFacade] startSession noop');
    }
    _isTransitioning = false;
  }

  @override
  Future<void> endSession() async {
    _isTransitioning = true;
    if (kDebugMode) {
      debugPrint('[ChatVoiceFacade] endSession noop');
    }
    _isTransitioning = false;
  }

  @override
  Future<void> sendText(String text) async {
    await _therapyService.processUserMessage(text);
  }
}
