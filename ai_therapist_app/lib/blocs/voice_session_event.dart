/// VoiceSessionEvent defines all possible user actions and system events that can occur during a therapy session.
/// These events trigger state changes in VoiceSessionBloc, enabling clean separation between UI actions and business logic.
library;

import '../widgets/mood_selector.dart';
import '../models/therapy_message.dart';
import '../services/gemini_live_duplex_controller.dart';
import '../services/pipeline/voice_pipeline_controller.dart';

abstract class VoiceSessionEvent {
  const VoiceSessionEvent();
}

class StartSession extends VoiceSessionEvent {
  const StartSession();
}

// Phase 1A.2: New events for refactoring
class SessionStarted extends VoiceSessionEvent {
  final String? sessionId;
  const SessionStarted(this.sessionId);
}

class EndSession extends VoiceSessionEvent {
  const EndSession();
}

// Phase 1A.2: Alias for end session (matches plan naming)
class EndSessionRequested extends VoiceSessionEvent {
  const EndSessionRequested();
}

class StartListening extends VoiceSessionEvent {
  const StartListening();
}

class StopListening extends VoiceSessionEvent {
  const StopListening();
}

class SelectMood extends VoiceSessionEvent {
  final Mood mood;
  const SelectMood(this.mood);
}

// Phase 1A.2: Alias for mood selection (matches plan naming)
class MoodSelected extends VoiceSessionEvent {
  final Mood mood;
  const MoodSelected(this.mood);
}

class ChangeDuration extends VoiceSessionEvent {
  final int minutes;
  const ChangeDuration(this.minutes);
}

// Phase 1A.2: Duration selected with Duration object
class DurationSelected extends VoiceSessionEvent {
  final Duration duration;
  const DurationSelected(this.duration);
}

class SwitchMode extends VoiceSessionEvent {
  final bool isVoiceMode;
  const SwitchMode(this.isVoiceMode);
}

class ProcessAudio extends VoiceSessionEvent {
  final String audioPath;
  const ProcessAudio(this.audioPath);
}

class HandleError extends VoiceSessionEvent {
  final String error;
  const HandleError(this.error);
}

class UpdateAmplitude extends VoiceSessionEvent {
  final double amplitude;
  const UpdateAmplitude(this.amplitude);
}

class AddMessage extends VoiceSessionEvent {
  final TherapyMessage message;
  const AddMessage(this.message);
}

class SetProcessing extends VoiceSessionEvent {
  final bool isProcessing;
  const SetProcessing(this.isProcessing);
}

class SetRecordingState extends VoiceSessionEvent {
  final bool isRecording;
  const SetRecordingState(this.isRecording);
}

class ProcessTextMessage extends VoiceSessionEvent {
  final String text;
  const ProcessTextMessage(this.text);
}

// Phase 1A.2: Alias for text message (matches plan naming)
class TextMessageSent extends VoiceSessionEvent {
  final String message;
  const TextMessageSent(this.message);
}

class ShowMoodSelector extends VoiceSessionEvent {
  final bool show;
  const ShowMoodSelector(this.show);
}

class ShowDurationSelector extends VoiceSessionEvent {
  final bool show;
  const ShowDurationSelector(this.show);
}

class ToggleMicMute extends VoiceSessionEvent {
  const ToggleMicMute();
}

class EnsureMicToggleEnabled extends VoiceSessionEvent {
  const EnsureMicToggleEnabled();
}

class GeminiLiveEventReceived extends VoiceSessionEvent {
  final GeminiLiveEvent event;
  const GeminiLiveEventReceived(this.event);
}

class VoicePipelineSnapshotUpdated extends VoiceSessionEvent {
  final VoicePipelineSnapshot snapshot;
  const VoicePipelineSnapshotUpdated(this.snapshot);
}

// Phase 3: New events for service calls
class InitializeService extends VoiceSessionEvent {
  const InitializeService();
}

class StopAudio extends VoiceSessionEvent {
  const StopAudio();
}

class PlayAudio extends VoiceSessionEvent {
  final String audioPath;
  const PlayAudio(this.audioPath);
}

class SetSpeakerMuted extends VoiceSessionEvent {
  final bool isMuted;
  const SetSpeakerMuted(this.isMuted);
}

// Events for tracking service states
class AudioPlaybackStateChanged extends VoiceSessionEvent {
  final bool isPlaying;
  const AudioPlaybackStateChanged(this.isPlaying);
}

class TtsStateChanged extends VoiceSessionEvent {
  final bool isSpeaking;
  const TtsStateChanged(this.isSpeaking);
}

// Event to play welcome message with proper TTS state management
class PlayWelcomeMessage extends VoiceSessionEvent {
  final String welcomeMessage;
  const PlayWelcomeMessage(this.welcomeMessage);
}

// Event to mark when the welcome message TTS has completed
class WelcomeMessageCompleted extends VoiceSessionEvent {
  const WelcomeMessageCompleted();
}

// Events for state management
class SetInitializing extends VoiceSessionEvent {
  final bool isInitializing;
  const SetInitializing(this.isInitializing);
}

class SetEndingSession extends VoiceSessionEvent {
  final bool isEndingSession;
  const SetEndingSession(this.isEndingSession);
}

class UpdateSessionTimer extends VoiceSessionEvent {
  const UpdateSessionTimer();
}

/// Fired when the selected session duration reaches zero
class AutoEndTriggered extends VoiceSessionEvent {
  const AutoEndTriggered();
}

/// Clears the auto-end trigger flag after the UI begins the end-session flow
class ClearAutoEndTrigger extends VoiceSessionEvent {
  const ClearAutoEndTrigger();
}

// Events for two-step session start flow to prevent premature audio activation
class StartSessionRequested extends VoiceSessionEvent {
  const StartSessionRequested();
}

class InitialMoodSelected extends VoiceSessionEvent {
  final Mood mood;
  const InitialMoodSelected(this.mood);
}

/// Dismiss the error banner without retrying
class ClearErrorEvent extends VoiceSessionEvent {
  const ClearErrorEvent();
}

/// Retry the last failed action (re-send last message, reconnect, etc.)
class RetryLastActionEvent extends VoiceSessionEvent {
  const RetryLastActionEvent();
}
