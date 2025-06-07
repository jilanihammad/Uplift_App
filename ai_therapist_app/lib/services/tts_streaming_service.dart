import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  AudioChunk({
    required this.data,
    required this.timestamp,
    required this.sequenceNumber,
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
class TTSStreamingService {
  // 🔧 FIXED: Correct backend endpoint
  static const String wsUrl =
      'wss://ai-therapist-backend-385290373302.us-central1.run.app/ws/tts/speech';

  // Protocol configuration
  static const int protocolVersion = 2;

  // Connection management
  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  ConnectionState _connectionState = ConnectionState.disconnected;

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

  StreamSubscription<PlayerState>? _playerStateSubscription;

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
    // Reset state for new session
    _resetStreamState();

    // Close any existing active TTS session first
    await TTSSessionManager.closeActiveSession();

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
  Future<void> connectAndRequestTTS({
    required String text,
    String voice = 'nova',
    String responseFormat = 'wav',
    VoidCallback? onDone,
    Function(String)? onError,
    Function(double)? onProgress,
  }) async {
    _onComplete = onDone;
    _onError = onError;
    _onProgress = onProgress;

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
    _connectionState = ConnectionState.connecting;

    // Get JWT token from Firebase
    final String? jwt = await _getJwtToken();
    if (jwt == null) {
      throw Exception('Failed to obtain JWT token');
    }

    // Generate a conversation ID
    final conversationId =
        'conv_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';

    if (kDebugMode) {
      debugPrint('TTSStreaming: Connecting to $wsUrl with JWT authentication');
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
          },
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
          debugPrint('TTSStreaming: WebSocket error: $error');
          _connectionState = ConnectionState.error;
          _onError?.call('WebSocket connection error: $error');
        },
        onDone: () {
          debugPrint('TTSStreaming: WebSocket connection closed');
          _connectionState = ConnectionState.disconnected;
        },
      );

      _connectionState = ConnectionState.connected;
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
      'text': text,
      'voice': voice,
      'params': {
        'response_format': responseFormat,
        'speed': 1.0,
        'pitch': 1.0,
      },
      'client_seq': _clientSequence++,
      'request_id': _generateRequestId(),
    };

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

    switch (frameType) {
      case 'init_ack':
      case 'init_response':
        _handleInitResponse(data);
        break;
      case 'audio_request_received':
        _handleAudioRequestReceived(data);
        break;
      case 'audio_chunk':
        _handleJsonAudioChunk(data);
        break;
      case 'audio':
        _handleAudioFrame(data);
        break;
      case 'tts_complete':
        _handleTtsComplete(data);
        break;
      case 'done':
      case 'complete':
        _handleStreamComplete(data);
        break;
      case 'error':
        _handleServerError(data);
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
        _handleAudioChunk(chunk, timestamp, sequence);

        if (isEnd) {
          _handleStreamComplete({});
        }
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
    ));

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 📥 Added chunk $sequenceNumber (${chunkData.length} bytes)');
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

    // 🎯 IMPROVED: Start progressive playback logic
    const int minBufferSize =
        2; // Start playing after 2 chunks for responsiveness

    // Only start new playback if:
    // 1. We're not currently playing
    // 2. We have enough chunks buffered
    // 3. There are unplayed chunks available
    final unplayedChunks = _audioBuffer.length - (_lastPlayedChunkIndex + 1);

    if (!_isPlaying &&
        _audioBuffer.length >= minBufferSize &&
        unplayedChunks > 0) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🚀 Starting progressive playback (${_audioBuffer.length} chunks buffered, $unplayedChunks unplayed)');
      }
      _startProgressivePlayback();
    } else if (_isPlaying && unplayedChunks > 0) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: ⏳ Playback in progress, $unplayedChunks chunks queued for next segment');
      }
    } else if (!_isPlaying && _audioBuffer.length < minBufferSize) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🔄 Buffering... (${_audioBuffer.length}/$minBufferSize chunks)');
      }
    }

    // 🔑 ENGINEER'S FIX: Check if we can close after adding chunk
    // (handles case where completion signal arrived while buffering)
    if (_completionSignalReceived) {
      _checkIfCanClose();
    }
  }

  /// 🎯 ENHANCED: Handle stream completion without abandoning chunks
  void _handleStreamComplete(Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🏁 Legacy stream completed signal with ${_audioBuffer.length} total chunks');
      debugPrint(
          'TTSStreaming: 📊 Final state - Last played: $_lastPlayedChunkIndex, Currently playing: $_isPlaying');
    }

    // Mark as complete (legacy path)
    _streamComplete = true;
    _bufferTimeout?.cancel();
    _bufferTimeout = null;

    // 🔑 ENGINEER'S FIX: Also trigger completion signal for legacy compatibility
    if (!_completionSignalReceived) {
      _completionSignalReceived = true;
    }

    // Use the centralized close logic
    _checkIfCanClose();
  }

  /// Handle server errors
  void _handleServerError(Map<String, dynamic> data) {
    final errorMessage = data['detail'] as String? ?? 'Unknown server error';
    _handleError('Server error: $errorMessage');
  }

  /// 🎯 FIXED: Progressive playback with correct index management
  Future<void> _startProgressivePlayback() async {
    if (_isPlaying || _audioBuffer.isEmpty) return;

    // Calculate available chunks BEFORE marking as playing
    final availableChunks = _audioBuffer.length - (_lastPlayedChunkIndex + 1);
    if (availableChunks <= 0) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: No new chunks to play (available: $availableChunks, buffer: ${_audioBuffer.length}, lastPlayed: $_lastPlayedChunkIndex)');
      }
      return;
    }

    _isPlaying = true;

    // 🎯 CRITICAL: Calculate the index range BEFORE processing
    final startIndex = _lastPlayedChunkIndex + 1;
    final endIndex = _audioBuffer.length;

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Starting progressive playback for chunks $startIndex to ${endIndex - 1} ($availableChunks chunks)');
    }

    try {
      final audioData = _concatenateAudioChunks(_audioBuffer);

      if (audioData.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              'TTSStreaming: No audio data extracted from chunks $startIndex to ${endIndex - 1}');
        }
        _isPlaying = false;
        return;
      }

      // Create and play audio
      final completeWavFile = _createWavFile(audioData);
      final tempFile = await _createTempAudioFile(completeWavFile);

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: Created WAV file with ${completeWavFile.length} bytes for progressive playback');
      }

      await _audioPlayer.setFilePath(tempFile.path);
      await _audioPlayer.play();

      // 🎯 CRITICAL: Only update index AFTER successful playback start
      // This ensures we don't lose chunks if playback fails
      final previousIndex = _lastPlayedChunkIndex;
      _lastPlayedChunkIndex =
          endIndex - 1; // Set to last chunk that will be played

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: Progressive playback started successfully, updated index from $previousIndex to $_lastPlayedChunkIndex');
      }

      // Set up completion listener
      await _playerStateSubscription?.cancel();
      _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (kDebugMode) {
            debugPrint('TTSStreaming: Progressive playback segment completed');
          }
          _cleanupTempFile(tempFile);
          _handleProgressiveCompletion();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: Progressive playback error: $e');
      }
      _isPlaying = false;
      _handleError('Progressive playback error: $e');
    }
  }

  /// 🎯 FIXED: Completion handling that preserves remaining chunks
  Future<void> _handleProgressiveCompletion() async {
    _isPlaying = false;

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Progressive completion - buffer size: ${_audioBuffer.length}, last played: $_lastPlayedChunkIndex, stream complete: $_streamComplete');
    }

    // Check if there are more chunks to play (chunks that arrived while we were playing)
    final remainingChunks = _audioBuffer.length - (_lastPlayedChunkIndex + 1);

    if (remainingChunks > 0) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: $remainingChunks more chunks available, continuing progressive playback');
      }
      // More chunks available - continue progressive playback immediately
      await _startProgressivePlayback();
    } else {
      // No more chunks - check if we can close now
      if (kDebugMode) {
        debugPrint('TTSStreaming: 🏁 Progressive playback segment completed');
      }
      _checkIfCanClose(); // 🔑 ENGINEER'S FIX: Use centralized close logic
    }
  }

  /// Start buffered audio playback with proper WAV file construction
  Future<void> _startBufferedPlayback() async {
    if (_isPlaying || _audioBuffer.isEmpty) return;

    _isPlaying = true;

    try {
      // Extract pure audio data from chunks
      final List<int> pureAudioData = [];
      for (final chunk in _audioBuffer) {
        final chunkData = chunk.data;
        if (_isWavFile(chunkData) && chunkData.length > 44) {
          pureAudioData.addAll(chunkData.sublist(44));
        } else {
          pureAudioData.addAll(chunkData);
        }
      }

      if (pureAudioData.isEmpty) {
        _scheduleCompletion();
        return;
      }

      // Create complete WAV file and play
      final completeWavFile = _createWavFile(Uint8List.fromList(pureAudioData));
      final tempFile = await _createTempAudioFile(completeWavFile);

      await _audioPlayer.setFilePath(tempFile.path);
      await _audioPlayer.play();

      // Set up completion listener
      await _playerStateSubscription?.cancel();
      _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _cleanupTempFile(tempFile);
          _scheduleCompletion();
        }
      });
    } catch (e) {
      _handleError('Buffered playback error: $e');
    }
  }

  /// 🎯 ENHANCED: Better chunk concatenation with comprehensive debugging
  Uint8List _concatenateAudioChunks(List<AudioChunk> chunks) {
    final startIndex = _lastPlayedChunkIndex + 1;
    final endIndex = chunks.length;

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: Concatenating chunks from index $startIndex to ${endIndex - 1}');
      debugPrint('TTSStreaming: Total chunks in buffer: ${chunks.length}');
      debugPrint(
          'TTSStreaming: Last played chunk index: $_lastPlayedChunkIndex');
      debugPrint('TTSStreaming: Chunks to process: ${endIndex - startIndex}');
    }

    if (startIndex >= endIndex) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: ⚠️  WARNING - No chunks to concatenate! startIndex ($startIndex) >= endIndex ($endIndex)');
        debugPrint('TTSStreaming: This indicates the index management bug!');
      }
      return Uint8List(0);
    }

    final List<int> pureAudioData = [];
    int totalProcessedBytes = 0;

    for (int i = startIndex; i < endIndex; i++) {
      final chunkData = chunks[i].data;

      if (kDebugMode && i == startIndex) {
        // Log format detection for first chunk being processed
        final formatInfo =
            _isWavFile(chunkData) ? 'WAV format' : 'Raw audio format';
        debugPrint(
            'TTSStreaming: Processing chunk $i (${chunkData.length} bytes, $formatInfo)');
      }

      if (_isWavFile(chunkData)) {
        // Skip WAV header if present (first 44 bytes)
        if (chunkData.length > 44) {
          final audioOnly = chunkData.sublist(44);
          pureAudioData.addAll(audioOnly);
          totalProcessedBytes += audioOnly.length;

          if (kDebugMode && i == startIndex) {
            debugPrint(
                'TTSStreaming: Extracted ${audioOnly.length} bytes from WAV chunk (skipped 44-byte header)');
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                'TTSStreaming: WAV chunk $i too small (${chunkData.length} bytes), using all data');
          }
          pureAudioData.addAll(chunkData);
          totalProcessedBytes += chunkData.length;
        }
      } else {
        // Raw audio data - use directly
        pureAudioData.addAll(chunkData);
        totalProcessedBytes += chunkData.length;

        if (kDebugMode && i == startIndex) {
          debugPrint(
              'TTSStreaming: Using raw audio data directly (${chunkData.length} bytes)');
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: ✅ Concatenated ${endIndex - startIndex} chunks into $totalProcessedBytes bytes of audio data');
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

  /// Create temporary audio file for playback
  Future<File> _createTempAudioFile(Uint8List audioData) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await tempFile.writeAsBytes(audioData);
    return tempFile;
  }

  /// Create a proper WAV file with header and audio data
  Uint8List _createWavFile(Uint8List audioData) {
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

  /// Reset state for new streaming session
  void _resetStreamState() {
    _streamComplete = false;
    _lastPlayedChunkIndex = -1;
    _audioBuffer.clear();
    _isPlaying = false;
    _requestStartTime = null;

    // 🔑 ENGINEER'S FIX: Reset completion tracking flags
    _completionSignalReceived = false;
    _shouldStayConnected = true;

    // 🔑 SAFETY TIMEOUT: Cancel any existing safety timeout
    _safetyTimeout?.cancel();
    _safetyTimeout = null;
  }

  /// Close connection and clean up resources
  Future<void> close() async {
    _playbackTimer?.cancel();
    _playbackTimer = null;

    _bufferTimeout?.cancel();
    _bufferTimeout = null;

    // 🔑 SAFETY TIMEOUT: Cancel safety timeout on close
    _safetyTimeout?.cancel();
    _safetyTimeout = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    await _playerStateSubscription?.cancel();
    _playerStateSubscription = null;

    await _channel?.sink.close();
    _channel = null;

    await _audioPlayer.stop();
    _audioBuffer.clear();
    _isPlaying = false;
    _connectionState = ConnectionState.disconnected;
  }

  /// Dispose of the service and release all resources
  Future<void> dispose() async {
    await close();
    _audioPlayer.dispose();
  }

  /// Get current connection state
  ConnectionState get connectionState => _connectionState;

  /// Check if currently connected
  bool get isConnected => _connectionState == ConnectionState.connected;

  /// Interrupt current playback
  Future<void> interrupt() async {
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

  /// 🎯 NEW: Handle TTS completion signal from backend (proper completion waiting)
  void _handleTtsComplete(Map<String, dynamic> data) {
    if (kDebugMode) {
      final requestId = data['request_id'] as String?;
      final status = data['status'] as String?;
      final totalChunks = data['total_chunks'] as int?;

      debugPrint(
          'TTSStreaming: 🏁 TTS completion signal received - staying connected until playback done');
      debugPrint(
          'TTSStreaming: 📊 Request: $requestId, Status: $status, Total chunks: $totalChunks');
      debugPrint(
          'TTSStreaming: 📊 Final state - buffer size: ${_audioBuffer.length}, last played: $_lastPlayedChunkIndex, currently playing: $_isPlaying');
    }

    // 🔑 ENGINEER'S FIX: Mark completion received but DON'T close yet
    _completionSignalReceived = true;
    _streamComplete = true;
    _bufferTimeout?.cancel();
    _bufferTimeout = null;

    // Check if we can close now (after both completion signal AND playback done)
    _checkIfCanClose();
  }

  /// 🔑 ENGINEER'S FIX: Centralized logic to check if connection can be safely closed
  void _checkIfCanClose() {
    // Only close if:
    // 1. Got completion signal from server
    // 2. Not currently playing audio
    // 3. No more chunks in buffer to play

    final hasUnplayedChunks = _audioBuffer.length > (_lastPlayedChunkIndex + 1);

    if (_completionSignalReceived && !_isPlaying && !hasUnplayedChunks) {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: 🔒 All conditions met - safe to close connection');
      }
      _finalizeAndClose();
    } else {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: ⏳ Waiting to close - completion: $_completionSignalReceived, playing: $_isPlaying, unplayed chunks: $hasUnplayedChunks');
      }
    }
  }

  /// 🔑 NEW: Safe WebSocket connection closure after TTS completion
  void _finalizeAndClose() {
    if (kDebugMode) {
      debugPrint(
          'TTSStreaming: 🏁 Finalizing TTS session and closing connection');
    }

    _onComplete?.call();

    // Now it's safe to close
    Timer(const Duration(milliseconds: 100), () async {
      try {
        await _channel?.sink.close();
        _channel = null;
        _connectionState = ConnectionState.disconnected;

        if (kDebugMode) {
          debugPrint('TTSStreaming: WebSocket connection closed successfully');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: Error closing WebSocket: $e');
        }
      }
    });
  }
}

/// Usage example:
/// final ttsService = TTSStreamingService();
/// await ttsService.streamAndPlay(
///   text: 'Hello world',
///   conversationId: 'unique_id',
///   onComplete: () => print('Playback done'),
///   onError: (err) => print('Error: $err'),
///   onProgress: (progress) => print('Progress: ${progress * 100}%'),
/// );
