// lib/exceptions/tts_exception.dart

import 'dart:async';
import 'dart:io';

/// Sealed class hierarchy for TTS-specific exceptions
/// Enables structured error handling with actionable user messages
sealed class TtsException implements Exception {
  const TtsException(this.message, this.details);
  
  final String message;
  final String details;
  
  @override
  String toString() => 'TtsException: $message ($details)';
}

/// Network-related TTS failures (WebSocket, HTTP, connectivity)
class TtsNetworkException extends TtsException {
  const TtsNetworkException(String message, [String details = ''])
      : super(message, details);
  
  /// Factory for WebSocket connection failures
  factory TtsNetworkException.webSocketFailed(String url, Object error) =>
      TtsNetworkException(
        'Failed to connect to TTS service',
        'WebSocket connection to $url failed: $error',
      );
  
  /// Factory for network timeout issues
  factory TtsNetworkException.timeout(Duration timeout) =>
      TtsNetworkException(
        'TTS service timed out',
        'No response within ${timeout.inMilliseconds}ms',
      );
  
  /// Factory for authentication/authorization failures
  factory TtsNetworkException.unauthorized() =>
      TtsNetworkException(
        'TTS service access denied',
        'Authentication failed or quota exceeded',
      );
}

/// Rate limiting and quota exceeded errors
class TtsQuotaException extends TtsException {
  const TtsQuotaException(String message, [String details = ''])
      : super(message, details);
  
  /// Factory for rate limit exceeded
  factory TtsQuotaException.rateLimitExceeded(Duration retryAfter) =>
      TtsQuotaException(
        'TTS rate limit exceeded',
        'Please try again in ${retryAfter.inSeconds} seconds',
      );
  
  /// Factory for daily/monthly quota exceeded  
  factory TtsQuotaException.quotaExceeded() =>
      TtsQuotaException(
        'TTS quota exceeded',
        'Daily or monthly usage limit reached',
      );
}

/// Audio device and session conflicts
class TtsDeviceBusyException extends TtsException {
  const TtsDeviceBusyException(String message, [String details = ''])
      : super(message, details);
  
  /// Factory for audio session conflicts
  factory TtsDeviceBusyException.audioSessionBusy() =>
      TtsDeviceBusyException(
        'Audio device is busy',
        'Another app is using the audio system',
      );
  
  /// Factory for audio focus conflicts
  factory TtsDeviceBusyException.audioFocusLost() =>
      TtsDeviceBusyException(
        'Audio focus lost',
        'Audio focus was taken by another app',
      );
  
  /// Factory for codec/format issues
  factory TtsDeviceBusyException.codecUnsupported(String format) =>
      TtsDeviceBusyException(
        'Audio format not supported',
        'Device cannot play $format audio',
      );
}

/// Service configuration and initialization errors
class TtsConfigurationException extends TtsException {
  const TtsConfigurationException(String message, [String details = ''])
      : super(message, details);
  
  /// Factory for missing configuration
  factory TtsConfigurationException.missingConfig(String configKey) =>
      TtsConfigurationException(
        'TTS service not configured',
        'Missing required configuration: $configKey',
      );
  
  /// Factory for invalid configuration
  factory TtsConfigurationException.invalidConfig(String reason) =>
      TtsConfigurationException(
        'Invalid TTS configuration',
        reason,
      );
}

/// Service disabled or permanently unavailable
class TtsDisabledException extends TtsException {
  const TtsDisabledException(String message, [String details = ''])
      : super(message, details);
  
  /// Factory for permanent disable after repeated failures
  factory TtsDisabledException.permanentlyDisabled(int failureCount) =>
      TtsDisabledException(
        'TTS service disabled',
        'Disabled after $failureCount consecutive failures',
      );
  
  /// Factory for user-disabled TTS
  factory TtsDisabledException.userDisabled() =>
      TtsDisabledException(
        'TTS disabled by user',
        'Text-to-speech has been turned off in settings',
      );
  
  /// Factory for system-level TTS unavailable
  factory TtsDisabledException.systemUnavailable() =>
      TtsDisabledException(
        'TTS system unavailable',
        'Device does not support text-to-speech',
      );
}

/// Utilities for converting generic exceptions to TTS exceptions
extension ExceptionConverters on Object {
  /// Convert generic exception to appropriate TtsException
  TtsException toTtsException([String context = '']) {
    switch (this) {
      case SocketException():
        return TtsNetworkException('Network connection failed', '$this');
      case TimeoutException():
        return TtsNetworkException.timeout(Duration(seconds: 30));
      case FormatException():
        return TtsConfigurationException('Invalid data format', '$this');
      case TtsException():
        return this as TtsException;
      default:
        return TtsConfigurationException('Unexpected error', '$context: $this');
    }
  }
}