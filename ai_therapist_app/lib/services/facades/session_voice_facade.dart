// lib/services/facades/session_voice_facade.dart
// Defines the shared contract for chat and voice mode session facades.
// Each facade encapsulates the lifecycle of voice-related services so that
// callers can manage start/end without touching low-level dependencies.
import '../voice_service.dart';
abstract class SessionVoiceFacade {
  bool get supportsVoice;
  bool get isTransitioning;
  Future<void> startSession();
  Future<void> endSession();
  Future<void> sendText(String text);
  VoiceService? get voiceService;
}
