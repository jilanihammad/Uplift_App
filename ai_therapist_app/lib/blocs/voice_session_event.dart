import '../widgets/mood_selector.dart';
import '../models/therapy_message.dart';

abstract class VoiceSessionEvent {
  const VoiceSessionEvent();
}

class StartSession extends VoiceSessionEvent {
  const StartSession();
}

class EndSession extends VoiceSessionEvent {
  const EndSession();
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

class ChangeDuration extends VoiceSessionEvent {
  final int minutes;
  const ChangeDuration(this.minutes);
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

// Phase 3: New events for service calls
class InitializeService extends VoiceSessionEvent {
  const InitializeService();
}

class EnableAutoMode extends VoiceSessionEvent {
  const EnableAutoMode();
}

class DisableAutoMode extends VoiceSessionEvent {
  const DisableAutoMode();
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

// Event to mark when the welcome message TTS has completed
class WelcomeMessageCompleted extends VoiceSessionEvent {
  const WelcomeMessageCompleted();
}
