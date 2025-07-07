import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../utils/opus_header_utils.dart';
import '../utils/wav_header_utils.dart';

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
  
  // CRITICAL: Track WebSocket state for proper DataSource contract
  bool _webSocketClosed = false;
  bool _streamCompleted = false;
  
  // CRITICAL: Prevent infinite replay loops
  int _requestCount = 0;
  bool _hasDeliveredData = false;
  
  // Data buffer and stream subscription for proper DataSource implementation
  final List<int> _dataBuffer = [];
  StreamSubscription<Uint8List>? _streamSubscription;
  bool _isListening = false;
  
  // OPUS header buffering for proper format support
  bool _headersReady = false;
  bool _isOpusFormat = false;
  OpusHeaderInfo? _opusHeaderInfo;
  Uint8List? _completeHeaders;
  
  /// Mark WebSocket as closed (no more data will arrive)
  /// This enables proper END_OF_INPUT signaling to ExoPlayer
  void markWebSocketClosed() {
    _webSocketClosed = true;
    if (kDebugMode) {
      print('🔌 LiveTtsAudioSource: WebSocket marked as closed for ${_debugName ?? "TTS"}');
    }
  }
  
  /// Mark stream as completed (all data received and processed)
  void markStreamCompleted() {
    _streamCompleted = true;
    if (kDebugMode) {
      print('✅ LiveTtsAudioSource: Stream marked as completed for ${_debugName ?? "TTS"}');
    }
  }
  
  /// Get WebSocket closed state (for state-based controller closure)
  bool get isWebSocketClosed => _webSocketClosed;
  
  /// Get stream completed state (for state-based controller closure)
  bool get isStreamCompleted => _streamCompleted;

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
  }) : _dataStream = byteStream, // CRITICAL FIX: Use stream directly, no asBroadcastStream()
       _contentType = contentType,
       _debugName = debugName {
    // Pre-determine format based on content type
    _isOpusFormat = contentType.toLowerCase().contains('ogg') || 
                   contentType.toLowerCase().contains('opus');
    
    if (kDebugMode) {
      print('🎯 LiveTtsAudioSource: Created with direct stream access for $debugName (completion fix applied)');
      print('🎯 Format detection: contentType=$contentType, isOpus=$_isOpusFormat');
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
      print('🔍 LiveTtsAudioSource.request() called:');
      print('  Request ID: $requestId');
      print('  Request Count: $_requestCount');
      print('  Debug Name: ${_debugName ?? "unknown"}');
      print('  Start: $start, End: $end');
      print('  Content Type: $_contentType');
      print('  WebSocket State: closed=$_webSocketClosed, streamCompleted=$_streamCompleted');
      print('  Buffer Size: ${_dataBuffer.length} bytes');
      print('  Has Delivered Data: $_hasDeliveredData');
    }
    
    // CRITICAL: Prevent replay after data has been consumed
    if (_hasDeliveredData && (start == null || start == 0)) {
      if (kDebugMode) {
        print('🚫 LiveTtsAudioSource: Preventing replay - stream already consumed');
      }
      throw UnsupportedError(
        'TTS stream already consumed - refusing replay. '
        'This prevents infinite audio loops.'
      );
    }
    
    try {
      // TTS streams are linear and don't support seeking
      if (start != null && start > 0) {
        if (kDebugMode) {
          print('❌ LiveTtsAudioSource: Seeking not supported (requested start: $start)');
        }
        throw UnsupportedError(
          'Seeking is not supported in live TTS streams. '
          'TTS audio must be played sequentially from the beginning.'
        );
      }

      // Validate content type
      if (_contentType.isEmpty) {
        throw ArgumentError('Content type cannot be empty for live TTS streams');
      }

      // Listening should already be active from constructor (timing fix)
      // This redundant check ensures we don't double-subscribe
      if (!_isListening) {
        if (kDebugMode) {
          print('⚠️ LiveTtsAudioSource: Late listener start - this should not happen with timing fix');
        }
        _startListening();
      }

      // Create a custom stream that implements proper DataSource contract
      final dataSourceStream = _createDataSourceStream();
      
      if (kDebugMode) {
        print('🎯 LiveTtsAudioSource: Creating DataSource-compliant stream response');
        print('🎯 Content-Type: $_contentType');
        print('🎯 Stream Configuration:');
        print('  - sourceLength: null (unknown - streaming)');
        print('  - contentLength: null (unknown - streaming)');
        print('  - offset: 0 (start from beginning)');
        print('  - DataSource contract: RESULT_NOTHING_READ when empty, END_OF_INPUT when closed');
      }

      final response = StreamAudioResponse(
        sourceLength: null,        // Unknown - live stream length not known until complete
        contentLength: null,       // Unknown total content size
        offset: 0,                 // Always start from beginning (no seeking)
        stream: dataSourceStream,  // DataSource-compliant stream
        contentType: _contentType, // MIME type matching backend format
      );
      
      if (kDebugMode) {
        print('✅ LiveTtsAudioSource: Successfully created DataSource-compliant StreamAudioResponse');
      }
      
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('❌ LiveTtsAudioSource: Error creating stream response: $e');
      }
      rethrow;
    }
  }

  /// Start listening to the broadcast stream and buffer data
  void _startListening() {
    if (_isListening) return;
    
    _isListening = true;
    if (kDebugMode) {
      print('👂 LiveTtsAudioSource: Starting to listen to data stream (immediate capture mode)');
    }
    
    _streamSubscription = _dataStream.listen(
      (chunk) {
        _dataBuffer.addAll(chunk);
        
        // Check for audio format and headers on first significant chunk
        if (!_headersReady && _dataBuffer.length >= 512) {
          _detectAndProcessHeaders();
        }
        
        if (kDebugMode) {
          print('📊 LiveTtsAudioSource: Buffered ${chunk.length} bytes (total: ${_dataBuffer.length}, headersReady: $_headersReady)');
        }
      },
      onDone: () {
        _streamCompleted = true;
        if (kDebugMode) {
          print('✅ LiveTtsAudioSource: Stream completed (total: ${_dataBuffer.length} bytes)');
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ LiveTtsAudioSource: Stream error: $error');
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
      print('✅ LiveTtsAudioSource: OPUS format - headers ready for streaming (${_dataBuffer.length} bytes buffered)');
    }
  }

  /// Process WAV headers - simpler, just verify validity
  void _processWavHeaders() {
    final wavInfo = WavHeaderUtils.parseWavHeader(_dataBuffer);
    if (wavInfo != null) {
      _headersReady = true;
      
      if (kDebugMode) {
        print('✅ LiveTtsAudioSource: WAV headers ready');
        print('🎯 Header info: $wavInfo');
      }
    }
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
      print('🏗️ LiveTtsAudioSource: Created $format DataSource stream with contract implementation');
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
        final bytesToRead = availableBytes < chunkSize ? availableBytes : chunkSize;
        
        // Extract chunk from buffer
        final chunk = Uint8List.fromList(
          _dataBuffer.skip(readPosition).take(bytesToRead).toList()
        );
        
        readPosition += bytesToRead;
        
        if (kDebugMode && chunk.isNotEmpty) {
          final dataType = _isOpusFormat ? 'OPUS' : 'WAV';
          print('📤 LiveTtsAudioSource: Yielding ${chunk.length} bytes of $dataType to ExoPlayer (position: $readPosition)');
        }
        
        yield chunk;
        _hasDeliveredData = true; // Mark that we've started delivering data
        continue;
      }
      
      // No data available - check if we should return RESULT_NOTHING_READ or END_OF_INPUT
      // CRITICAL FIX: End stream immediately when WebSocket closed and all data consumed
      if (_webSocketClosed) {
        // WebSocket is closed - no more data will arrive, end the stream
        if (kDebugMode) {
          final format = _isOpusFormat ? 'OPUS' : 'WAV';
          print('🏁 LiveTtsAudioSource: $format stream completed - ending stream (END_OF_INPUT)');
          print('🏁 Stream state: webSocketClosed=$_webSocketClosed, streamCompleted=$_streamCompleted, allDataConsumed=${readPosition >= _dataBuffer.length}');
        }
        break;
      } else {
        // WebSocket still open - wait for more data (RESULT_NOTHING_READ)
        if (kDebugMode) {
          print('⏳ LiveTtsAudioSource: No data available but WebSocket still open - waiting (RESULT_NOTHING_READ)');
        }
        
        // Brief delay to prevent busy waiting
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
    }
    
    if (kDebugMode) {
      final format = _isOpusFormat ? 'OPUS' : 'WAV';
      print('🏁 LiveTtsAudioSource: $format DataSource stream ended (total read: $readPosition bytes)');
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
    
    if (kDebugMode) {
      print('🧹 LiveTtsAudioSource: Disposed resources for ${_debugName ?? "TTS"}');
    }
  }

  @override
  String toString() {
    return 'LiveTtsAudioSource(contentType: $_contentType, debugName: ${_debugName ?? "unknown"}, bufferSize: ${_dataBuffer.length})';
  }
}