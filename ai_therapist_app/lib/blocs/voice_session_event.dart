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
class SessionStarted extends VoiceSessionEvent {
  final String? sessionId;
  const SessionStarted(this.sessionId);
}
class EndSession extends VoiceSessionEvent {
  const EndSession();
}
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
class MoodSelected extends VoiceSessionEvent {
  final Mood mood;
  const MoodSelected(this.mood);
}
class ChangeDuration extends VoiceSessionEvent {
  final int minutes;
  const ChangeDuration(this.minutes);
}
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
class AudioPlaybackStateChanged extends VoiceSessionEvent {
  final bool isPlaying;
  const AudioPlaybackStateChanged(this.isPlaying);
}
class TtsStateChanged extends VoiceSessionEvent {
  final bool isSpeaking;
  const TtsStateChanged(this.isSpeaking);
}
class PlayWelcomeMessage extends VoiceSessionEvent {
  final String welcomeMessage;
  const PlayWelcomeMessage(this.welcomeMessage);
}
class WelcomeMessageCompleted extends VoiceSessionEvent {
  const WelcomeMessageCompleted();
}
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
class AutoEndTriggered extends VoiceSessionEvent {
  const AutoEndTriggered();
}
class ClearAutoEndTrigger extends VoiceSessionEvent {
  const ClearAutoEndTrigger();
}
class StartSessionRequested extends VoiceSessionEvent {
  const StartSessionRequested();
}
class InitialMoodSelected extends VoiceSessionEvent {
  final Mood mood;
  const InitialMoodSelected(this.mood);
}
class ClearErrorEvent extends VoiceSessionEvent {
  const ClearErrorEvent();
}
class RetryLastActionEvent extends VoiceSessionEvent {
  const RetryLastActionEvent();
}
