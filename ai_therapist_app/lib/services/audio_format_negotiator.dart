import 'package:flutter/foundation.dart';
import '../config/audio_format_config.dart';
import '../config/llm_config.dart';

/// Audio format negotiation and configuration
///
/// Handles format selection between frontend and backend,
/// with capability detection and fallback strategies.
class AudioFormatNegotiator {
  /// Available audio formats in order of preference
  static const List<AudioFormat> _supportedFormats = [
    AudioFormat.native,
    AudioFormat.opus, // Preferred for streaming
    AudioFormat.wav, // Fallback for compatibility
  ];

  /// Current active format (starts with WAV for compatibility)
  static AudioFormat _currentFormat = AudioFormat.wav;

  /// Get the preferred format for new TTS requests
  /// Priority: native mode > client OPUS preference > backend format > WAV fallback
  static AudioFormat getPreferredFormat() {
    final backendFormat =
        LLMConfig.activeTTSResponseFormat.toLowerCase().trim();
    final backendMode = LLMConfig.activeTTSMode.toLowerCase().trim();

    // 1. Native mode takes highest priority (Gemini Live)
    if (backendMode == 'live' || backendFormat == 'native') {
      return AudioFormat.native;
    }

    // 2. Client-side OPUS preference (from AudioFormatConfig)
    // This allows the app to prefer OPUS regardless of backend default
    if (AudioFormatConfig.shouldUseOpus && _isOpusSupported()) {
      return AudioFormat.opus;
    }

    // 3. Backend explicitly requested OPUS
    if (backendFormat == 'opus' && _isOpusSupported()) {
      return AudioFormat.opus;
    }

    // 4. Default to WAV
    return AudioFormat.wav;
  }

  /// Get current active format
  static AudioFormat getCurrentFormat() => _currentFormat;

  /// Initialize format based on configuration
  static void initialize() {
    updateFromConfig(log: true);
  }

  /// Refresh the current format using the latest backend configuration.
  /// This can be called whenever remote overrides change (e.g., after
  /// fetching `/system/tts-config`).
  static void updateFromConfig({bool log = false}) {
    final preferredFormat = getPreferredFormat();
    final formatChanged = _currentFormat != preferredFormat;
    _currentFormat = preferredFormat;

    if (kDebugMode) {
      if (formatChanged) {
        debugPrint(
            '🎵 AudioFormatNegotiator: Format updated to ${_currentFormat.name}');
      } else if (log) {
        debugPrint(
            '🎵 AudioFormatNegotiator: Format remains ${_currentFormat.name}');
      }

      if (log) {
        AudioFormatConfig.logCurrentConfiguration();
      }
    }
  }

  /// Enable emergency WAV fallback
  static void enableEmergencyFallback(String reason) {
    AudioFormatConfig.enableEmergencyWavFallback(reason);
    _currentFormat = AudioFormat.wav;

    if (kDebugMode) {
      debugPrint('🚨 AudioFormatNegotiator: Emergency fallback to WAV - $reason');
    }
  }

  /// Disable emergency fallback and return to configured format
  static void disableEmergencyFallback() {
    AudioFormatConfig.disableEmergencyWavFallback();
    _currentFormat = getPreferredFormat();

    if (kDebugMode) {
      debugPrint(
          '✅ AudioFormatNegotiator: Returned to configured format: ${_currentFormat.name}');
    }
  }

  /// Check if OPUS format is supported by the current environment
  static bool _isOpusSupported() {
    // For now, assume OPUS is supported on all platforms
    // In the future, we could add more sophisticated detection
    return true;
  }

  /// Get MIME type for the current format
  static String getMimeType() {
    return getMimeTypeForFormat(_currentFormat.name.toLowerCase());
  }

  static String getMimeTypeForFormat(String format) {
    switch (format.toLowerCase()) {
      case 'native':
        return LLMConfig.activeTtsMimeType;
      case 'opus':
      case 'ogg_opus':
        return 'audio/ogg; codecs=opus';
      case 'aac':
        return 'audio/aac';
      case 'wav':
      default:
        return 'audio/wav';
    }
  }

  /// Get file extension for the current format
  static String getFileExtension() {
    switch (_currentFormat) {
      case AudioFormat.native:
        return 'ogg';
      case AudioFormat.opus:
        return 'ogg';
      case AudioFormat.wav:
        return 'wav';
    }
  }

  /// Get backend request format parameter
  static String getBackendFormat() {
    switch (_currentFormat) {
      case AudioFormat.native:
        return 'native';
      case AudioFormat.opus:
        return 'opus'; // Backend parameter
      case AudioFormat.wav:
        return 'wav';
    }
  }

  /// Get format configuration for debugging
  static Map<String, dynamic> getFormatInfo() {
    return {
      'currentFormat': _currentFormat.name,
      'configuredFormat': getPreferredFormat().name,
      'mimeType': getMimeType(),
      'fileExtension': getFileExtension(),
      'backendFormat': getBackendFormat(),
      'isOpusSupported': _isOpusSupported(),
      'formatConfig': AudioFormatConfig.getCurrentConfiguration(),
    };
  }

  /// Check if current format supports true streaming
  static bool supportsStreaming() {
    switch (_currentFormat) {
      case AudioFormat.native:
        return true;
      case AudioFormat.opus:
        return true; // OPUS is designed for streaming
      case AudioFormat.wav:
        return true; // WAV now supports streaming with optimized buffers
    }
  }

  /// Log current format configuration
  static void logCurrentConfiguration() {
    if (kDebugMode) {
      final info = getFormatInfo();
      debugPrint('🎵 AudioFormatNegotiator: Current configuration:');
      info.forEach((key, value) {
        debugPrint('  $key: $value');
      });
    }
  }
}

/// Supported audio formats
enum AudioFormat {
  native,
  opus,
  wav,
}

/// Extension methods for AudioFormat
extension AudioFormatExtension on AudioFormat {
  String get name {
    switch (this) {
      case AudioFormat.native:
        return 'NATIVE';
      case AudioFormat.opus:
        return 'OPUS';
      case AudioFormat.wav:
        return 'WAV';
    }
  }

  String get description {
    switch (this) {
      case AudioFormat.native:
        return 'Gemini Live native audio';
      case AudioFormat.opus:
        return 'OPUS/OGG - Optimized for streaming';
      case AudioFormat.wav:
        return 'WAV - Legacy format with streaming limitations';
    }
  }
}
