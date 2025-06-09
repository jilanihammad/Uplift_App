import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:just_audio/just_audio.dart';

<<<<<<< Updated upstream
=======
/// Connection states for TTS streaming
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Audio chunk for jitter buffer
class AudioChunk {
  final Uint8List data;
  final double timestamp;
  final int sequenceNumber;

  // 🎯 ENHANCED: Multi-sentence tracking
  final String? sentenceId;
  final bool isSentenceEnd;

  AudioChunk({
    required this.data,
    required this.timestamp,
    required this.sequenceNumber,
    this.sentenceId,
    this.isSentenceEnd = false,
  });
}

/// Global TTS session manager to prevent multiple concurrent sessions
class TTSSessionManager {
  static TTSStreamingService? _activeSession;

  /// Close any active TTS session
  static Future<void> closeActiveSession() async {
    if (_activeSession != null) {
      if (kDebugMode) {
        debugPrint('TTSSessionManager: Closing active TTS session');
      }
      await _activeSession!.close();
      _activeSession = null;
    }
  }

  /// Register a new active session
  static void setActiveSession(TTSStreamingService session) {
    _activeSession = session;
  }

  /// Check if there's an active session
  static bool get hasActiveSession => _activeSession != null;
}

/// TTS Streaming Service with enhanced security and production features
>>>>>>> Stashed changes
class TTSStreamingService {
  static const String wsUrl =
      'wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts';

<<<<<<< Updated upstream
=======
  // Protocol configuration
  static const int protocolVersion = 2;

  // 🔧 CRITICAL FIX: Improved buffering constants for high-latency networks
  static const int MIN_CHUNKS_TO_START = 1; // Faster start
  static const int MIN_CHUNKS_TO_START_SLOW_NETWORK =
      6; // More buffering for stability
  static const int MAX_BUFFER_SIZE = 20; // Prevent excessive memory usage
  static const Duration STREAM_TIMEOUT =
      Duration(seconds: 45); // 🔧 FIX: Was 10s, causing premature disconnection

  // Connection management
>>>>>>> Stashed changes
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final List<int> _audioBuffer = [];
  final _player = AudioPlayer();

<<<<<<< Updated upstream
=======
  // Random number generator for conversation IDs
  static final Random _random = Random();

  // Client sequence number for security
  int _clientSequence = 1;

  // Audio playback
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 🎯 ENHANCED: Progressive playback state management
  final List<AudioChunk> _audioBuffer = [];
  Timer? _playbackTimer;
  Timer? _bufferTimeout;
  bool _isPlaying = false;
  bool _streamComplete = false;
  int _lastPlayedChunkIndex = -1;

  // 🚀 ENHANCED: Better completion tracking and stream management
  int _lastPlayedSequence = -1;
  int _expectedTotalChunks = 0;
  bool _isStreamComplete = false;
  final List<AudioChunk> _audioChunks = [];
  Timer? _streamTimeoutTimer;

  // 🔑 ENGINEER'S FIX: Add completion signal tracking
  bool _completionSignalReceived = false;
  bool _shouldStayConnected = true;

  // 🔑 SAFETY TIMEOUT: Belt and suspenders approach
  Timer? _safetyTimeout;

  // Connection resilience constants
  static const int maxReconnectAttempts = 5;
  static const Duration baseReconnectDelay = Duration(seconds: 1);

  // Callbacks
  VoidCallback? _onComplete;
  Function(String)? _onError;
  Function(double)? _onProgress;

  // Performance tracking
  DateTime? _requestStartTime;
  DateTime? _connectionStartTime;
  DateTime? _firstChunkTime;
  DateTime? _lastChunkTime;
  int _totalChunksReceived = 0;
  int _totalBytesReceived = 0;

  StreamSubscription<PlayerState>? _playerStateSubscription;

  // 🔧 CRITICAL FIX: Enhanced timeout protection and network resilience for high-latency
  Timer? _networkReconnectTimer;
  Timer? _chunkReceiptTimeout;
  static const Duration maxTimeBetweenChunks =
      Duration(seconds: 20); // 🔧 FIX: Was 10s
  static const Duration maxTotalStreamTime =
      Duration(seconds: 90); // 🔧 FIX: Was 30s

  // 🔍 NETWORK DIAGNOSTICS: Comprehensive logging methods
  void _logConnectionStateChange(
      ConnectionState oldState, ConnectionState newState,
      [String? reason]) {
    if (kDebugMode) {
      final now = DateTime.now();
      final elapsed = _connectionStartTime != null
          ? now.difference(_connectionStartTime!).inMilliseconds
          : 0;
      debugPrint(
          '🔗 CONNECTION: $oldState → $newState (${elapsed}ms) ${reason != null ? "[$reason]" : ""}');

      // 🚨 CRITICAL: Alert on premature disconnection
      if (newState == ConnectionState.disconnected &&
          elapsed > 5000 &&
          elapsed < 15000 &&
          !_completionSignalReceived) {
        debugPrint('  🚨 SUSPECTED TIMEOUT DISCONNECTION at ${elapsed}ms!');
      }
    }
    _connectionState = newState;
  }

  void _logNetworkPerformance(String event, [Map<String, dynamic>? data]) {
    if (kDebugMode) {
      final now = DateTime.now();
      final elapsed = _requestStartTime != null
          ? now.difference(_requestStartTime!).inMilliseconds
          : 0;
      final prefix = '📊 NETWORK';
      if (data != null) {
        debugPrint('$prefix: $event (${elapsed}ms) - Data: $data');
      } else {
        debugPrint('$prefix: $event (${elapsed}ms)');
      }
    }
  }

  void _logChunkReceived(int sequence, int bytes, bool isEnd) {
    final now = DateTime.now();
    _totalChunksReceived++;
    _totalBytesReceived += bytes;
    _lastChunkTime = now;

    if (_firstChunkTime == null) {
      _firstChunkTime = now;
      final ttfa = _connectionStartTime != null
          ? now.difference(_connectionStartTime!).inMilliseconds
          : 0;
      _logNetworkPerformance('FIRST_CHUNK',
          {'ttfa_ms': ttfa, 'sequence': sequence, 'bytes': bytes});
    }

    // 🔧 OPTIMIZE: Only log every 5th chunk or important events (reduce log spam)
    if (kDebugMode && (sequence % 5 == 0 || isEnd || sequence <= 3)) {
      // 🔧 SIMPLIFIED: Reduce calculation overhead
      final elapsed = _firstChunkTime != null
          ? now.difference(_firstChunkTime!).inMilliseconds
          : 0;
      final avgLatency = elapsed > 0 && _totalChunksReceived > 0
          ? elapsed / _totalChunksReceived
          : 0.0;

      debugPrint(
          '📥 CHUNK_$sequence: ${bytes}B, isEnd=$isEnd, total=${_totalChunksReceived}, avgLatency=${avgLatency.toStringAsFixed(1)}ms');

      // 🚨 CRITICAL: Alert if approaching timeout
      if (elapsed > 8000) {
        // 8 seconds = close to 10s timeout
        debugPrint(
            '  ⚠️  WARNING: ${elapsed}ms elapsed - approaching timeout limit!');
      }
    }
  }

  void _logDisconnection(String reason, [String? details]) {
    final now = DateTime.now();
    final totalTime = _connectionStartTime != null
        ? now.difference(_connectionStartTime!).inMilliseconds
        : 0;
    final chunksPerSec =
        totalTime > 0 ? (_totalChunksReceived * 1000.0 / totalTime) : 0.0;
    final bytesPerSec =
        totalTime > 0 ? (_totalBytesReceived * 1000.0 / totalTime) : 0.0;

    if (kDebugMode) {
      debugPrint('🔌 DISCONNECT: $reason');
      debugPrint(
          '📊 SESSION_STATS: ${totalTime}ms, ${_totalChunksReceived} chunks, ${_totalBytesReceived}B');
      debugPrint(
          '📊 THROUGHPUT: ${chunksPerSec.toStringAsFixed(1)} chunks/s, ${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s');
      debugPrint(
          '📊 BUFFER_STATE: ${_audioChunks.length} buffered, playing=$_isPlaying, complete=$_isStreamComplete');
      if (details != null) debugPrint('📊 DETAILS: $details');
    }
  }

  void _logErrorWithContext(String error, [dynamic exception]) {
    final now = DateTime.now();
    final elapsed = _connectionStartTime != null
        ? now.difference(_connectionStartTime!).inMilliseconds
        : 0;

    if (kDebugMode) {
      debugPrint('❌ ERROR: $error (${elapsed}ms)');
      debugPrint(
          '📊 ERROR_CONTEXT: chunks=${_totalChunksReceived}, bytes=${_totalBytesReceived}, state=$_connectionState');
      if (exception != null) debugPrint('📊 EXCEPTION: $exception');
    }
  }

  /// Main entry point: stream TTS audio from text and play it
  Future<void> streamAndPlay({
    required String text,
    required String conversationId,
    String voice = 'nova',
    String format = 'wav',
    void Function()? onComplete,
    void Function(double)? onProgress,
    void Function(String)? onError,
  }) async {
    // 🔍 INITIALIZE: Set up audio player with comprehensive diagnostics
    await _initializeAudioPlayerWithDiagnostics();

    // Reset state for new session
    _resetStreamState();

    // Close any existing active TTS session first
    await TTSSessionManager.closeActiveSession();

    // 🔍 LOGGING: Start comprehensive session tracking
    _requestStartTime = DateTime.now();
    _connectionStartTime = DateTime.now();
    _logNetworkPerformance('SESSION_START', {
      'text_length': text.length,
      'voice': voice,
      'format': format,
    });

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Starting new session for: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
    }

    _onComplete = onComplete;
    _onProgress = onProgress;
    _onError = onError;

    // 🔑 SAFETY TIMEOUT: Add safety timeout as absolute backup
    _safetyTimeout = Timer(const Duration(minutes: 3), () {
      if (!_completionSignalReceived) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: ⚠️ Safety timeout - forcing completion');
        }
        _completionSignalReceived = true;
        _checkIfCanClose();
      }
    });

    try {
      // Register this as the active session
      TTSSessionManager.setActiveSession(this);

      await connectAndRequestTTS(
        text: text,
        voice: voice,
        responseFormat: format,
        onDone: onComplete,
        onError: onError,
        onProgress: onProgress,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: Stream and play error: $e');
      }
      _handleError('Failed to start TTS streaming: $e');
    } finally {
      // Always cancel safety timeout
      _safetyTimeout?.cancel();
      _safetyTimeout = null;
    }
  }

  /// Enhanced WebSocket connection with JWT authentication and protocol negotiation
>>>>>>> Stashed changes
  Future<void> connectAndRequestTTS({
    required String text,
    String voice = 'sage',
    String responseFormat = 'opus',
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    _audioBuffer.clear();
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

<<<<<<< Updated upstream
    final request = jsonEncode({
=======
    try {
      await _establishConnection();
      await _sendTTSRequest(text, voice, responseFormat);
    } catch (e) {
      final errorMessage = 'TTS connection failed: $e';
      debugPrint('TTSStreaming: $errorMessage');
      _onError?.call(errorMessage);
      dispose();
    }
  }

  /// Establish WebSocket connection with JWT authentication
  Future<void> _establishConnection() async {
    final oldState = _connectionState;
    _logConnectionStateChange(
        oldState, ConnectionState.connecting, 'Starting connection');

    // Get JWT token from Firebase
    _logNetworkPerformance('JWT_REQUEST_START');
    final String? jwt = await _getJwtToken();
    if (jwt == null) {
      _logErrorWithContext('Failed to obtain JWT token');
      throw Exception('Failed to obtain JWT token');
    }
    _logNetworkPerformance('JWT_REQUEST_COMPLETE');

    // Generate a conversation ID
    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';

    _logNetworkPerformance('WEBSOCKET_CONNECT_START', {
      'url': wsUrl,
      'connect_timeout_seconds': 30,
      'keep_alive_timeout_seconds': 60,
    });

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Connecting to $wsUrl with JWT authentication and 30s connect timeout');
    }

    // Create WebSocket connection with JWT token as query parameter
    final uri = Uri.parse(wsUrl).replace(queryParameters: {
      'token': jwt,
      'conversation_id': conversationId,
      'voice': 'nova',
      'format': 'wav',
    });

    try {
      // Use IOWebSocketChannel for mobile with proper headers and sub-protocol
      if (!kIsWeb) {
        _channel = IOWebSocketChannel.connect(
          uri,
          protocols: ['streaming-tts'],
          headers: {
            'X-Supports-Binary-Frames': 'true',
            'User-Agent': 'AI-Therapist-App/1.0',
            // 🔧 NEW: Add connection timeout headers for high-latency networks
            'Connection-Timeout': '60000',
            'Keep-Alive': 'timeout=60',
          },
          // 🔧 CRITICAL: Add connection timeout to handle high latency connections
          connectTimeout: const Duration(seconds: 30),
        );
      } else {
        _channel = WebSocketChannel.connect(
          uri,
          protocols: ['streaming-tts'],
        );
      }

      // Set up message listening
      _streamSubscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _logErrorWithContext('WebSocket stream error', error);

          // 🔧 NEW: More intelligent error handling
          final errorStr = error.toString().toLowerCase();

          if (errorStr.contains('timeout') || errorStr.contains('network')) {
            _logConnectionStateChange(_connectionState, ConnectionState.error,
                'Network/timeout error - attempting recovery');
            _handleNetworkError(error);
          } else if (errorStr.contains('connection closed') ||
              errorStr.contains('socket')) {
            _logConnectionStateChange(_connectionState, ConnectionState.error,
                'Connection closed - checking if graceful');
            // If we have completion signal, this might be normal
            if (_completionSignalReceived) {
              debugPrint(
                  'TTSStreaming: Connection closed after completion - normal');
              _checkIfCanClose();
            } else {
              _onError?.call('Connection lost: $error');
            }
          } else {
            _logConnectionStateChange(_connectionState, ConnectionState.error,
                'Unexpected error: $error');
            _onError?.call('WebSocket connection error: $error');
          }
        },
        onDone: () {
          _logDisconnection(
              'WebSocket stream closed', 'onDone callback triggered');
          _logConnectionStateChange(
              _connectionState, ConnectionState.disconnected, 'Stream done');

          // 🔧 NEW: Check if this was expected
          if (!_completionSignalReceived && _totalChunksReceived > 0) {
            debugPrint(
                'TTSStreaming: 🚨 Unexpected disconnection with ${_totalChunksReceived} chunks received');
            // Try to recover with what we have
            _handleTimeoutWithGracefulRecovery();
          }
        },
        cancelOnError:
            false, // 🔧 IMPORTANT: Don't cancel on recoverable errors
      );

      _logConnectionStateChange(_connectionState, ConnectionState.connected,
          'WebSocket stream established');
      _logNetworkPerformance('WEBSOCKET_CONNECT_COMPLETE');
      debugPrint('TTSStreaming: WebSocket connected successfully');

      // Send initial protocol negotiation
      await _sendInitMessage();
    } catch (e) {
      _connectionState = ConnectionState.error;
      throw Exception('Failed to establish WebSocket connection: $e');
    }
  }

  /// Send initial protocol negotiation message
  Future<void> _sendInitMessage() async {
    final initMessage = {
      'type': 'init',
      'proto_version': protocolVersion,
      'client_seq': _clientSequence++,
    };

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Sending init message with protocol version $protocolVersion');
    }

    _channel!.sink.add(jsonEncode(initMessage));
  }

  /// Get JWT token from Firebase Auth
  Future<String?> _getJwtToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: No authenticated Firebase user found');
        }
        return null;
      }

      // Force token refresh to ensure validity
      final token = await user.getIdToken(true);
      if (kDebugMode) {
        debugPrint('TTSStreaming: Successfully obtained JWT token');
      }
      return token;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: Error obtaining JWT token: $e');
      }
      return null;
    }
  }

  /// Send TTS request with security enhancements
  Future<void> _sendTTSRequest(
      String text, String voice, String responseFormat) async {
    final request = {
      'type': 'audio_request',
>>>>>>> Stashed changes
      'text': text,
      'voice': voice,
      'params': {'response_format': responseFormat},
    });

<<<<<<< Updated upstream
    // Listen for incoming audio chunks
    _subscription = _channel!.stream.listen((event) async {
      try {
        final data = jsonDecode(event);
        if (data['type'] == 'audio_chunk') {
          final chunk = base64Decode(data['data']);
          _audioBuffer.addAll(chunk);
          // Optionally, call onProgress with percent complete (if available)
        } else if (data['type'] == 'done') {
          await _playBufferedAudio(responseFormat);
          onDone?.call();
          await close();
        } else if (data['type'] == 'error') {
          onError?.call(data['detail'] ?? 'Unknown error');
          await close();
        }
      } catch (e) {
        onError?.call('Failed to process TTS stream: $e');
        await close();
=======
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Sending TTS request with client_seq: ${request['client_seq']}');
    }

    _channel!.sink.add(jsonEncode(request));
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      if (message is List<int>) {
        // Binary frame handling
        _handleBinaryFrame(Uint8List.fromList(message));
      } else if (message is String) {
        // JSON frame handling
        final data = jsonDecode(message);
        _handleJsonFrame(data);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: ⚠️ Message processing error (continuing): $e');
      }
      // 🔑 ENHANCED ERROR RECOVERY: Don't close connection for minor parse errors
      // Only call _handleError for critical failures, not minor parsing issues
      // This keeps the connection alive to receive the completion signal
    }
  }

  /// Handle binary WebSocket frames (11-byte header format)
  void _handleBinaryFrame(Uint8List data) {
    if (data.length < 11) return;

    // Parse 11-byte header
    final buffer = data.buffer.asByteData();
    final audioLength = buffer.getUint32(0, Endian.little);
    final timestamp = buffer.getFloat32(4, Endian.little);
    final sequenceNumber = buffer.getUint16(8, Endian.little);
    final frameType = data[10];

    if (frameType == 0x01) {
      // Audio frame
      final audioData = data.sublist(11, 11 + audioLength);
      _handleAudioChunk(audioData, timestamp, sequenceNumber);
    }
  }

  /// Handle JSON WebSocket frames
  void _handleJsonFrame(Map<String, dynamic> data) {
    final frameType = data['type'] as String?;

    if (kDebugMode) {
      debugPrint('🔍 FRAME DEBUG: Received JSON frame type: "$frameType"');
    }

    switch (frameType) {
      case 'init_ack':
      case 'init_response':
        if (kDebugMode) debugPrint('🔍 FRAME DEBUG: Handling init response');
        _handleInitResponse(data);
        break;
      case 'audio_request_received':
        if (kDebugMode)
          debugPrint('🔍 FRAME DEBUG: Handling audio request received');
        _handleAudioRequestReceived(data);
        break;
      case 'audio_chunk':
        if (kDebugMode)
          debugPrint('🔍 FRAME DEBUG: Handling audio chunk (JSON)');
        _handleJsonAudioChunk(data);
        break;
      case 'audio':
        if (kDebugMode) debugPrint('🔍 FRAME DEBUG: Handling audio frame');
        _handleAudioFrame(data);
        break;
      case 'tts_complete':
        // 🔧 FIX: This is the ONLY completion we trust
        if (kDebugMode)
          debugPrint('🔍 FRAME DEBUG: Handling TTS completion signal');
        _handleTtsComplete(data);
        break;
      case 'done':
      case 'complete':
        // 🔧 FIX: Log but ignore legacy completion signals
        if (kDebugMode) {
          debugPrint(
              '🔍 FRAME DEBUG: ⚠️ Ignoring legacy completion signal: "$frameType"');
        }
        // DO NOT call _handleStreamComplete here!
        break;
      case 'error':
        if (kDebugMode) debugPrint('🔍 FRAME DEBUG: Handling server error');
        _handleServerError(data);
        break;
      default:
        if (kDebugMode)
          debugPrint('🔍 FRAME DEBUG: ⚠️ Unknown frame type: "$frameType"');
        break;
    }
  }

  /// Handle server's initialization response
  void _handleInitResponse(Map<String, dynamic> data) {
    final serverVersion = data['proto_version'] as int?;
    if (kDebugMode) {
      debugPrint('TTSStreaming: Server protocol version: $serverVersion');
    }
  }

  /// Handle audio request acknowledgment
  void _handleAudioRequestReceived(Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint('TTSStreaming: Audio request acknowledged');
    }
  }

  /// Handle JSON audio chunks (legacy format)
  void _handleJsonAudioChunk(Map<String, dynamic> data) {
    try {
      final chunk = base64Decode(data['data'] as String);
      final timestamp = (data['timestamp'] as num?)?.toDouble() ?? 0.0;
      final sequenceNumber = data['sequence'] as int? ?? 0;
      _handleAudioChunk(chunk, timestamp, sequenceNumber);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: Error processing JSON audio chunk: $e');
      }
    }
  }

  /// Handle 'audio' frames from backend
  void _handleAudioFrame(Map<String, dynamic> data) {
    try {
      final audioData = data['audio_data'] as String?;
      final sequence = data['sequence'] as int? ?? 0;
      final isEnd = data['is_sentence_end'] as bool? ?? false;
      final sentenceId = data['sentence_id'] as String?;

      if (kDebugMode) {
        debugPrint(
            '🔍 AUDIO FRAME DEBUG: Sequence: $sequence, is_sentence_end: $isEnd, sentence_id: $sentenceId');
        debugPrint(
            '🔍 AUDIO FRAME DEBUG: Audio data length: ${audioData?.length ?? 0}');
      }

      double timestamp = sequence.toDouble();
      final timestampRaw = data['timestamp'];
      if (timestampRaw is num) {
        timestamp = timestampRaw.toDouble();
      } else if (timestampRaw is String) {
        try {
          final dateTime = DateTime.parse(timestampRaw);
          timestamp = dateTime.millisecondsSinceEpoch.toDouble();
        } catch (e) {
          timestamp = sequence.toDouble();
        }
      }

      if (audioData != null) {
        final chunk = base64Decode(audioData);

        // 🔍 LOGGING: Track chunk reception with comprehensive metrics
        _logChunkReceived(sequence, chunk.length, isEnd);

        // 🔧 FIX: Simplified chunk handling - only buffer and play, no sentence tracking
        _audioChunks.add(AudioChunk(
          data: Uint8List.fromList(chunk),
          timestamp: timestamp,
          sequenceNumber: sequence,
          sentenceId: sentenceId,
          isSentenceEnd: isEnd,
        ));

        // Also handle with existing method for compatibility
        _handleAudioChunk(chunk, timestamp, sequence);

        // Continue playback if it was waiting
        if (!_isPlaying && _audioChunks.length >= MIN_CHUNKS_TO_START) {
          _startProgressivePlayback();
        }

        // NO completion logic here - only trust tts_complete signal!
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: ERROR in _handleAudioFrame: $e');
      }
    }
  }

  /// 🎯 ENHANCED: Audio chunk handling with improved progressive playback logic
  void _handleAudioChunk(
      List<int> chunkData, double timestamp, int sequenceNumber) {
    // 🛡️ NEW: Reset chunk timeout on each chunk received
    _resetChunkTimeout();

    // Record start time on first chunk
    if (_requestStartTime == null) {
      _requestStartTime = DateTime.now();
      if (kDebugMode) {
        debugPrint('TTSStreaming: First chunk received, starting timer');
      }
    }

    // Add chunk to buffer
    _audioBuffer.add(AudioChunk(
      data: Uint8List.fromList(chunkData),
      timestamp: timestamp,
      sequenceNumber: sequenceNumber,
      sentenceId: null,
      isSentenceEnd: false,
    ));

    if (kDebugMode) {
      final chunkType =
          _isWavFile(Uint8List.fromList(chunkData)) ? 'WAV' : 'RAW';
      debugPrint(
          'TTSStreaming: 📥 Chunk $sequenceNumber ($chunkType, ${chunkData.length}B) - Buffer: ${_audioBuffer.length} total');
      debugPrint(
          'TTSStreaming: 📊 Buffer state - Total chunks: ${_audioBuffer.length}, Last played: $_lastPlayedChunkIndex, Currently playing: $_isPlaying');

      // Calculate chunks available for playback
      final availableForPlayback =
          _audioBuffer.length - (_lastPlayedChunkIndex + 1);
      debugPrint(
          'TTSStreaming: 🎵 Chunks available for playback: $availableForPlayback');
    }

    // Progress callback (simplified)
    _onProgress?.call(0.5);

    // 🔧 SIMPLIFIED: Legacy buffer maintained for compatibility but enhanced system handles playback
    // The enhanced system (_audioChunks) manages all actual playback to prevent conflicts

    if (kDebugMode && _audioBuffer.length % 10 == 0) {
      debugPrint(
          'TTSStreaming: 📊 Enhanced system status: ${_audioChunks.length} chunks, last played: $_lastPlayedSequence');
    }

    // 🔑 ENGINEER'S FIX: Check if we can close after adding chunk
    // (handles case where completion signal arrived while buffering)
    if (_completionSignalReceived) {
      _checkIfCanClose();
    }
  }

  /// 🔧 STUBBED: Legacy completion handler - should never be called
  void _handleStreamComplete(Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: ⚠️ Legacy _handleStreamComplete called - ignoring');
    }
    // Do nothing - this should never be called with the updated code
  }

  /// Handle server errors
  void _handleServerError(Map<String, dynamic> data) {
    final errorMessage = data['detail'] as String? ?? 'Unknown server error';
    _handleError('Server error: $errorMessage');
  }

  /// 🚀 ENHANCED: Dynamic progressive playback with improved buffering
  Future<void> _startProgressivePlayback() async {
    // 🎯 OPTIMIZED: Adaptive buffering based on network conditions
    final adaptiveMinChunks = _getAdaptiveMinChunks();

    if (_isPlaying || _audioChunks.length < adaptiveMinChunks) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🔄 Buffering... (${_audioChunks.length}/$adaptiveMinChunks chunks)');
      }
      return;
    }

    _isPlaying = true;
    _startTimeout(); // Start stream timeout

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🚀 Starting enhanced progressive playback with ${_audioChunks.length} chunks (adaptive: $adaptiveMinChunks)');
    }

    // 🔧 FIX: Use chunk-based progressive playback for better reliability
    // This ensures all chunks are played without skipping
    while (!_isStreamComplete || _audioChunks.isNotEmpty) {
      // Wait for minimum chunks if buffer is low and stream is still active
      if (_audioChunks.length < 2 && !_isStreamComplete) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: ⏳ Waiting for more chunks...');
        }
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // Get all available unplayed chunks
      final availableChunks = _getUnplayedChunks();
      if (availableChunks.isEmpty) {
        if (_isStreamComplete) {
          if (kDebugMode) {
            debugPrint(
                'TTSStreaming: 🏁 No more chunks and stream complete - ending playback');
          }
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      // 🔧 FIX: Play chunks in smaller batches for smoother playback
      const int batchSize = 5; // Play up to 5 chunks at a time
      final chunkBatch = availableChunks.take(batchSize).toList();

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🎵 Playing batch of ${chunkBatch.length} chunks (sequences ${chunkBatch.first.sequenceNumber}-${chunkBatch.last.sequenceNumber})');
      }

      // Play batch of chunks
      await _playChunkBatch(chunkBatch);

      // 🔧 FIX: Check if we should continue or if stream is complete
      if (_isStreamComplete && _audioChunks.isEmpty) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: 🏁 All chunks played and stream complete');
        }
        break;
      }

      // Small delay between batches to prevent overwhelming the audio system
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _isPlaying = false;
    _streamTimeoutTimer?.cancel();

    if (kDebugMode) {
      debugPrint('TTSStreaming: 🏁 Progressive playback complete');
    }

    // Notify completion when truly done
    _notifyTTSComplete();
  }

  /// 🚀 OPTIMIZED: Get adaptive minimum chunks based on network conditions
  int _getAdaptiveMinChunks() {
    // Simple heuristic: if we're getting chunks quickly, use lower buffer
    if (_audioChunks.length >= 3 && _requestStartTime != null) {
      final elapsed =
          DateTime.now().difference(_requestStartTime!).inMilliseconds;
      final chunksPerSecond = (_audioChunks.length / elapsed) * 1000;

      if (chunksPerSecond > 5) {
        // Fast network - use minimal buffering for low latency
        return MIN_CHUNKS_TO_START;
      }
    }

    // Slower network or not enough data - use more buffering for smoothness
    return MIN_CHUNKS_TO_START_SLOW_NETWORK;
  }

  /// 🚀 ENHANCED: Get unplayed chunks with proper sequencing
  List<AudioChunk> _getUnplayedChunks() {
    return _audioChunks
        .where((chunk) => chunk.sequenceNumber > _lastPlayedSequence)
        .toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  /// 🚀 ENHANCED: Play batch of chunks with proper tracking and performance monitoring
  Future<void> _playChunkBatch(List<AudioChunk> chunks) async {
    if (chunks.isEmpty) return;

    final batchStartTime = DateTime.now();

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🎵 Playing chunks ${chunks.first.sequenceNumber} to ${chunks.last.sequenceNumber}');
    }

    try {
      // 🔍 PERFORMANCE: Monitor memory usage during batch processing
      final totalChunkBytes =
          chunks.fold<int>(0, (sum, chunk) => sum + chunk.data.length);
      if (kDebugMode) {
        debugPrint('🎵 BATCH_PERF: Processing batch of $totalChunkBytes bytes');
      }

      final audioData = _concatenateChunks(chunks);
      final wavData = _createWavFromData(audioData);

      // 🔍 PERFORMANCE: Log actual file size vs expected
      if (kDebugMode) {
        debugPrint(
            '🎵 BATCH_PERF: Concatenated size: ${audioData.length} bytes');
        debugPrint('🎵 BATCH_PERF: WAV file size: ${wavData.length} bytes');
      }

      // Play audio and wait for completion
      await _playAudioData(wavData);

      // 🔍 PERFORMANCE: Log batch completion time
      final batchDuration =
          DateTime.now().difference(batchStartTime).inMilliseconds;
      if (kDebugMode) {
        debugPrint('🎵 BATCH_PERF: Batch completed in ${batchDuration}ms');
      }

      // Update last played sequence
      _lastPlayedSequence = chunks.last.sequenceNumber;

      // Remove played chunks from buffer
      _audioChunks.removeWhere((c) => c.sequenceNumber <= _lastPlayedSequence);

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: ✅ Completed batch, last played sequence: $_lastPlayedSequence');
      }
    } catch (e) {
      if (kDebugMode) {
        final errorDuration =
            DateTime.now().difference(batchStartTime).inMilliseconds;
        debugPrint(
            'TTSStreaming: ❌ Error playing chunk batch after ${errorDuration}ms: $e');
      }
      rethrow;
    }
  }

  /// 🔧 SIMPLIFIED: Just check if done playing all chunks
  void _notifyTTSComplete() {
    // Simply check if we're done playing all chunks
    if (_audioChunks.isEmpty && !_isPlaying) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🎯 All chunks played - checking for completion');
      }

      // If we already have the completion signal, we can close
      if (_completionSignalReceived) {
        _checkIfCanClose();
      }
    }
  }

  /// Legacy buffered playback - REMOVED to prevent conflict with enhanced system
  /// The enhanced progressive playback system handles all audio playback now

  /// 🎯 Enhanced concatenation with explicit range and detailed logging
  Uint8List _concatenateAudioChunks(
      List<AudioChunk> chunks, int startIndex, int endIndex) {
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🔧 Concatenating chunks $startIndex to ${endIndex - 1}');
      debugPrint('TTSStreaming: Chunk buffer size: ${chunks.length}');
    }

    if (startIndex >= endIndex || startIndex >= chunks.length) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: ⚠️ Invalid range - no chunks to concatenate');
      }
      return Uint8List(0);
    }

    final List<int> pureAudioData = [];
    int totalProcessedBytes = 0;
    int wavChunks = 0;
    int rawChunks = 0;
    int malformedChunks = 0;

    for (int i = startIndex; i < endIndex && i < chunks.length; i++) {
      final chunkData = chunks[i].data;

      if (_isWavFile(chunkData)) {
        wavChunks++;
        if (chunkData.length > 44) {
          // Extract pure audio data (skip 44-byte WAV header)
          final audioOnly = chunkData.sublist(44);
          pureAudioData.addAll(audioOnly);
          totalProcessedBytes += audioOnly.length;

          if (kDebugMode && i == startIndex) {
            debugPrint(
                'TTSStreaming: 🎵 WAV chunk - extracted ${audioOnly.length} bytes (skipped header)');
          }
        } else {
          // Malformed WAV chunk - log warning but continue
          malformedChunks++;
          if (kDebugMode) {
            debugPrint(
                'TTSStreaming: ⚠️ Malformed WAV chunk $i (${chunkData.length} bytes < 44)');
          }
          // Use what we have
          pureAudioData.addAll(chunkData);
          totalProcessedBytes += chunkData.length;
        }
      } else {
        rawChunks++;
        // Raw audio data - use directly
        pureAudioData.addAll(chunkData);
        totalProcessedBytes += chunkData.length;

        if (kDebugMode && i == startIndex) {
          debugPrint(
              'TTSStreaming: 🎵 Raw audio chunk - using ${chunkData.length} bytes directly');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('TTSStreaming: ✅ Audio extraction complete:');
      debugPrint('  📊 Processed ${endIndex - startIndex} chunks');
      debugPrint('  🎵 $wavChunks WAV chunks + $rawChunks raw chunks');
      if (malformedChunks > 0) {
        debugPrint('  ⚠️ $malformedChunks malformed chunks');
      }
      debugPrint('  📦 Total audio data: $totalProcessedBytes bytes');
    }

    return Uint8List.fromList(pureAudioData);
  }

  /// Detect if chunk is a WAV file
  bool _isWavFile(Uint8List data) {
    if (data.length < 12) return false;

    return data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x41 &&
        data[10] == 0x56 &&
        data[11] == 0x45;
  }

  /// Create temporary audio file for playback with comprehensive error logging
  Future<File> _createTempAudioFile(Uint8List audioData) async {
    try {
      if (kDebugMode) {
        debugPrint(
            '🎵 TEMP_FILE: Creating temp file for ${audioData.length} bytes');
      }

      final tempDir = await getTemporaryDirectory();
      if (kDebugMode) {
        debugPrint('🎵 TEMP_FILE: Temp directory: ${tempDir.path}');
        debugPrint('🎵 TEMP_FILE: Directory exists: ${await tempDir.exists()}');
      }

      final tempFile = File(
        '${tempDir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (kDebugMode) {
        debugPrint('🎵 TEMP_FILE: Writing to: ${tempFile.path}');
      }

      await tempFile.writeAsBytes(audioData);

      if (kDebugMode) {
        debugPrint('🎵 TEMP_FILE: ✅ File written successfully');
        debugPrint(
            '🎵 TEMP_FILE: Final file size: ${await tempFile.length()} bytes');
      }

      return tempFile;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎵 TEMP_FILE: ❌ ERROR creating temp file: $e');
        debugPrint('🎵 TEMP_FILE: ❌ Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Create a proper WAV file with header and audio data + validation logging
  Uint8List _createWavFile(Uint8List audioData) {
    if (kDebugMode) {
      debugPrint(
          '🎵 WAV_CREATION: Creating WAV file for ${audioData.length} bytes of audio data');
    }

    final audioLength = audioData.length;
    final fileSize = 36 + audioLength;
    final wavHeader = ByteData(44);

    // RIFF header
    wavHeader.setUint8(0, 0x52); // 'R'
    wavHeader.setUint8(1, 0x49); // 'I'
    wavHeader.setUint8(2, 0x46); // 'F'
    wavHeader.setUint8(3, 0x46); // 'F'
    wavHeader.setUint32(4, fileSize, Endian.little);
    wavHeader.setUint8(8, 0x57); // 'W'
    wavHeader.setUint8(9, 0x41); // 'A'
    wavHeader.setUint8(10, 0x56); // 'V'
    wavHeader.setUint8(11, 0x45); // 'E'

    // fmt chunk
    wavHeader.setUint8(12, 0x66); // 'f'
    wavHeader.setUint8(13, 0x6D); // 'm'
    wavHeader.setUint8(14, 0x74); // 't'
    wavHeader.setUint8(15, 0x20); // ' '
    wavHeader.setUint32(16, 16, Endian.little);
    wavHeader.setUint16(20, 1, Endian.little);
    wavHeader.setUint16(22, 1, Endian.little);
    wavHeader.setUint32(24, 24000, Endian.little);
    wavHeader.setUint32(28, 48000, Endian.little);
    wavHeader.setUint16(32, 2, Endian.little);
    wavHeader.setUint16(34, 16, Endian.little);

    // data chunk
    wavHeader.setUint8(36, 0x64); // 'd'
    wavHeader.setUint8(37, 0x61); // 'a'
    wavHeader.setUint8(38, 0x74); // 't'
    wavHeader.setUint8(39, 0x61); // 'a'
    wavHeader.setUint32(40, audioLength, Endian.little);

    // Combine header and audio data
    final completeFile = Uint8List(44 + audioLength);
    completeFile.setRange(0, 44, wavHeader.buffer.asUint8List());
    completeFile.setRange(44, 44 + audioLength, audioData);

    // 🔍 VALIDATION: Check the created WAV file
    if (kDebugMode) {
      debugPrint('🎵 WAV_CREATION: ✅ Created WAV file:');
      debugPrint('  📊 Total size: ${completeFile.length} bytes');
      debugPrint('  📊 Header size: 44 bytes');
      debugPrint('  📊 Audio data size: $audioLength bytes');
      debugPrint('  📊 File size in header: $fileSize');

      // Validate RIFF header
      final riffCheck = String.fromCharCodes(completeFile.sublist(0, 4));
      final waveCheck = String.fromCharCodes(completeFile.sublist(8, 12));
      debugPrint('  🔍 RIFF header: "$riffCheck" (should be "RIFF")');
      debugPrint('  🔍 WAVE header: "$waveCheck" (should be "WAVE")');

      // Check if audio data seems valid (not all zeros)
      final firstFewBytes = audioData.take(10).toList();
      final hasNonZero = firstFewBytes.any((byte) => byte != 0);
      debugPrint(
          '  🔍 Audio data validity: ${hasNonZero ? "Has non-zero data" : "WARNING: All zeros"}');
      debugPrint('  🔍 First 10 audio bytes: $firstFewBytes');
    }

    return completeFile;
  }

  /// Schedule completion callback
  void _scheduleCompletion() {
    _isPlaying = false;
    _audioBuffer.clear();
    _lastPlayedChunkIndex = -1;

    if (kDebugMode) {
      debugPrint('TTSStreaming: Scheduling completion callback');
    }

    // 🔑 ENGINEER'S FIX: Don't call completion here - let _finalizeAndClose handle it
    // Removed: _onComplete?.call(); to prevent double completion calls
  }

  /// Clean up temporary audio file safely
  void _cleanupTempFile(File tempFile) {
    try {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    } catch (e) {
      // Non-critical error - don't crash
    }
  }

  /// Centralized error handling
  Future<void> _handleError(String error) async {
    if (kDebugMode) {
      debugPrint('TTSStreaming: Error: $error');
    }

    _connectionState = ConnectionState.error;

    String userMessage = error;
    if (error.contains('Connection')) {
      userMessage =
          'Unable to connect to speech service. Please check your internet connection.';
    } else if (error.contains('JWT') || error.contains('auth')) {
      userMessage = 'Authentication failed. Please sign in again.';
    }

    _onError?.call(userMessage);
    await close();
  }

  /// Generate unique request ID
  String _generateRequestId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  /// Reset stream state for new request
  void _resetStreamState() {
    _streamComplete = false;
    _lastPlayedChunkIndex = -1;
    _audioBuffer.clear();
    _isPlaying = false;
    _requestStartTime = null;
    _lastChunkTime = null;

    // 🚀 ENHANCED: Reset new state variables
    _lastPlayedSequence = -1;
    _expectedTotalChunks = 0;
    _isStreamComplete = false;
    _audioChunks.clear();
    _streamTimeoutTimer?.cancel();
    _streamTimeoutTimer = null;

    // 🔑 ENGINEER'S FIX: Reset completion tracking flags
    _completionSignalReceived = false;
    _shouldStayConnected = true;

    // 🔑 SAFETY TIMEOUT: Cancel any existing safety timeout
    _safetyTimeout?.cancel();
    _safetyTimeout = null;

    // 🛡️ NEW: Setup timeout protection
    _setupTimeoutProtection();
  }

  /// Enhanced timeout protection and network resilience
  void _setupTimeoutProtection() {
    // Cancel any existing timers
    _chunkReceiptTimeout?.cancel();
    _networkReconnectTimer?.cancel();

    // Set up chunk receipt timeout (resets on each chunk)
    _resetChunkTimeout();

    // Set up maximum total stream time protection
    _networkReconnectTimer = Timer(maxTotalStreamTime, () {
      if (!_completionSignalReceived) {
        if (kDebugMode) {
          debugPrint(
              'TTSStreaming: 🔄 Maximum stream time reached - checking for completion');
        }
        _handleTimeoutWithGracefulRecovery();
      }
    });
  }

  /// Reset the chunk receipt timeout (call on each chunk received)
  void _resetChunkTimeout() {
    _chunkReceiptTimeout?.cancel();
    _lastChunkTime = DateTime.now();

    _chunkReceiptTimeout = Timer(maxTimeBetweenChunks, () {
      if (!_completionSignalReceived) {
        _logNetworkPerformance('CHUNK_TIMEOUT', {
          'timeout_seconds': maxTimeBetweenChunks.inSeconds,
          'chunks_received': _totalChunksReceived,
          'elapsed_ms': _connectionStartTime != null
              ? DateTime.now().difference(_connectionStartTime!).inMilliseconds
              : 0
        });
        _handleTimeoutWithGracefulRecovery();
      }
    });
  }

  /// Graceful timeout recovery - try to complete with existing chunks
  void _handleTimeoutWithGracefulRecovery() {
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🛡️ Graceful timeout recovery with ${_audioBuffer.length} chunks');
    }

    // If we have chunks, treat as completion
    if (_audioBuffer.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🎵 Playing ${_audioBuffer.length} buffered chunks before timeout completion');
      }

      // Mark as completed and let existing chunks play
      _completionSignalReceived = true;
      _streamComplete = true;
      _checkIfCanClose();
    } else {
      // No chunks received - this is a real error
      _handleError('Stream timeout: No audio chunks received');
    }
  }

  /// Close connection and clean up resources
  Future<void> close() async {
    // 🔍 LOGGING: Track close operation with full context
    _logDisconnection('Manual close() called',
        'Completion: $_completionSignalReceived, Playing: $_isPlaying, Chunks: ${_audioChunks.length}');

    _playbackTimer?.cancel();
    _playbackTimer = null;

    _bufferTimeout?.cancel();
    _bufferTimeout = null;

    // 🔑 SAFETY TIMEOUT: Cancel safety timeout on close
    _safetyTimeout?.cancel();
    _safetyTimeout = null;

    // 🛡️ NEW: Cancel timeout protection timers
    _chunkReceiptTimeout?.cancel();
    _chunkReceiptTimeout = null;

    _networkReconnectTimer?.cancel();
    _networkReconnectTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    await _playerStateSubscription?.cancel();
    _playerStateSubscription = null;

    await _channel?.sink.close();
    _channel = null;

    await _audioPlayer.stop();
    _audioBuffer.clear();
    _isPlaying = false;
    _logConnectionStateChange(_connectionState, ConnectionState.disconnected,
        'Manual close() completed');
  }

  /// Dispose of the service and release all resources
  Future<void> dispose() async {
    _logDisconnection('Dispose() called', 'Full cleanup and resource release');
    await close();
    _audioPlayer.dispose();
  }

  /// Get current connection state
  ConnectionState get connectionState => _connectionState;

  /// Check if currently connected
  bool get isConnected => _connectionState == ConnectionState.connected;

  /// Interrupt current playback
  Future<void> interrupt() async {
    _logDisconnection(
        'Manual interrupt() called', 'User-triggered playback interruption');

    if (_channel != null && isConnected) {
      final interruptFrame = {
        'type': 'interrupt',
        'client_seq': _clientSequence++,
      };
      _channel!.sink.add(jsonEncode(interruptFrame));
    }

    await _audioPlayer.stop();
    _audioBuffer.clear();
    _isPlaying = false;
  }

  /// 🔧 NEW: Handle network errors gracefully
  void _handleNetworkError(dynamic error) {
    final elapsed = _connectionStartTime != null
        ? DateTime.now().difference(_connectionStartTime!).inMilliseconds
        : 0;

    if (_completionSignalReceived) {
      debugPrint(
          'TTSStreaming: Network error after completion ($elapsed ms) - finishing gracefully');
      _checkIfCanClose();
    } else if (_totalChunksReceived > 0) {
      debugPrint(
          'TTSStreaming: Network error with ${_totalChunksReceived} chunks received ($elapsed ms) - attempting recovery');
      _handleTimeoutWithGracefulRecovery();
    } else {
      debugPrint(
          'TTSStreaming: Early network error ($elapsed ms) - this is a real error');
      _onError?.call('Network connection error: $error');
    }
  }

  /// 🎯 NEW: Handle TTS completion signal from backend (proper completion waiting)
  void _handleTtsComplete(Map<String, dynamic> data) {
    if (kDebugMode) {
      final requestId = data['request_id'] as String?;
      final status = data['status'] as String?;
      final totalChunks = data['total_chunks'] as int?;

      debugPrint('TTSStreaming: 🏁 TTS FINAL completion signal received');
      debugPrint(
          'TTSStreaming: 📊 Request: $requestId, Status: $status, Total chunks: $totalChunks');
      debugPrint(
          'TTSStreaming: 📊 Received ${_audioChunks.length} chunks total');
    }

    // Store total chunks if provided (for debugging)
    if (data['total_chunks'] != null) {
      _expectedTotalChunks = data['total_chunks'] as int;
    }

    // 🎯 SIMPLIFIED: This is THE ONLY place where completion is triggered
    _completionSignalReceived = true;
    _streamComplete = true;
    _isStreamComplete = true;
    _bufferTimeout?.cancel();
    _bufferTimeout = null;

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🏁 Backend signaled FULL message complete - finalizing playback');
    }

    // Check if we can close now (after both completion signal AND playback done)
    _checkIfCanClose();
  }

  /// 🔑 ENGINEER'S FIX: Centralized logic to check if connection can be safely closed
  void _checkIfCanClose() {
    // Check both buffer systems for compatibility
    final hasUnplayedInBuffer =
        _audioBuffer.length > (_lastPlayedChunkIndex + 1);
    final hasUnplayedInChunks = _audioChunks.isNotEmpty;

    if (_completionSignalReceived &&
        !_isPlaying &&
        !hasUnplayedInBuffer &&
        !hasUnplayedInChunks) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🔒 All conditions met - safe to close connection');
      }
      _finalizeAndClose();
    } else {
      if (kDebugMode) {
        debugPrint('TTSStreaming: ⏳ Waiting to close:');
        debugPrint('  - Completion signal: $_completionSignalReceived');
        debugPrint('  - Currently playing: $_isPlaying');
        debugPrint('  - Unplayed in buffer: $hasUnplayedInBuffer');
        debugPrint('  - Unplayed in chunks: $hasUnplayedInChunks');
      }
    }
  }

  /// 🔑 NEW: Safe WebSocket connection closure after TTS completion
  void _finalizeAndClose() {
    _logDisconnection('Normal completion - finalize and close',
        'TTS session completed successfully, all chunks processed');

    _onComplete?.call();

    // Now it's safe to close
    Timer(const Duration(milliseconds: 100), () async {
      try {
        await _channel?.sink.close();
        _channel = null;
        _logConnectionStateChange(_connectionState,
            ConnectionState.disconnected, 'TTS completion finalized');

        if (kDebugMode) {
          debugPrint('TTSStreaming: WebSocket connection closed successfully');
        }
      } catch (e) {
        _logErrorWithContext('Error closing WebSocket in _finalizeAndClose', e);
>>>>>>> Stashed changes
      }
    }, onError: (err) async {
      onError?.call('WebSocket error: $err');
      await close();
    }, onDone: () async {
      await close();
    });

    // Send the TTS request
    _channel!.sink.add(request);
  }

  Future<void> _playBufferedAudio(String format) async {
    try {
      // Write buffer to a temporary file and play from file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.${format == 'opus' ? 'ogg' : 'mp3'}');
      await tempFile.writeAsBytes(_audioBuffer);

      await _player.setFilePath(tempFile.path);
      await _player.play();

      // Clean up temp file after playback
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          tempFile.delete().catchError((_) {});
        }
      });
    } catch (e) {
      // Handle playback errors
      rethrow;
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _player.stop();
    _audioBuffer.clear();
  }

  void dispose() {
    close();
    _player.dispose();
  }

  /// 🚀 ENHANCED: Stream timeout handling
  void _startTimeout() {
    _streamTimeoutTimer?.cancel();
    _streamTimeoutTimer = Timer(STREAM_TIMEOUT, () {
      if (!_isStreamComplete) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: ⚠️ Stream timeout - marking as complete');
        }
        _isStreamComplete = true;
      }
    });
  }

  /// 🚀 ENHANCED: Concatenate chunks for batch playback
  Uint8List _concatenateChunks(List<AudioChunk> chunks) {
    final totalLength =
        chunks.fold<int>(0, (sum, chunk) => sum + chunk.data.length);
    final result = Uint8List(totalLength);
    int offset = 0;

    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.data.length, chunk.data);
      offset += chunk.data.length;
    }

    return result;
  }

  /// 🚀 ENHANCED: Create WAV file from raw audio data
  Uint8List _createWavFromData(Uint8List audioData) {
    return _createWavFile(audioData);
  }

  /// 🚀 ENHANCED: Play audio data directly with comprehensive error logging
  Future<void> _playAudioData(Uint8List wavData) async {
    if (kDebugMode) {
      debugPrint(
          '🎵 AUDIO_PLAYER: Starting playback of ${wavData.length} bytes');
    }

    File? tempFile;
    try {
      // Create temp file with detailed logging
      tempFile = await _createTempAudioFile(wavData);
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: Created temp file: ${tempFile.path}');
        debugPrint('🎵 AUDIO_PLAYER: File exists: ${await tempFile.exists()}');
        debugPrint(
            '🎵 AUDIO_PLAYER: File size: ${await tempFile.length()} bytes');
      }

      // Set file path with error checking
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: Setting file path...');
      }
      await _audioPlayer.setFilePath(tempFile.path);

      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: File path set successfully');
        debugPrint(
            '🎵 AUDIO_PLAYER: Player state: ${_audioPlayer.playerState}');
      }

      // Start playback with state monitoring
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: Starting playback...');
      }

      // Set up state monitoring before starting playback
      late StreamSubscription<PlayerState> stateSubscription;
      final completer = Completer<void>();
      bool hasCompleted = false;

      stateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (kDebugMode) {
          debugPrint(
              '🎵 AUDIO_PLAYER: State changed to ${state.processingState}');
        }

        if (state.processingState == ProcessingState.completed &&
            !hasCompleted) {
          hasCompleted = true;
          stateSubscription.cancel();
          completer.complete();
        } else if (state.processingState == ProcessingState.idle &&
            !hasCompleted) {
          if (kDebugMode) {
            debugPrint('🎵 AUDIO_PLAYER: ❌ Playback went to idle unexpectedly');
          }
          hasCompleted = true;
          stateSubscription.cancel();
          completer.completeError('Playback went to idle state unexpectedly');
        }
      });

      // Start playback
      await _audioPlayer.play();
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: Play() called successfully');
      }

      // Wait for completion with timeout
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stateSubscription.cancel();
          throw TimeoutException('Audio playback timed out after 30 seconds');
        },
      );

      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: ✅ Playback completed successfully');
      }

      _cleanupTempFile(tempFile);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_PLAYER: ❌ ERROR during playback: $e');
        debugPrint('🎵 AUDIO_PLAYER: ❌ Stack trace: $stackTrace');
        if (tempFile != null) {
          debugPrint('🎵 AUDIO_PLAYER: ❌ Temp file path: ${tempFile.path}');
          debugPrint(
              '🎵 AUDIO_PLAYER: ❌ Temp file exists: ${await tempFile.exists()}');
        }
      }
      if (tempFile != null) {
        _cleanupTempFile(tempFile);
      }
      rethrow;
    }
  }

  /// 🔧 SIMPLIFIED: Always return false - rely on backend's tts_complete signal
  bool _shouldCompleteStream() {
    // This method is no longer needed since we rely on backend's tts_complete signal
    // Keep it simple for backwards compatibility
    return false; // Never auto-complete based on chunks
  }

  /// 🔍 Initialize audio player with comprehensive diagnostics
  Future<void> _initializeAudioPlayerWithDiagnostics() async {
    if (kDebugMode) {
      debugPrint('🎵 AUDIO_INIT: ================================');
      debugPrint('🎵 AUDIO_INIT: Starting audio player diagnostics');
      debugPrint('🎵 AUDIO_INIT: Platform: ${Platform.operatingSystem}');
      debugPrint(
          '🎵 AUDIO_INIT: Platform version: ${Platform.operatingSystemVersion}');
    }

    try {
      // Check current audio player state
      final currentState = _audioPlayer.playerState;
      if (kDebugMode) {
        debugPrint(
            '🎵 AUDIO_INIT: Player state: ${currentState.processingState}');
        debugPrint('🎵 AUDIO_INIT: Currently playing: ${currentState.playing}');
        debugPrint('🎵 AUDIO_INIT: Current volume: ${_audioPlayer.volume}');
      }

      // Test basic operations
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_INIT: Testing volume control...');
      }
      await _audioPlayer.setVolume(1.0);

      if (kDebugMode) {
        debugPrint('🎵 AUDIO_INIT: ✅ Volume control works');
        debugPrint('🎵 AUDIO_INIT: Testing stop operation...');
      }
      await _audioPlayer.stop();

      if (kDebugMode) {
        debugPrint('🎵 AUDIO_INIT: ✅ Stop operation works');
        debugPrint(
            '🎵 AUDIO_INIT: Final state: ${_audioPlayer.playerState.processingState}');
        debugPrint('🎵 AUDIO_INIT: ================================');
      }

      // Test temp directory access
      await _testTempDirectoryAccess();

      // Test Android-specific audio capabilities
      if (Platform.isAndroid) {
        await _testAndroidAudioCapabilities();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎵 AUDIO_INIT: ❌ INITIALIZATION FAILED: $e');
        debugPrint('🎵 AUDIO_INIT: ❌ Stack trace: $stackTrace');
        debugPrint('🎵 AUDIO_INIT: ================================');
      }
      // Don't throw - let the app continue but log the issue
    }
  }

  /// 🔍 Test temporary directory access for audio files
  Future<void> _testTempDirectoryAccess() async {
    try {
      if (kDebugMode) {
        debugPrint('🎵 TEMP_TEST: Testing temporary directory access...');
      }

      final tempDir = await getTemporaryDirectory();
      if (kDebugMode) {
        debugPrint('🎵 TEMP_TEST: Temp directory: ${tempDir.path}');
        debugPrint('🎵 TEMP_TEST: Directory exists: ${await tempDir.exists()}');
      }

      // Test creating a small test file
      final testFile = File(
          '${tempDir.path}/audio_test_${DateTime.now().millisecondsSinceEpoch}.txt');
      await testFile.writeAsString('test');

      if (kDebugMode) {
        debugPrint('🎵 TEMP_TEST: Test file created: ${testFile.path}');
        debugPrint('🎵 TEMP_TEST: File exists: ${await testFile.exists()}');
        debugPrint('🎵 TEMP_TEST: File size: ${await testFile.length()} bytes');
      }

      // Clean up test file
      await testFile.delete();

      if (kDebugMode) {
        debugPrint('🎵 TEMP_TEST: ✅ Temporary directory access works');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎵 TEMP_TEST: ❌ Temporary directory test failed: $e');
        debugPrint('🎵 TEMP_TEST: ❌ Stack trace: $stackTrace');
      }
    }
  }

  /// 🔍 Test Android-specific audio capabilities and configurations
  Future<void> _testAndroidAudioCapabilities() async {
    try {
      if (kDebugMode) {
        debugPrint('🎵 ANDROID_TEST: Testing Android audio capabilities...');
      }

      // Test if we can create a small WAV file and validate its structure
      final testAudioData = Uint8List.fromList(
          [0, 255, 128, 64, 192, 32, 224, 16]); // Small test audio
      final testWav = _createWavFile(testAudioData);

      if (kDebugMode) {
        debugPrint(
            '🎵 ANDROID_TEST: Created test WAV file: ${testWav.length} bytes');

        // Validate WAV header
        final riffCheck = String.fromCharCodes(testWav.sublist(0, 4));
        final waveCheck = String.fromCharCodes(testWav.sublist(8, 12));
        debugPrint('🎵 ANDROID_TEST: RIFF header: "$riffCheck"');
        debugPrint('🎵 ANDROID_TEST: WAVE header: "$waveCheck"');

        // Check if the audio player can handle the basic file format
        final tempDir = await getTemporaryDirectory();
        final testFile = File(
            '${tempDir.path}/android_audio_test_${DateTime.now().millisecondsSinceEpoch}.wav');
        await testFile.writeAsBytes(testWav);

        debugPrint('🎵 ANDROID_TEST: Test WAV file written: ${testFile.path}');
        debugPrint('🎵 ANDROID_TEST: File exists: ${await testFile.exists()}');
        debugPrint(
            '🎵 ANDROID_TEST: File size: ${await testFile.length()} bytes');

        // Clean up test file
        await testFile.delete();

        debugPrint(
            '🎵 ANDROID_TEST: ✅ Android audio test completed successfully');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎵 ANDROID_TEST: ❌ Android audio test failed: $e');
        debugPrint('🎵 ANDROID_TEST: ❌ Stack trace: $stackTrace');
      }
    }
  }
}

/// Usage:
/// final ttsService = TTSStreamingService();
/// ttsService.connectAndRequestTTS(
///   text: 'Hello world',
///   onDone: () => print('Playback done'),
///   onError: (err) => print('Error: $err'),
/// );
