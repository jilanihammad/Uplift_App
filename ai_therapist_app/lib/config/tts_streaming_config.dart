import 'package:flutter/foundation.dart';
import 'app_config.dart';

/// TTS Streaming Configuration Constants
/// 
/// Provides compile-time constants and runtime configuration for TTS streaming feature.
/// This follows a safety-first approach with feature flags for gradual rollout.
class TTSStreamingConfig {
  static final AppConfig _config = AppConfig();

  /// Whether TTS streaming is enabled
  /// Defaults to false for safety - must be explicitly enabled
  static bool get isEnabled => _config.ttsStreamingEnabled;

  /// Buffer size in bytes before starting playback
  /// Large default (999999) effectively disables streaming until reduced
  static int get bufferSize => _config.ttsStreamingBufferSize;

  /// Maximum duration (in seconds) to keep audio in memory before switching to temp file
  /// Prevents memory bloat for long AI responses
  static int get maxMemoryDurationSeconds => _config.ttsMaxMemoryDurationSeconds;

  /// Calculated max memory duration
  static Duration get maxMemoryDuration => 
      Duration(seconds: maxMemoryDurationSeconds);

  /// Whether to use streaming based on buffer size
  /// Returns false if buffer size is set to effectively disable streaming
  static bool get shouldUseStreaming => 
      isEnabled && bufferSize < 500000; // 500KB threshold

  /// Log current streaming configuration
  static void logConfig() {
    if (kDebugMode) {
      print('🎯 TTS Streaming Config:');
      print('  Enabled: $isEnabled');
      print('  Should Use Streaming: $shouldUseStreaming');
      print('  Buffer Size: $bufferSize bytes (${(bufferSize / 1024).toStringAsFixed(1)} KB)');
      print('  Buffer Description: $bufferSizeDescription');
      print('  Max Memory Duration: $maxMemoryDurationSeconds seconds');
      
      if (shouldUseStreaming) {
        print('  🚀 STREAMING ACTIVE - Will start playback after ${(bufferSize / 1024).toStringAsFixed(1)}KB');
      } else if (isEnabled) {
        print('  ⚠️  STREAMING ENABLED but buffer too large (${(bufferSize / 1024).toStringAsFixed(1)}KB)');
      } else {
        print('  🔄 STREAMING DISABLED - Using full-buffer mode');
      }
    }
  }

  /// Safe buffer sizes for gradual rollout
  static const int bufferSizeDisabled = 999999; // Effectively disabled
  static const int bufferSizeConservative = 32768; // 32KB - very safe
  static const int bufferSizeModerate = 16384; // 16KB - moderately aggressive
  static const int bufferSizeAggressive = 8192; // 8KB - aggressive

  /// Get buffer size description for logging
  static String get bufferSizeDescription {
    if (bufferSize >= bufferSizeDisabled) return 'Disabled (full buffer)';
    if (bufferSize >= bufferSizeConservative) return 'Conservative (32KB+)';
    if (bufferSize >= bufferSizeModerate) return 'Moderate (16KB+)';
    if (bufferSize >= bufferSizeAggressive) return 'Aggressive (8KB+)';
    return 'Very aggressive (<8KB)';
  }
}