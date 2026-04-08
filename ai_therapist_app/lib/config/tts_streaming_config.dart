import 'app_config.dart';
class TTSStreamingConfig {
  static final AppConfig _config = AppConfig();
  static bool get isEnabled => _config.ttsStreamingEnabled;
  static int get bufferSize => _config.ttsStreamingBufferSize;
  static int get maxMemoryDurationSeconds =>
      _config.ttsMaxMemoryDurationSeconds;
  static Duration get maxMemoryDuration =>
      Duration(seconds: maxMemoryDurationSeconds);
  static bool get shouldUseStreaming =>
      isEnabled && bufferSize < 500000; // 500KB threshold
  static void logConfig() {
  }
  static const int wavChunkBytes = 8192; // 8KB read unit for WAV
  static const int wavPreplayBytes = 24576; // 24KB before starting playback
  static const int bufferSizeDisabled = 999999; // Effectively disabled
  static const int bufferSizeConservative = 32768; // 32KB - very safe
  static const int bufferSizeModerate = 16384; // 16KB - moderately aggressive
  static const int bufferSizeAggressive = 8192; // 8KB - aggressive
  static String get bufferSizeDescription {
    if (bufferSize >= bufferSizeDisabled) return 'Disabled (full buffer)';
    if (bufferSize >= bufferSizeConservative) return 'Conservative (32KB+)';
    if (bufferSize >= bufferSizeModerate) return 'Moderate (16KB+)';
    if (bufferSize >= bufferSizeAggressive) return 'Aggressive (8KB+)';
    return 'Very aggressive (<8KB)';
  }
}
