// lib/blocs/voice_session/voice_session_event.dart
// Clean event definitions for VoiceSessionBloc

import 'package:flutter/foundation.dart';
import '../../services/pipeline/voice_pipeline_controller.dart';

@immutable
abstract class VoiceSessionEvent {
  const VoiceSessionEvent();
}

/// Initialize the voice session
class InitializeSession extends VoiceSessionEvent {
  const InitializeSession();
}

/// Start a new voice session
class StartSession extends VoiceSessionEvent {
  const StartSession();
}

/// End the current voice session
class EndSession extends VoiceSessionEvent {
  const EndSession();
}

/// Switch between voice and chat mode
class SwitchMode extends VoiceSessionEvent {
  final bool isVoiceMode;
  const SwitchMode(this.isVoiceMode);
}

/// Toggle microphone mute state
class ToggleMic extends VoiceSessionEvent {
  const ToggleMic();
}

/// Send a text message
class SendMessage extends VoiceSessionEvent {
  final String text;
  const SendMessage(this.text);
}

/// Process recorded audio file
class ProcessAudio extends VoiceSessionEvent {
  final String audioPath;
  const ProcessAudio(this.audioPath);
}

/// Stop current audio playback
class StopAudio extends VoiceSessionEvent {
  const StopAudio();
}

/// Set the user's mood
class SetMood extends VoiceSessionEvent {
  final String mood;
  const SetMood(this.mood);
}

/// Set the session duration
class SetDuration extends VoiceSessionEvent {
  final Duration duration;
  const SetDuration(this.duration);
}

/// Pipeline snapshot updated
class PipelineSnapshotUpdated extends VoiceSessionEvent {
  final VoicePipelineSnapshot snapshot;
  const PipelineSnapshotUpdated(this.snapshot);
}

/// Error occurred
class ErrorOccurred extends VoiceSessionEvent {
  final String error;
  const ErrorOccurred(this.error);
}

/// Clear error state
class ClearError extends VoiceSessionEvent {
  const ClearError();
}
