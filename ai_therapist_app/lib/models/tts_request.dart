// lib/models/tts_request.dart

import 'dart:async';

/// Canonical TTS request object for the single-owner TTSService
/// This eliminates all race conditions and simplifies the TTS pipeline
class TtsRequest {
  final String text;
  final String voice;
  final String format;
  final Completer<void> done;
  final DateTime createdAt;
  final String id;

  TtsRequest({
    required this.text,
    required this.voice,
    required this.format,
  }) : done = Completer<void>(),
       createdAt = DateTime.now(),
       id = DateTime.now().microsecondsSinceEpoch.toString();

  /// Get the future that completes when playback is finished
  Future<void> get completion => done.future;

  /// Complete the request successfully
  void complete() {
    if (!done.isCompleted) {
      done.complete();
    }
  }

  /// Complete the request with an error
  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!done.isCompleted) {
      done.completeError(error, stackTrace);
    }
  }

  @override
  String toString() => 'TtsRequest(id: $id, text: "${text.substring(0, text.length > 30 ? 30 : text.length)}...", voice: $voice)';
}