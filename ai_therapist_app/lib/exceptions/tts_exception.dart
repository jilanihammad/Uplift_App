// lib/exceptions/tts_exception.dart
import 'dart:async';
import 'dart:io';
sealed class TtsException implements Exception {
  const TtsException(this.message, this.details);
  final String message;
  final String details;
  @override
  String toString() => 'TtsException: $message ($details)';
}
class TtsNetworkException extends TtsException {
  const TtsNetworkException(super.message, [super.details = '']);
  factory TtsNetworkException.webSocketFailed(String url, Object error) =>
      TtsNetworkException(
        'Failed to connect to TTS service',
        'WebSocket connection to $url failed: $error',
      );
  factory TtsNetworkException.timeout(Duration timeout) => TtsNetworkException(
        'TTS service timed out',
        'No response within ${timeout.inMilliseconds}ms',
      );
  factory TtsNetworkException.unauthorized() => const TtsNetworkException(
        'TTS service access denied',
        'Authentication failed or quota exceeded',
      );
}
class TtsQuotaException extends TtsException {
  const TtsQuotaException(super.message, [super.details = '']);
  factory TtsQuotaException.rateLimitExceeded(Duration retryAfter) =>
      TtsQuotaException(
        'TTS rate limit exceeded',
        'Please try again in ${retryAfter.inSeconds} seconds',
      );
  factory TtsQuotaException.quotaExceeded() => const TtsQuotaException(
        'TTS quota exceeded',
        'Daily or monthly usage limit reached',
      );
}
class TtsDeviceBusyException extends TtsException {
  const TtsDeviceBusyException(super.message, [super.details = '']);
  factory TtsDeviceBusyException.audioSessionBusy() => const TtsDeviceBusyException(
        'Audio device is busy',
        'Another app is using the audio system',
      );
  factory TtsDeviceBusyException.audioFocusLost() => const TtsDeviceBusyException(
        'Audio focus lost',
        'Audio focus was taken by another app',
      );
  factory TtsDeviceBusyException.codecUnsupported(String format) =>
      TtsDeviceBusyException(
        'Audio format not supported',
        'Device cannot play $format audio',
      );
}
class TtsConfigurationException extends TtsException {
  const TtsConfigurationException(super.message, [super.details = '']);
  factory TtsConfigurationException.missingConfig(String configKey) =>
      TtsConfigurationException(
        'TTS service not configured',
        'Missing required configuration: $configKey',
      );
  factory TtsConfigurationException.invalidConfig(String reason) =>
      TtsConfigurationException(
        'Invalid TTS configuration',
        reason,
      );
}
class TtsDisabledException extends TtsException {
  const TtsDisabledException(super.message, [super.details = '']);
  factory TtsDisabledException.permanentlyDisabled(int failureCount) =>
      TtsDisabledException(
        'TTS service disabled',
        'Disabled after $failureCount consecutive failures',
      );
  factory TtsDisabledException.userDisabled() => const TtsDisabledException(
        'TTS disabled by user',
        'Text-to-speech has been turned off in settings',
      );
  factory TtsDisabledException.systemUnavailable() => const TtsDisabledException(
        'TTS system unavailable',
        'Device does not support text-to-speech',
      );
}
extension ExceptionConverters on Object {
  TtsException toTtsException([String context = '']) {
    switch (this) {
      case SocketException():
        return TtsNetworkException('Network connection failed', '$this');
      case TimeoutException():
        return TtsNetworkException.timeout(const Duration(seconds: 30));
      case FormatException():
        return TtsConfigurationException('Invalid data format', '$this');
      case TtsException():
        return this as TtsException;
      default:
        return TtsConfigurationException('Unexpected error', '$context: $this');
    }
  }
}
