import 'dart:async';
abstract class BaseVoiceService {
  Stream<RecordingState> get recordingStateStream;
  Stream<bool> get isPlayingStream;
  Stream<String?> get errorStream;
  Future<void> initialize();
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<String> transcribeAudio(String audioFilePath);
  Future<String> generateAudio(String text);
  Future<void> playAudio(String audioPath);
  Future<void> stopAudio();
  Future<void> speak(String text);
  Future<void> speakWithTts(String text);
  Future<void> dispose();
  Future<void> enableAutoMode();
  Future<void> disableAutoMode();
  bool get isAutoModeEnabled;
}
enum RecordingState {
  stopped,
  recording,
  processing,
  error
}
