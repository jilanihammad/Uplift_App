// lib/voice/streaming_buffer_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/logger_util.dart';

/// Side-car buffer controller for TTS streaming optimization.
/// 
/// This controller isolates all streaming logic from the existing VoiceSessionBloc,
/// following the Golden Rules:
/// 1. No edits inside VoiceSessionBloc
/// 2. Feature flag is immutable per session
/// 3. Two-second watchdog guarantees automatic fallback
class StreamingBufferController {
  // onFlush pushes text to AudioGenerator
  final void Function(String) onFlush;
  
  // ----- tuning knobs -----
  final Duration maxStall;
  final int minBufferChars;          // ~250 ms speech
  final Duration watchdogTimeout;
  
  // ----- internals -----
  final StringBuffer _buf = StringBuffer();
  bool _firstAudioPlayed = false;
  bool _cancelled = false;
  late Timer _watchdog;
  Timer? _stallTimer;

  StreamingBufferController(
    this.onFlush, {
    @visibleForTesting Duration? maxStall,
    @visibleForTesting int? minBufferChars,
    @visibleForTesting Duration? watchdogTimeout,
  }) : maxStall = maxStall ?? const Duration(milliseconds: 150),
       minBufferChars = minBufferChars ?? 180,
       watchdogTimeout = watchdogTimeout ?? const Duration(seconds: 2) {
    _watchdog = Timer(this.watchdogTimeout, _fallbackToLegacy);
    log.d('StreamingBufferController initialized: '
        'minBufferChars=$minBufferChars, maxStall=${this.maxStall.inMilliseconds}ms, '
        'watchdog=${this.watchdogTimeout.inSeconds}s');
  }

  /// Add a chunk of text to the buffer and flush if conditions are met
  void addChunk(String text) {
    if (_cancelled) {
      log.d('StreamingBuffer: Ignoring chunk - cancelled');
      return;
    }
    
    _buf.write(text);
    log.d('StreamingBuffer: Added chunk ${text.length} chars, buffer now ${_buf.length} chars');

    if (_buf.length >= minBufferChars) {
      log.d('StreamingBuffer: Buffer reached minimum chars, flushing');
      _flush();
    }

    _stallTimer?.cancel();
    _stallTimer = Timer(maxStall, () {
      log.d('StreamingBuffer: Stall timer expired, flushing');
      _flush();
    });
  }

  /// Cancel the streaming buffer and clean up
  void cancel() {
    log.d('StreamingBuffer: Cancelling controller');
    _cancelled = true;
    _buf.clear();
    _stallTimer?.cancel();
    _watchdog.cancel();
  }

  // ---------- private ----------
  void _flush() {
    if (_buf.isEmpty) {
      log.d('StreamingBuffer: Buffer empty, nothing to flush');
      return;
    }
    
    final text = _buf.toString();
    final preview = text.length > 50 ? '${text.substring(0, 50)}...' : text;
    log.d('StreamingBuffer: Flushing ${text.length} chars: "$preview"');
    
    onFlush(text);
    _buf.clear();
    _firstAudioPlayed = true;
    _watchdog.cancel();            // success - disable watchdog
  }

  void _fallbackToLegacy() {
    if (_firstAudioPlayed || _cancelled) {
      log.d('StreamingBuffer: Watchdog fired but first audio already played or cancelled');
      return;
    }
    
    log.w('StreamingBuffer WATCHDOG: No audio played within ${watchdogTimeout.inSeconds}s, falling back to legacy');
    cancel();                      // drop side-car
    // legacy full-buffer path keeps handling the stream
  }
}