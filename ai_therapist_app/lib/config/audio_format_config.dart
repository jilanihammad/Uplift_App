import 'package:flutter_dotenv/flutter_dotenv.dart';
class AudioFormatConfig {
  static bool get enableOpusFormat =>
      false; // WAV mode - standardized format across frontend/backend
  static const bool enableOpusHeaderBuffering = true;
  static const bool enableWavHeaderModification = true;
  static const bool enableProgressiveStreaming = true;
  static const int streamingBufferThreshold = 32768; // 32KB
  static int get opusBitrate =>
      _getEnvInt('TTS_OPUS_BITRATE', 64000); // 64 kbps default
  static int get opusSampleRate =>
      _getEnvInt('TTS_OPUS_SAMPLE_RATE', 48000); // 48 kHz default
  static int get opusChannels =>
      _getEnvInt('TTS_OPUS_CHANNELS', 1); // Mono default
  static int get opusRolloutPercentage =>
      _getEnvInt('TTS_OPUS_ROLLOUT_PCT', 0); // 0% - OPUS disabled, using WAV
  static const int opusHeaderTimeoutMs = 5000; // 5 seconds
  static bool _emergencyWavFallback = false;
  static bool get shouldUseOpus {
    if (!enableOpusFormat || _emergencyWavFallback) {
      return false;
    }
    int rolloutPct = opusRolloutPercentage;
    if (rolloutPct <= 0) {
      return false; // 0% rollout means no OPUS
    }
    if (rolloutPct >= 100) {
      return true; // 100% rollout means always OPUS
    }
    // TODO: Implement proper user-based rollout logic
    return true;
  }
  static bool get shouldUseWav {
    return !shouldUseOpus;
  }
  static bool get shouldBufferOpusHeaders {
    return enableOpusHeaderBuffering && shouldUseOpus;
  }
  static bool get shouldModifyWavHeaders {
    return enableWavHeaderModification && shouldUseWav;
  }
  static bool get shouldUseProgressiveStreaming {
    return enableProgressiveStreaming;
  }
  static void enableEmergencyWavFallback(String reason) {
    _emergencyWavFallback = true;
  }
  static void disableEmergencyWavFallback() {
    _emergencyWavFallback = false;
  }
  static Map<String, dynamic> getCurrentConfiguration() {
    return {
      'enableOpusFormat': enableOpusFormat,
      'enableOpusHeaderBuffering': enableOpusHeaderBuffering,
      'enableWavHeaderModification': enableWavHeaderModification,
      'enableProgressiveStreaming': enableProgressiveStreaming,
      'streamingBufferThreshold': streamingBufferThreshold,
      'opusHeaderTimeoutMs': opusHeaderTimeoutMs,
      'opusBitrate': opusBitrate,
      'opusSampleRate': opusSampleRate,
      'opusChannels': opusChannels,
      'opusRolloutPercentage': opusRolloutPercentage,
      'emergencyWavFallback': _emergencyWavFallback,
      'effectiveFormat': shouldUseOpus ? 'OPUS' : 'WAV (or MP3 if requested)',
      'shouldBufferOpusHeaders': shouldBufferOpusHeaders,
      'shouldModifyWavHeaders': shouldModifyWavHeaders,
      'shouldUseProgressiveStreaming': shouldUseProgressiveStreaming,
    };
  }
  static void logCurrentConfiguration() {
  }
  static bool validateConfiguration() {
    bool isValid = true;
    List<String> warnings = [];
    if (enableOpusFormat && !enableOpusHeaderBuffering) {
      warnings.add(
          'OPUS format enabled but header buffering disabled - may cause playback issues');
      isValid = false;
    }
    if (!enableProgressiveStreaming && enableOpusFormat) {
      warnings.add('OPUS format works best with progressive streaming enabled');
    }
    if (streamingBufferThreshold < 1024) {
      warnings.add(
          'Streaming buffer threshold is very low - may cause excessive buffering');
    }
    if (opusHeaderTimeoutMs < 1000) {
      warnings.add(
          'OPUS header timeout is very low - may cause premature timeouts');
    }
    return isValid;
  }
  static int _getEnvInt(String key, int defaultValue) {
    return int.tryParse(dotenv.env[key] ?? '') ?? defaultValue;
  }
}
