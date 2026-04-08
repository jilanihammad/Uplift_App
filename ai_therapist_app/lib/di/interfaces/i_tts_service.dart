// lib/di/interfaces/i_tts_service.dart
import 'dart:async';
abstract class ITTSService {
  Future<void> speak(String text,
      {String? voice, String format = 'auto', bool makeBackupFile = true});
  Future<String> generateSpeech(String text, {String? voice});
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  });
  Future<void> streamAndPlayTTSChunked(
    Stream<String> textStream, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  });
  Future<void> playAudio(String audioPath);
  Future<void> stopAudio();
  Future<void> pauseAudio();
  Future<void> resumeAudio();
  Future<void> cancelAllStreams();
  bool get isPlaying;
  bool get isSpeaking;
  bool get hasPendingOrActiveTts; // Race condition guard for reset operations
  Stream<bool> get playbackStateStream;
  Stream<bool> get speakingStateStream;
  void setVoiceSettings(String voice, double speed, double pitch);
  void setAudioFormat(String format);
  void setSessionValidityCallback(bool Function()? callback);
  void resetTTSState();
  void setAiSpeaking(bool speaking);
  Future<void> initialize();
  void dispose();
  Future<String?> downloadAndCacheAudio(String url);
  Future<void> cleanupAudioFiles();
  void setCachedTTSConfig();
}
