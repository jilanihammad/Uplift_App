import 'package:flutter/foundation.dart';
import '../config/audio_format_config.dart';

/// Audio format negotiation and configuration
///
/// Handles format selection between frontend and backend,
/// with capability detection and fallback strategies.
class AudioFormatNegotiator {
  /// Available audio formats in order of preference
  static const List<AudioFormat> _supportedFormats = [
    AudioFormat.opus, // Preferred for streaming
    AudioFormat.wav, // Fallback for compatibility
  ];

  /// Current active format (starts with WAV for compatibility)
  static AudioFormat _currentFormat = AudioFormat.wav;

  /// Get the preferred format for new TTS requests
  static AudioFormat getPreferredFormat() {
    // Use AudioFormatConfig to determine format
    if (AudioFormatConfig.shouldUseOpus && _isOpusSupported()) {
      return AudioFormat.opus;
    }
    return AudioFormat.wav;
  }

  /// Get current active format
  static AudioFormat getCurrentFormat() => _currentFormat;

  /// Initialize format based on configuration
  static void initialize() {
    _currentFormat = getPreferredFormat();

    if (kDebugMode) {
      print(
          '🎵 AudioFormatNegotiator: Initialized with format: ${_currentFormat.name}');
      AudioFormatConfig.logCurrentConfiguration();
    }
  }

  /// Enable emergency WAV fallback
  static void enableEmergencyFallback(String reason) {
    AudioFormatConfig.enableEmergencyWavFallback(reason);
    _currentFormat = AudioFormat.wav;

    if (kDebugMode) {
      print('🚨 AudioFormatNegotiator: Emergency fallback to WAV - $reason');
    }
  }

  /// Disable emergency fallback and return to configured format
  static void disableEmergencyFallback() {
    AudioFormatConfig.disableEmergencyWavFallback();
    _currentFormat = getPreferredFormat();

    if (kDebugMode) {
      print(
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
    switch (_currentFormat) {
      case AudioFormat.opus:
        return 'audio/ogg'; // OPUS in OGG container
      case AudioFormat.wav:
        return 'audio/wav';
    }
  }

  /// Get file extension for the current format
  static String getFileExtension() {
    switch (_currentFormat) {
      case AudioFormat.opus:
        return 'ogg';
      case AudioFormat.wav:
        return 'wav';
    }
  }

  /// Get backend request format parameter
  static String getBackendFormat() {
    switch (_currentFormat) {
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
      print('🎵 AudioFormatNegotiator: Current configuration:');
      info.forEach((key, value) {
        print('  $key: $value');
      });
    }
  }
}

/// Supported audio formats
enum AudioFormat {
  opus,
  wav,
}

/// Extension methods for AudioFormat
extension AudioFormatExtension on AudioFormat {
  String get name {
    switch (this) {
      case AudioFormat.opus:
        return 'OPUS';
      case AudioFormat.wav:
        return 'WAV';
    }
  }

  String get description {
    switch (this) {
      case AudioFormat.opus:
        return 'OPUS/OGG - Optimized for streaming';
      case AudioFormat.wav:
        return 'WAV - Legacy format with streaming limitations';
    }
  }
}
