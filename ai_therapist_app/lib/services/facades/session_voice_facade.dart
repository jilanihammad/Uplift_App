// lib/services/facades/session_voice_facade.dart
// Defines the shared contract for chat and voice mode session facades.
// Each facade encapsulates the lifecycle of voice-related services so that
// callers can manage start/end without touching low-level dependencies.

import '../voice_service.dart';

/// Contract implemented by chat and voice session facades.
///
/// The facade abstracts away the differences between text-only chat flows and
/// live voice sessions. Voice-capable facades expose the underlying
/// [VoiceService] for legacy call sites while we migrate the rest of the
/// pipeline.
abstract class SessionVoiceFacade {
  /// Indicates whether the facade supports live voice features
  /// (recording, TTS playback, auto listening, etc.).
  bool get supportsVoice;

  /// Guard toggled while session start/stop work is in flight. Callers should
  /// respect this so that no new requests are triggered during transitions.
  bool get isTransitioning;

  /// Begin a new session scope. Voice-capable facades will initialize
  /// VoiceService + AutoListeningCoordinator. Chat-only facades perform a
  /// lightweight no-op start so existing flows stay consistent.
  Future<void> startSession();

  /// Stop the current session scope and release resources.
  Future<void> endSession();

  /// Send a purely textual utterance through the facade. Voice facades will
  /// pass the work to the TherapyService in addition to any voice coordination.
  Future<void> sendText(String text);

  /// Temporary escape hatch for legacy callers that still require direct
  /// access to [VoiceService]. Returns null for chat-only facades.
  VoiceService? get voiceService;
}
