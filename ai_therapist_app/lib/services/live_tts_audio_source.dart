import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../utils/opus_header_utils.dart';
import '../utils/wav_header_utils.dart';
import '../utils/log_channels.dart';

/// Custom StreamAudioSource for true live TTS streaming
///
/// This enables progressive playback where audio starts quickly and continues
/// streaming as chunks arrive, without the limitations of static audio sources.
///
/// Key features:
/// - True live streaming (no static snapshots)
/// - No seeking support (TTS is linear)
/// - Unknown duration until stream completes
/// - Proper DataSource contract compliance (RESULT_NOTHING_READ vs END_OF_INPUT)
/// - Proper integration with just_audio's streaming architecture
class LiveTtsAudioSource extends StreamAudioSource {
  final Stream<Uint8List> _dataStream;
  final String _contentType;
  final String? _debugName;

  bool get _ttsTraceEnabled => kDebugMode && LogChannels.ttsTrace;

  void _ttsLog(String message) {
    if (_ttsTraceEnabled) {
      debugPrint(message);
    }
  }

  // CRITICAL: Track WebSocket state for proper DataSource contract
  bool _webSocketClosed = false;
  bool _streamCompleted = false;
  int? _totalContentSize; // Total content size from tts-done message
  final Completer<int?> _contentSizeCompleter = Completer<int?>();

  // CRITICAL: Prevent infinite replay loops
  int _requestCount = 0;
  bool _hasDeliveredData = false;

  // Session tracking to allow ExoPlayer seeks during same playback session
  String? _currentSessionId;
  bool _sessionCompleted = false;

  int? _lastRequestTime; // For validation logging

  // Data buffer and stream subscription for proper DataSource implementation
  final List<int> _dataBuffer = [];
  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isListening = false;

  // Chunk counter for log throttling (prevents UI thread blocking)
  int _chunkCount = 0;

  // OPUS header buffering for proper format support
  bool _headersReady = false;
  bool _isOpusFormat = false;
  OpusHeaderInfo? _opusHeaderInfo;
  Uint8List? _completeHeaders;

  int? _playbackToken;

  void attachPlaybackToken(int token) {
    _playbackToken = token;
    if (kDebugMode) {
      _ttsLog(
          '🎯 LiveTtsAudioSource: Attached playback token $token for ${_debugName ?? "TTS"}');
    }
  }

  /// Mark WebSocket as closed (no more data will arrive)
  /// This enables proper END_OF_INPUT signaling to ExoPlayer
  void markWebSocketClosed([int? totalSize]) {
    _webSocketClosed = true;
    _totalContentSize = totalSize;

    // Complete the content size completer for waiting request() calls
    if (!_contentSizeCompleter.isCompleted) {
      _contentSizeCompleter.complete(totalSize);
    }

    if (kDebugMode) {
      _ttsLog(
          '🔌 LiveTtsAudioSource: WebSocket marked as closed for ${_debugName ?? "TTS"} (totalSize: $totalSize)');
    }
  }

  /// Mark stream as completed (all data received and processed)
  void markStreamCompleted() {
    _streamCompleted = true;
    if (kDebugMode) {
      _ttsLog(
          '✅ LiveTtsAudioSource: Stream marked as completed for ${_debugName ?? "TTS"}');
    }
  }

  /// Get WebSocket closed state (for state-based controller closure)
  bool get isWebSocketClosed => _webSocketClosed;

  /// Get stream completed state (for state-based controller closure)
  bool get isStreamCompleted => _streamCompleted;

  /// Get current buffer size for diagnostic logging
  int get bufferSize => _dataBuffer.length;

  /// Create a live TTS audio source from a byte stream
  ///
  /// [byteStream] - The live stream of audio chunks
  /// [contentType] - MIME type (default: 'audio/wav' to match backend)
  /// [debugName] - Optional name for debugging/logging
  ///
  /// Uses stream directly (no double broadcast conversion)
  /// SimpleTTSService already provides broadcast-capable StreamController
  /// (just_audio/ExoPlayer calls request() twice - once for MIME sniffing, once for decoding)
  LiveTtsAudioSource(
    Stream<Uint8List> byteStream, {
    String contentType = 'audio/wav',
    String? debugName,
  })  : _dataStream =
            byteStream, // CRITICAL FIX: Use stream directly, no asBroadcastStream()
        _contentType = contentType,
        _debugName = debugName {
    // Pre-determine format based on content type
    _isOpusFormat = contentType.toLowerCase().contains('ogg') ||
        contentType.toLowerCase().contains('opus');

    if (kDebugMode) {
      _ttsLog(
          '🎯 LiveTtsAudioSource: Created with direct stream access for $debugName (natural completion)');
      _ttsLog(
          '🎯 Format detection: contentType=$contentType, isOpus=$_isOpusFormat');
    }

    // CRITICAL FIX: Start listening immediately to capture broadcast stream events
    // Don't wait for request() - by then broadcast events may be lost
    _startListening();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final requestId = DateTime.now().microsecondsSinceEpoch;
    _requestCount++;

    if (kDebugMode) {
      // Validation logging for timing gaps between requests
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastRequestTime != null) {
        final gap = now - _lastRequestTime!;
        _ttsLog('⚡ Request gap: ${gap}ms (Count: $_requestCount)');
      }
      _lastRequestTime = now;

      _ttsLog('🔍 LiveTtsAudioSource.request() called:');
      _ttsLog('  Request ID: $requestId');
      _ttsLog('  Request Count: $_requestCount');
      _ttsLog('  Debug Name: ${_debugName ?? "unknown"}');
      _ttsLog('  Playback Token: ${_playbackToken ?? 'none'}');
      _ttsLog('  Start: $start, End: $end');
      _ttsLog('  Content Type: $_contentType');
      _ttsLog(
          '  WebSocket State: closed=$_webSocketClosed, streamCompleted=$_streamCompleted');
      _ttsLog('  Buffer Size: ${_dataBuffer.length} bytes');
      _ttsLog('  Has Delivered Data: $_hasDeliveredData');
      _ttsLog('⏳ Waiting for content size from backend...');
    }

    // Wait for content size from tts-done message (with timeout)
    int? contentSize;
    try {
      contentSize = await _contentSizeCompleter.future
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (kDebugMode) {
        _ttsLog('✅ Received content size: $contentSize bytes');
      }
    } catch (e) {
      if (kDebugMode) {
        _ttsLog('⚠️ Timeout waiting for content size, using null: $e');
      }
      contentSize = null;
    }

    // Generate session ID on first request to track legitimate vs replay requests
    if (_currentSessionId == null) {
      _currentSessionId = 'session_${DateTime.now().microsecondsSinceEpoch}';
      if (kDebugMode) {
        _ttsLog(
            '🆔 LiveTtsAudioSource: Starting new playback session: $_currentSessionId');
      }
    }

    // CRITICAL: Only prevent replay AFTER session is completed
    // Allow multiple requests during the same ExoPlayer session (seeks, retries, etc.)
    if (_sessionCompleted &&
        _hasDeliveredData &&
        (start == null || start == 0)) {
      if (kDebugMode) {
        _ttsLog(
            '🚫 LiveTtsAudioSource: Preventing replay - session $_currentSessionId already completed');
      }
      throw UnsupportedError(
          'TTS stream session $_currentSessionId already completed - refusing replay. '
          'This prevents infinite audio loops between different TTS requests.');
    }

    try {
      // Handle ExoPlayer's range requests by serving real data from buffer
      if (start != null && start > 0) {
        if (kDebugMode) {
          _ttsLog(
              '🔍 LiveTtsAudioSource: Range request for offset $start (buffer size: ${_dataBuffer.length}, contentSize: $contentSize)');
        }

        // Since we have the full audio buffer in memory, serve real data for any valid offset
        if (start < _dataBuffer.length) {
          final availableBytes = _dataBuffer.length - start;
          final responseData = _dataBuffer.sublist(start);

          if (kDebugMode) {
            _ttsLog(
                '✅ LiveTtsAudioSource: Serving $availableBytes bytes from offset $start');
          }

          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: availableBytes,
            offset: start,
            stream: Stream.value(Uint8List.fromList(responseData)),
            contentType: _contentType,
          );
        } else {
          // Offset beyond buffer - return empty response (EOF behavior)
          if (kDebugMode) {
            _ttsLog(
                '✅ LiveTtsAudioSource: EOF request beyond buffer (start: $start >= ${_dataBuffer.length})');
          }

          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: 0,
            offset: start,
            stream: const Stream.empty(),
            contentType: _contentType,
          );
        }
      }

      // Validate content type
      if (_contentType.isEmpty) {
        throw ArgumentError(
            'Content type cannot be empty for live TTS streams');
      }

      // Listening should already be active from constructor (timing fix)
      // This redundant check ensures we don't double-subscribe
      if (!_isListening) {
        if (kDebugMode) {
          _ttsLog(
              '⚠️ LiveTtsAudioSource: Late listener start - this should not happen with timing fix');
        }
        _startListening();
      }

      // Create a custom stream that implements proper DataSource contract
      final dataSourceStream = _createDataSourceStream();

      if (kDebugMode) {
        _ttsLog(
            '🎯 LiveTtsAudioSource: Creating DataSource-compliant stream response');
        _ttsLog('🎯 Content-Type: $_contentType');
        _ttsLog('🎯 Stream Configuration:');
        _ttsLog(
            '  - sourceLength: ${contentSize ?? "null (unknown - streaming)"}');
        _ttsLog(
            '  - contentLength: ${contentSize ?? "null (unknown - streaming)"}');
        _ttsLog('  - offset: 0 (start from beginning)');
        _ttsLog(
            '  - DataSource contract: RESULT_NOTHING_READ when empty, END_OF_INPUT when closed');
      }

      final response = StreamAudioResponse(
        sourceLength: contentSize, // Use content size from backend
        contentLength: contentSize, // Use content size for ExoPlayer completion
        offset: 0, // Always start from beginning (no seeking)
        stream: dataSourceStream, // DataSource-compliant stream
        contentType: _contentType, // MIME type matching backend format
      );

      if (kDebugMode) {
        _ttsLog(
            '✅ LiveTtsAudioSource: Successfully created DataSource-compliant StreamAudioResponse');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        _ttsLog('❌ LiveTtsAudioSource: Error creating stream response: $e');
      }
      rethrow;
    }
  }

  /// Start listening to the broadcast stream and buffer data
  void _startListening() {
    if (_isListening) return;

    _isListening = true;
    if (kDebugMode) {
      _ttsLog(
          '👂 LiveTtsAudioSource: Starting to listen to data stream (immediate capture mode)');
    }

    _streamSubscription = _dataStream.listen(
      (chunk) {
        // CLIENT-SIDE GUARD: Check first chunk for proper Ogg headers (Engineer's recommendation)
        if (_dataBuffer.isEmpty && _isOpusFormat) {
          final firstChunk = chunk;
          if (firstChunk.length >= 4) {
            final headerCheck = String.fromCharCodes(firstChunk.sublist(0, 4));
            if (headerCheck != 'OggS') {
              if (kDebugMode) {
                _ttsLog(
                    '⚠️ LiveTtsAudioSource: Invalid Ogg header detected. Expected "OggS", got "$headerCheck"');
                _ttsLog(
                    '🔧 LiveTtsAudioSource: Injecting cached BOS+tags headers for compatibility');
              }

              // Inject proper Ogg/Opus headers before the malformed data
              final staticOpusHeaders = _getStaticOpusHeaders();
              _dataBuffer.addAll(staticOpusHeaders);

              if (kDebugMode) {
                _ttsLog(
                    '✅ LiveTtsAudioSource: Injected ${staticOpusHeaders.length} bytes of static Opus headers');
              }
            } else {
              if (kDebugMode) {
                _ttsLog(
                    '✅ LiveTtsAudioSource: Valid Ogg header detected, proceeding normally');
              }
            }
          }
        }

        _dataBuffer.addAll(chunk);

        // Check for audio format and headers on first significant chunk
        if (!_headersReady && _dataBuffer.length >= 512) {
          _detectAndProcessHeaders();
        }

        // Throttled logging to prevent UI thread blocking (every 16 chunks ≈ 64KB)
        if (kDebugMode && ((_chunkCount++ & 0x0F) == 0)) {
          _ttsLog(
              '📊 LiveTtsAudioSource: Buffered ${_dataBuffer.length} bytes ($_chunkCount chunks, headersReady: $_headersReady)');
        }
      },
      onDone: () {
        _streamCompleted = true;
        if (kDebugMode) {
          _ttsLog(
              '✅ LiveTtsAudioSource: Stream completed (total: ${_dataBuffer.length} bytes)');
        }
      },
      onError: (error) {
        if (kDebugMode) {
          _ttsLog('❌ LiveTtsAudioSource: Stream error: $error');
        }
        _streamCompleted = true;
      },
    );
  }

  /// Detect audio format and process headers appropriately
  void _detectAndProcessHeaders() {
    if (_headersReady) return;

    // Use pre-determined format based on content type
    if (_isOpusFormat) {
      _processOpusHeaders();
    } else {
      // For WAV or unknown formats, try WAV parsing
      _processWavHeaders();
    }
  }

  /// Process OPUS headers - for streaming, just mark as ready
  void _processOpusHeaders() {
    // For OPUS streaming, we don't need to wait for complete headers
    // The hard-gated processing in SimpleTTSService sends OPUS data directly
    _headersReady = true;

    if (kDebugMode) {
      _ttsLog(
          '✅ LiveTtsAudioSource: OPUS format - headers ready for streaming (${_dataBuffer.length} bytes buffered)');
    }
  }

  /// Process WAV headers - simpler, just verify validity
  void _processWavHeaders() {
    final wavInfo = WavHeaderUtils.parseWavHeader(_dataBuffer);
    if (wavInfo != null) {
      _headersReady = true;

      if (kDebugMode) {
        _ttsLog('✅ LiveTtsAudioSource: WAV headers ready');
        _ttsLog('🎯 Header info: $wavInfo');
      }
    }
  }

  /// Get static Opus headers for fallback injection (Engineer's recommendation)
  /// This prevents rogue backend deploys from breaking audio playback
  Uint8List _getStaticOpusHeaders() {
    // OpusHead (BOS) header - matches backend implementation
    final opusHead = <int>[
      // OggS header for BOS page
      0x4F, 0x67, 0x67, 0x53, // "OggS" - Ogg capture pattern
      0x00, // stream structure version
      0x02, // header type: 2 = BOS (fresh beginning)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // granule pos = 0
      0x01, 0x00, 0x00, 0x00, // bitstream serial no. = 1
      0x00, 0x00, 0x00, 0x00, // page seq no. = 0
      0x00, 0x00, 0x00, 0x00, // CRC (placeholder)
      0x01, // segment count = 1
      0x13, // segment length = 19 bytes
      // OpusHead packet (19 bytes)
      0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
      0x01, // version = 1
      0x01, // channels = 1 (mono)
      0x38, 0x01, // pre-skip = 312 (little-endian)
      0x80, 0xbb, 0x00, 0x00, // input sample rate = 48000
      0x00, 0x00, // output gain = 0 dB
      0x00, // channel mapping family = 0
    ];

    // OpusTags header
    final opusTags = <int>[
      // OggS header for tags page
      0x4F, 0x67, 0x67, 0x53, // "OggS" - Ogg capture pattern
      0x00, // stream structure version
      0x00, // header type: 0 = continuation
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // granule pos = 0
      0x01, 0x00, 0x00, 0x00, // bitstream serial no. = 1
      0x01, 0x00, 0x00, 0x00, // page seq no. = 1
      0x00, 0x00, 0x00, 0x00, // CRC (placeholder)
      0x01, // segment count = 1
      0x10, // segment length = 16 bytes
      // OpusTags packet (16 bytes)
      0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73, // "OpusTags"
      0x08, 0x00, 0x00, 0x00, // vendor string length = 8
      0x6D, 0x61, 0x79, 0x61, 0x2E, 0x61, 0x69, 0x00, // "maya.ai" + padding
      0x00, 0x00, 0x00, 0x00, // user comment list length = 0
    ];

    // Combine headers
    final combined = <int>[];
    combined.addAll(opusHead);
    combined.addAll(opusTags);

    return Uint8List.fromList(combined);
  }

  /// Create a DataSource-compliant stream that follows the contract:
  /// - Returns RESULT_NOTHING_READ when queue empty but WebSocket open
  /// - Returns END_OF_INPUT only when WebSocket closed and no more data
  /// - Simplified for hard-gated format processing
  Stream<Uint8List> _createDataSourceStream() async* {
    const int chunkSize = 4096; // Read in 4KB chunks
    int readPosition = 0;

    if (kDebugMode) {
      final format = _isOpusFormat ? 'OPUS' : 'WAV';
      _ttsLog(
          '🏗️ LiveTtsAudioSource: Created $format DataSource stream with contract implementation');
    }

    while (true) {
      // Wait for headers to be ready (fast for OPUS due to simplified processing)
      if (!_headersReady) {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }

      // Check if we have data available to read
      if (readPosition < _dataBuffer.length) {
        // Calculate how much we can read
        final availableBytes = _dataBuffer.length - readPosition;
        final bytesToRead =
            availableBytes < chunkSize ? availableBytes : chunkSize;

        // Extract chunk from buffer
        final chunk = Uint8List.fromList(
            _dataBuffer.skip(readPosition).take(bytesToRead).toList());

        readPosition += bytesToRead;

        if (kDebugMode && chunk.isNotEmpty) {
          final dataType = _isOpusFormat ? 'OPUS' : 'WAV';
          // _ttsLog('📤 LiveTtsAudioSource: Yielding ${chunk.length} bytes of $dataType to ExoPlayer (position: $readPosition)');
        }

        yield chunk;
        _hasDeliveredData = true; // Mark that we've started delivering data

        if (kDebugMode && chunk.length < chunkSize) {
          // _ttsLog('📤 LiveTtsAudioSource: Delivered final partial chunk (${chunk.length} < $chunkSize) - stream ending soon');
        }
        continue;
      }

      // No data available - check if we should return RESULT_NOTHING_READ or END_OF_INPUT
      // CRITICAL FIX: End stream immediately when WebSocket closed and all data consumed
      if (_webSocketClosed) {
        // FIX: Mark stream as completed when all data is consumed
        _streamCompleted = true;

        // WebSocket is closed - no more data will arrive, end the stream
        if (kDebugMode) {
          final format = _isOpusFormat ? 'OPUS' : 'WAV';
          _ttsLog(
              '🏁 LiveTtsAudioSource: $format stream completed - ending stream (END_OF_INPUT)');
          _ttsLog(
              '🏁 Stream state: webSocketClosed=$_webSocketClosed, streamCompleted=$_streamCompleted, allDataConsumed=${readPosition >= _dataBuffer.length}');
        }

        // Natural completion - let ExoPlayer handle ProcessingState.completed event
        if (kDebugMode) {
          final format = _isOpusFormat ? 'OPUS' : 'WAV';
          _ttsLog(
              '🏁 LiveTtsAudioSource: $format stream completed - ending stream (END_OF_INPUT)');
          _ttsLog('🏁 Session: $_currentSessionId - marking as completed');
          _ttsLog(
              '🏁 Stream state: webSocketClosed=$_webSocketClosed, streamCompleted=$_streamCompleted, allDataConsumed=${readPosition >= _dataBuffer.length}');
          _ttsLog(
              '🎯 LiveTtsAudioSource: Natural completion - letting ExoPlayer fire ProcessingState.completed');
        }

        // Mark session as completed to prevent future replays
        _sessionCompleted = true;

        break;
      } else {
        // WebSocket still open - check format for retry behavior
        if (!_isOpusFormat) {
          // If it's WAV format
          if (kDebugMode) {
            _ttsLog(
                '🏁 LiveTtsAudioSource: WAV stream stalled/no data, ending stream (ExoPlayer will handle)');
          }
          _streamCompleted = true; // Mark as completed
          _sessionCompleted =
              true; // Mark session as completed to prevent replays
          break; // Exit the loop
        } else {
          // If it's OPUS, continue waiting as before
          if (kDebugMode) {
            _ttsLog(
                '⏳ LiveTtsAudioSource: No data available but WebSocket still open - waiting (RESULT_NOTHING_READ)');
          }
          await Future.delayed(const Duration(milliseconds: 10));
          continue;
        }
      }
    }

    // After the loop, ensure session is marked complete
    // This is a redundant assignment here, as it's already handled in the loop's break conditions.
    // Keeping it for clarity, but the critical logic is within the while loop's conditional breaks.
    _sessionCompleted =
        true; // Mark session as completed to prevent future replays (from just_audio)

    if (kDebugMode) {
      final format = _isOpusFormat ? 'OPUS' : 'WAV';
      _ttsLog(
          '🏁 LiveTtsAudioSource: $format DataSource stream ended (total read: $readPosition bytes)');
    }
  }

  /// Cleanup resources and cancel subscriptions
  void dispose() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isListening = false;
    _dataBuffer.clear();

    // Clean up OPUS-specific resources
    _headersReady = false;
    _isOpusFormat = false;
    _opusHeaderInfo = null;
    _completeHeaders = null;

    // Reset session tracking
    _sessionCompleted = true; // Ensure no future requests

    if (kDebugMode) {
      _ttsLog(
          '🧹 LiveTtsAudioSource: Disposed resources for ${_debugName ?? "TTS"} (session: $_currentSessionId)');
    }
  }

  @override
  String toString() {
    return 'LiveTtsAudioSource(contentType: $_contentType, debugName: ${_debugName ?? "unknown"}, bufferSize: ${_dataBuffer.length})';
  }
}
