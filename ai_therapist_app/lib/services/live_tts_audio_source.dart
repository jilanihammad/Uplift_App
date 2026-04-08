import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../utils/opus_header_utils.dart';
import '../utils/wav_header_utils.dart';
import '../utils/log_channels.dart';
class LiveTtsAudioSource extends StreamAudioSource {
  final Stream<Uint8List> _dataStream;
  final String _contentType;
  final String? _debugName;
  bool get _ttsTraceEnabled => kDebugMode && LogChannels.ttsTrace;
  // CRITICAL: Track WebSocket state for proper DataSource contract
  bool _webSocketClosed = false;
  bool _streamCompleted = false;
  int? _totalContentSize; // Total content size from tts-done message
  final Completer<int?> _contentSizeCompleter = Completer<int?>();
  // CRITICAL: Prevent infinite replay loops
  int _requestCount = 0;
  bool _hasDeliveredData = false;
  String? _currentSessionId;
  bool _sessionCompleted = false;
  // CRITICAL: Track if primary streaming request has been made
  bool _primaryStreamStarted = false;
  int _streamReadPosition = 0; // Track how much has been read from primary stream
  int? _lastRequestTime; // For validation logging
  final List<int> _dataBuffer = [];
  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isListening = false;
  int _chunkCount = 0;
  bool _headersReady = false;
  bool _isOpusFormat = false;
  bool _isMp3Format = false;
  OpusHeaderInfo? _opusHeaderInfo;
  Uint8List? _completeHeaders;
  int? _playbackToken;
  void attachPlaybackToken(int token) {
    _playbackToken = token;
  }
  void markWebSocketClosed([int? totalSize]) {
    _webSocketClosed = true;
    _totalContentSize = totalSize;
    if (!_contentSizeCompleter.isCompleted) {
      _contentSizeCompleter.complete(totalSize);
    }
  }
  void markStreamCompleted() {
    _streamCompleted = true;
  }
  bool get isWebSocketClosed => _webSocketClosed;
  bool get isStreamCompleted => _streamCompleted;
  int get bufferSize => _dataBuffer.length;
  LiveTtsAudioSource(
    Stream<Uint8List> byteStream, {
    String contentType = 'audio/wav',
    String? debugName,
  })  : _dataStream =
            byteStream, // CRITICAL FIX: Use stream directly, no asBroadcastStream()
        _contentType = contentType,
        _debugName = debugName {
    _isOpusFormat = contentType.toLowerCase().contains('ogg') ||
        contentType.toLowerCase().contains('opus');
    _isMp3Format = contentType.toLowerCase().contains('mpeg') ||
        contentType.toLowerCase().contains('mp3');
    // CRITICAL FIX: Start listening immediately to capture broadcast stream events
    _startListening();
  }
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final requestId = DateTime.now().microsecondsSinceEpoch;
    _requestCount++;
    int? contentSize;
    int waitAttempts = 0;
    const maxWaitAttempts = 100; // 100 * 10ms = 1 second max wait for first data
    while (!_headersReady && waitAttempts < maxWaitAttempts) {
      await Future.delayed(const Duration(milliseconds: 10));
      waitAttempts++;
    }
    if (_contentSizeCompleter.isCompleted) {
      contentSize = _totalContentSize;
    }
    if (_currentSessionId == null) {
      _currentSessionId = 'session_${DateTime.now().microsecondsSinceEpoch}';
    }
    // CRITICAL: Handle completed sessions - return EOF to prevent audio repeat
    if (_sessionCompleted && _hasDeliveredData) {
      if (start != null && start > 0 && start < _dataBuffer.length) {
        final availableBytes = _dataBuffer.length - start;
        final responseData = _dataBuffer.sublist(start);
        return StreamAudioResponse(
          sourceLength: _totalContentSize,
          contentLength: availableBytes,
          offset: start,
          stream: Stream.value(Uint8List.fromList(responseData)),
          contentType: _contentType,
        );
      }
      return StreamAudioResponse(
        sourceLength: _totalContentSize,
        contentLength: 0,
        offset: start ?? 0,
        stream: const Stream.empty(),
        contentType: _contentType,
      );
    }
    try {
      if (start != null && start > 0) {
        if (start < _dataBuffer.length) {
          final availableBytes = _dataBuffer.length - start;
          final responseData = _dataBuffer.sublist(start);
          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: availableBytes,
            offset: start,
            stream: Stream.value(Uint8List.fromList(responseData)),
            contentType: _contentType,
          );
        } else {
          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: 0,
            offset: start,
            stream: const Stream.empty(),
            contentType: _contentType,
          );
        }
      }
      if (_contentType.isEmpty) {
        throw ArgumentError(
            'Content type cannot be empty for live TTS streams');
      }
      // CRITICAL: Prevent creating multiple stream generators (causes audio repeat)
      if (_primaryStreamStarted) {
        if (_streamReadPosition < _dataBuffer.length) {
          final availableBytes = _dataBuffer.length - _streamReadPosition;
          final responseData = _dataBuffer.sublist(_streamReadPosition);
          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: availableBytes,
            offset: _streamReadPosition,
            stream: Stream.value(Uint8List.fromList(responseData)),
            contentType: _contentType,
          );
        } else {
          return StreamAudioResponse(
            sourceLength: contentSize,
            contentLength: 0,
            offset: _streamReadPosition,
            stream: const Stream.empty(),
            contentType: _contentType,
          );
        }
      }
      if (!_isListening) {
        _startListening();
      }
      _primaryStreamStarted = true;
      final dataSourceStream = _createDataSourceStream();
      final response = StreamAudioResponse(
        sourceLength: contentSize, // Use content size from backend
        contentLength: contentSize, // Use content size for ExoPlayer completion
        offset: 0, // Always start from beginning (no seeking)
        stream: dataSourceStream, // DataSource-compliant stream
        contentType: _contentType, // MIME type matching backend format
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }
  void _startListening() {
    if (_isListening) return;
    _isListening = true;
    _streamSubscription = _dataStream.listen(
      (chunk) {
        if (_dataBuffer.isEmpty && _isOpusFormat) {
          final firstChunk = chunk;
          if (firstChunk.length >= 4) {
            final headerCheck = String.fromCharCodes(firstChunk.sublist(0, 4));
            if (headerCheck != 'OggS') {
              final staticOpusHeaders = _getStaticOpusHeaders();
              _dataBuffer.addAll(staticOpusHeaders);
            } else {
            }
          }
        }
        _dataBuffer.addAll(chunk);
        if (!_headersReady && _dataBuffer.length >= 512) {
          _detectAndProcessHeaders();
        }
      },
      onDone: () {
        _streamCompleted = true;
      },
      onError: (error) {
        _streamCompleted = true;
      },
    );
  }
  void _detectAndProcessHeaders() {
    if (_headersReady) return;
    if (_isOpusFormat) {
      _processOpusHeaders();
    } else if (_isMp3Format) {
      _processMp3Headers();
    } else {
      _processWavHeaders();
    }
  }
  void _processOpusHeaders() {
    _headersReady = true;
  }
  void _processMp3Headers() {
    _headersReady = true;
  }
  void _processWavHeaders() {
    final wavInfo = WavHeaderUtils.parseWavHeader(_dataBuffer);
    if (wavInfo != null) {
      _headersReady = true;
    }
  }
  Uint8List _getStaticOpusHeaders() {
    final opusHead = <int>[
      0x4F, 0x67, 0x67, 0x53, // "OggS" - Ogg capture pattern
      0x00, // stream structure version
      0x02, // header type: 2 = BOS (fresh beginning)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // granule pos = 0
      0x01, 0x00, 0x00, 0x00, // bitstream serial no. = 1
      0x00, 0x00, 0x00, 0x00, // page seq no. = 0
      0x00, 0x00, 0x00, 0x00, // CRC (placeholder)
      0x01, // segment count = 1
      0x13, // segment length = 19 bytes
      0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
      0x01, // version = 1
      0x01, // channels = 1 (mono)
      0x38, 0x01, // pre-skip = 312 (little-endian)
      0x80, 0xbb, 0x00, 0x00, // input sample rate = 48000
      0x00, 0x00, // output gain = 0 dB
      0x00, // channel mapping family = 0
    ];
    final opusTags = <int>[
      0x4F, 0x67, 0x67, 0x53, // "OggS" - Ogg capture pattern
      0x00, // stream structure version
      0x00, // header type: 0 = continuation
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // granule pos = 0
      0x01, 0x00, 0x00, 0x00, // bitstream serial no. = 1
      0x01, 0x00, 0x00, 0x00, // page seq no. = 1
      0x00, 0x00, 0x00, 0x00, // CRC (placeholder)
      0x01, // segment count = 1
      0x10, // segment length = 16 bytes
      0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73, // "OpusTags"
      0x08, 0x00, 0x00, 0x00, // vendor string length = 8
      0x6D, 0x61, 0x79, 0x61, 0x2E, 0x61, 0x69, 0x00, // "maya.ai" + padding
      0x00, 0x00, 0x00, 0x00, // user comment list length = 0
    ];
    final combined = <int>[];
    combined.addAll(opusHead);
    combined.addAll(opusTags);
    return Uint8List.fromList(combined);
  }
  Stream<Uint8List> _createDataSourceStream() async* {
    const int chunkSize = 4096; // Read in 4KB chunks
    int readPosition = 0;
    while (true) {
      if (!_headersReady) {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
      if (readPosition < _dataBuffer.length) {
        final availableBytes = _dataBuffer.length - readPosition;
        final bytesToRead =
            availableBytes < chunkSize ? availableBytes : chunkSize;
        final chunk = Uint8List.fromList(
            _dataBuffer.skip(readPosition).take(bytesToRead).toList());
        readPosition += bytesToRead;
        _streamReadPosition = readPosition; // Track for subsequent requests
        yield chunk;
        _hasDeliveredData = true; // Mark that we've started delivering data
        continue;
      }
      // CRITICAL FIX: End stream immediately when WebSocket closed and all data consumed
      if (_webSocketClosed) {
        // FIX: Mark stream as completed when all data is consumed
        _streamCompleted = true;
        _sessionCompleted = true;
        break;
      } else {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
    }
    _sessionCompleted =
        true; // Mark session as completed to prevent future replays (from just_audio)
  }
  void dispose() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isListening = false;
    _dataBuffer.clear();
    _headersReady = false;
    _isOpusFormat = false;
    _opusHeaderInfo = null;
    _completeHeaders = null;
    _sessionCompleted = true; // Ensure no future requests
  }
  @override
  String toString() {
    return 'LiveTtsAudioSource(contentType: $_contentType, debugName: ${_debugName ?? "unknown"}, bufferSize: ${_dataBuffer.length})';
  }
}
