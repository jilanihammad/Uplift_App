import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Audio format configuration with feature flag preservation
///
/// This config allows safe rollback to WAV format if OPUS streaming
/// encounters issues in production.
class AudioFormatConfig {
  /// Master feature flag for OPUS support
  /// OPUS provides 60-70% size reduction for faster TTS streaming
  /// Set to false to force WAV format if OPUS encounters issues
  /// Backend supports OPUS via response_format parameter in llm_manager.py
  static bool get enableOpusFormat =>
      false; // WAV mode - standardized format across frontend/backend

  /// Feature flag for OPUS header buffering
  /// Controls whether we wait for complete OPUS headers before playback
  static const bool enableOpusHeaderBuffering = true;

  /// Feature flag for WAV header modification (legacy streaming support)
  /// Kept for backward compatibility and emergency fallback
  static const bool enableWavHeaderModification = true;

  /// Feature flag for streaming vs full-buffer mode
  /// Controls whether we use progressive streaming or wait for complete audio
  static const bool enableProgressiveStreaming = true;

  /// Buffer size for streaming threshold (bytes)
  /// Only used when progressive streaming is enabled
  static const int streamingBufferThreshold = 32768; // 32KB

  /// OPUS bitrate in bits per second
  static int get opusBitrate =>
      _getEnvInt('TTS_OPUS_BITRATE', 64000); // 64 kbps default

  /// OPUS sample rate in Hz
  static int get opusSampleRate =>
      _getEnvInt('TTS_OPUS_SAMPLE_RATE', 48000); // 48 kHz default

  /// OPUS channels (1 = mono, 2 = stereo)
  static int get opusChannels =>
      _getEnvInt('TTS_OPUS_CHANNELS', 1); // Mono default

  /// OPUS rollout percentage (0-100)
  static int get opusRolloutPercentage =>
      _getEnvInt('TTS_OPUS_ROLLOUT_PCT', 0); // 0% - OPUS disabled, using WAV

  /// OPUS header buffer timeout (milliseconds)
  /// How long to wait for complete OPUS headers before giving up
  static const int opusHeaderTimeoutMs = 5000; // 5 seconds

  /// Emergency rollback to WAV format
  /// This can be set to true at runtime if OPUS encounters issues
  static bool _emergencyWavFallback = false;

  /// Check if OPUS format should be used
  /// Considers both enableOpusFormat flag and rollout percentage
  static bool get shouldUseOpus {
    if (!enableOpusFormat || _emergencyWavFallback) {
      return false;
    }

    // Honor rollout percentage - if 0%, disable OPUS entirely
    int rolloutPct = opusRolloutPercentage;
    if (rolloutPct <= 0) {
      return false; // 0% rollout means no OPUS
    }
    if (rolloutPct >= 100) {
      return true; // 100% rollout means always OPUS
    }

    // For partial rollout, we'd need user-based hashing
    // For now, treat any rollout > 0% as enabled for this session
    // TODO: Implement proper user-based rollout logic
    return true;
  }

  /// Check if WAV format should be used
  static bool get shouldUseWav {
    return !shouldUseOpus;
  }

  /// Check if OPUS header buffering is enabled
  static bool get shouldBufferOpusHeaders {
    return enableOpusHeaderBuffering && shouldUseOpus;
  }

  /// Check if WAV header modification is enabled
  static bool get shouldModifyWavHeaders {
    return enableWavHeaderModification && shouldUseWav;
  }

  /// Check if progressive streaming is enabled
  static bool get shouldUseProgressiveStreaming {
    return enableProgressiveStreaming;
  }

  /// Enable emergency WAV fallback (runtime override)
  static void enableEmergencyWavFallback(String reason) {
    _emergencyWavFallback = true;

    if (kDebugMode) {
      debugPrint('🚨 AudioFormatConfig: Emergency WAV fallback enabled - $reason');
      logCurrentConfiguration();
    }
  }

  /// Disable emergency WAV fallback (return to normal operation)
  static void disableEmergencyWavFallback() {
    _emergencyWavFallback = false;

    if (kDebugMode) {
      debugPrint('✅ AudioFormatConfig: Emergency WAV fallback disabled');
      logCurrentConfiguration();
    }
  }

  /// Get current configuration summary
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
      'effectiveFormat': shouldUseOpus ? 'OPUS' : 'WAV',
      'shouldBufferOpusHeaders': shouldBufferOpusHeaders,
      'shouldModifyWavHeaders': shouldModifyWavHeaders,
      'shouldUseProgressiveStreaming': shouldUseProgressiveStreaming,
    };
  }

  /// Log current configuration for debugging
  static void logCurrentConfiguration() {
    if (kDebugMode) {
      debugPrint('🎵 AudioFormatConfig: Current configuration:');
      final config = getCurrentConfiguration();
      config.forEach((key, value) {
        debugPrint('  $key: $value');
      });
    }
  }

  /// Validate configuration consistency
  static bool validateConfiguration() {
    bool isValid = true;
    List<String> warnings = [];

    // Check for logical inconsistencies
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

    if (kDebugMode && warnings.isNotEmpty) {
      debugPrint('⚠️ AudioFormatConfig: Configuration warnings:');
      for (final warning in warnings) {
        debugPrint('  - $warning');
      }
    }

    return isValid;
  }

  /// Helper to get int from environment with default
  static int _getEnvInt(String key, int defaultValue) {
    return int.tryParse(dotenv.env[key] ?? '') ?? defaultValue;
  }
}
