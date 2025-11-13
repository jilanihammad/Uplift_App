// Audio capture abstraction for the upcoming voice pipeline controller.
// Currently a thin wrapper around RecordingManager so we can gradually
// decouple VoiceService from direct recorder control.

import '../recording_manager.dart';
import '../base_voice_service.dart';

abstract class AudioCapture {
  bool get isRecording;
  Future<void> start();
  Future<String?> stop();
}

class RecordingManagerAudioCapture implements AudioCapture {
  final RecordingManager recordingManager;

  RecordingManagerAudioCapture(this.recordingManager);

  @override
  bool get isRecording =>
      recordingManager.currentState == RecordingState.recording;

  @override
  Future<void> start() => recordingManager.startRecording();

  @override
  Future<String?> stop() => recordingManager.stopRecording();
}
