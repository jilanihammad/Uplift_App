// lib/services/websocket_audio_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../data/datasources/remote/api_client.dart';
import '../config/app_config.dart';

/// WebSocket audio manager implementation for real-time audio streaming
/// Extracted from VoiceService to provide focused audio communication capabilities
class WebSocketAudioManager implements IWebSocketAudioManager {
  // Note: ApiClient reserved for future use (authentication, etc.)
  final ApiClient _apiClient;
  
  // WebSocket connection management
  WebSocketChannel? _channel;
  DateTime? _lastUsed;
  Timer? _keepAliveTimer;
  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _keepAliveInterval = Duration(seconds: 25);
  // Graceful idle close: keep socket open briefly for fast reuse after session end
  Timer? _idleCloseTimer;
  static const Duration _idleCloseDelay = Duration(seconds: 30);
  // Exponential backoff for reconnection attempts
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  Timer? _reconnectTimer;
  
  // Stream controllers for connection state and messages
  final StreamController<bool> _connectionStateController = 
      StreamController<bool>.broadcast();
  final StreamController<dynamic> _messageController = 
      StreamController<dynamic>.broadcast();
  final StreamController<String> _errorController = 
      StreamController<String>.broadcast();
  
  // Session management
  String? _currentSessionId;
  final Map<String, StreamController<dynamic>> _activeSessions = {};
  StreamSubscription? _wsSubscription;
  
  // Connection state
  bool _isConnected = false;
  bool _disposed = false;
  
  // Audio streaming configuration
  Map<String, dynamic> _compressionSettings = {};
  String _streamingQuality = 'high';
  
  WebSocketAudioManager({required ApiClient apiClient}) : _apiClient = apiClient;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
    }
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Initializing...');
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Stream<dynamic> get messageStream => _messageController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  String? get currentSessionId => _currentSessionId;

  @override
  Future<void> connectToBackend() async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
    }

    final now = DateTime.now();
    
    // Check if we have a valid existing connection
    if (_channel != null && 
        _channel!.closeCode == null &&
        _lastUsed != null &&
        now.difference(_lastUsed!) < _connectionTimeout) {
      _lastUsed = now;
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Reusing existing connection');
      }
      return;
    }
    
    // Clean up old connection
    await _cleanupConnection();
    
    try {
      // Create WebSocket URL - using the same pattern as VoiceService
      final backendUrl = AppConfig().backendUrl;
      final wsUrl = '${backendUrl.replaceAll('http', 'ws')}/ws/audio';
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Connecting to: $wsUrl');
      }
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _lastUsed = now;
      _resetReconnectAttempts();
      _cancelReconnectTimer();
      
      // Setup message handling
      _setupMessageHandling();
      
      // Start keep-alive mechanism
      _startKeepAliveTimer();
      
      // Update connection state
      _isConnected = true;
      _connectionStateController.add(true);
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Connected successfully');
      }
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      _errorController.add('Connection failed: $e');
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Connection failed: $e');
      }
      
      rethrow;
    }
  }

  @override
  Future<void> disconnectFromBackend() async {
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Disconnecting from backend');
    }
    
    await _cleanupConnection();
    
    _isConnected = false;
    _connectionStateController.add(false);
  }

  @override
  Future<void> streamAudio(Uint8List audioData) async {
    if (!_isConnected) {
      throw StateError('Not connected to backend');
    }
    
    if (_currentSessionId == null) {
      throw StateError('No active session');
    }
    
    try {
      final message = {
        'type': 'audio_data',
        'session_id': _currentSessionId,
        'data': base64Encode(audioData),
        'quality': _streamingQuality,
        'compression': _compressionSettings,
      };
      
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
      
      if (kDebugMode && audioData.isNotEmpty) {
        debugPrint('[WebSocketAudioManager] Streamed ${audioData.length} bytes');
      }
    } catch (e) {
      _errorController.add('Audio streaming failed: $e');
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Audio streaming error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> sendAudioChunk(Uint8List chunk, int chunkIndex) async {
    if (!_isConnected) {
      throw StateError('Not connected to backend');
    }
    
    if (_currentSessionId == null) {
      throw StateError('No active session');
    }
    
    try {
      final message = {
        'type': 'audio_chunk',
        'session_id': _currentSessionId,
        'chunk_index': chunkIndex,
        'data': base64Encode(chunk),
        'quality': _streamingQuality,
        'compression': _compressionSettings,
      };
      
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Sent chunk $chunkIndex (${chunk.length} bytes)');
      }
    } catch (e) {
      _errorController.add('Audio chunk sending failed: $e');
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Chunk sending error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> finalizeAudioStream() async {
    if (!_isConnected) {
      throw StateError('Not connected to backend');
    }
    
    if (_currentSessionId == null) {
      throw StateError('No active session');
    }
    
    try {
      final message = {
        'type': 'audio_stream_end',
        'session_id': _currentSessionId,
      };
      
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Finalized audio stream');
      }
    } catch (e) {
      _errorController.add('Audio stream finalization failed: $e');
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Stream finalization error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected) {
      throw StateError('Not connected to backend');
    }
    
    try {
      // Add session ID if available and not already present
      if (_currentSessionId != null && !message.containsKey('session_id')) {
        message['session_id'] = _currentSessionId;
      }
      
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Sent message: ${message['type']}');
      }
    } catch (e) {
      _errorController.add('Message sending failed: $e');
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Message sending error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> startSession(String sessionId) async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
    }
    
    _cancelIdleClose();
    _currentSessionId = sessionId;
    
    // Create session-specific controller
    final sessionController = StreamController<dynamic>.broadcast();
    _activeSessions[sessionId] = sessionController;
    
    // Ensure connection is established
    if (!_isConnected) {
      await connectToBackend();
    }
    
    // Send session start message
    try {
      final message = {
        'type': 'session_start',
        'session_id': sessionId,
        'quality': _streamingQuality,
        'compression': _compressionSettings,
      };
      
      await sendMessage(message);
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Started session: $sessionId');
      }
    } catch (e) {
      // Clean up session on error
      _activeSessions.remove(sessionId);
      sessionController.close();
      _currentSessionId = null;
      rethrow;
    }
  }

  @override
  Future<void> endSession() async {
    if (_currentSessionId == null) {
      return;
    }
    
    final sessionId = _currentSessionId!;
    
    try {
      // Send session end message
      final message = {
        'type': 'session_end',
        'session_id': sessionId,
      };
      
      if (_isConnected) {
        await sendMessage(message);
      }
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Ended session: $sessionId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Error ending session: $e');
      }
    } finally {
      // Clean up session
      final controller = _activeSessions.remove(sessionId);
      controller?.close();
      _currentSessionId = null;
      // Schedule graceful idle close to reduce dial-ups while allowing rapid reuse
      if (_isConnected) {
        _scheduleIdleClose();
      }
    }
  }

  @override
  void setStreamingQuality(String quality) {
    _streamingQuality = quality;
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Set streaming quality: $quality');
    }
  }

  @override
  void setCompressionSettings(Map<String, dynamic> settings) {
    _compressionSettings = settings;
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Set compression settings: $settings');
    }
  }

  @override
  Future<void> sendKeepAlive() async {
    if (!_isConnected) {
      return;
    }
    
    try {
      final message = {'type': 'ping'};
      _channel!.sink.add(jsonEncode(message));
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Sent keep-alive ping');
      }
      _lastUsed = DateTime.now();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Keep-alive failed: $e');
      }
      
      // Mark connection as invalid
      _isConnected = false;
      _connectionStateController.add(false);
      _errorController.add('Keep-alive failed: $e');
    }
  }

  @override
  void startKeepAliveTimer() {
    stopKeepAliveTimer();
    
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (timer) {
      if (_isConnected && _channel?.closeCode == null) {
        sendKeepAlive();
      } else {
        timer.cancel();
      }
    });
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Started keep-alive timer');
    }
  }

  @override
  void stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Stopped keep-alive timer');
    }
  }

  @override
  Future<void> handleConnectionError(String error) async {
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Handling connection error: $error');
    }
    
    _isConnected = false;
    _connectionStateController.add(false);
    _errorController.add(error);
    
    // Clean up current connection
    await _cleanupConnection();
    // Backoff reconnection only if session active or recently used
    final now = DateTime.now();
    final shouldAttemptReconnect =
        _currentSessionId != null || (_lastUsed != null && now.difference(_lastUsed!) < _connectionTimeout);
    if (shouldAttemptReconnect && !_disposed) {
      _scheduleReconnectWithBackoff();
    }
  }

  @override
  Future<void> reconnect() async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
    }
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Attempting to reconnect...');
    }
    
    await _cleanupConnection();
    
    try {
      await connectToBackend();
      
      // Restart current session if there was one
      if (_currentSessionId != null) {
        final sessionId = _currentSessionId!;
        _currentSessionId = null; // Reset to allow startSession to work
        await startSession(sessionId);
      }
      
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Reconnected successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Reconnection failed: $e');
      }
      
      _errorController.add('Reconnection failed: $e');
      _scheduleReconnectWithBackoff();
    }
  }

  /// Setup message handling for the WebSocket connection
  void _setupMessageHandling() {
    _wsSubscription?.cancel();
    
    _wsSubscription = _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          
          // Handle global messages
          if (data['type'] == 'pong') {
            if (kDebugMode) {
              debugPrint('[WebSocketAudioManager] Received pong response');
            }
            return;
          }
          
          // Route messages to specific sessions
          final sessionId = data['session_id'] as String?;
          if (sessionId != null && _activeSessions.containsKey(sessionId)) {
            _activeSessions[sessionId]!.add(data);
          }
          
          // Also send to global message stream
          _messageController.add(data);
          
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[WebSocketAudioManager] Error parsing message: $e');
          }
          _errorController.add('Message parsing error: $e');
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] WebSocket error: $error');
        }
        
        handleConnectionError('WebSocket error: $error');
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] WebSocket connection closed');
        }
        
        _isConnected = false;
        _connectionStateController.add(false);
        _cleanupConnection();
      },
    );
  }

  /// Start keep-alive timer mechanism
  void _startKeepAliveTimer() {
    startKeepAliveTimer();
  }

  /// Clean up WebSocket connection and related resources
  Future<void> _cleanupConnection() async {
    stopKeepAliveTimer();
    _cancelIdleClose();
    _cancelReconnectTimer();
    
    _wsSubscription?.cancel();
    _wsSubscription = null;
    
    // Close all active session controllers
    for (final controller in _activeSessions.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _activeSessions.clear();
    
    if (_channel != null) {
      try {
        await _channel!.sink.close();
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] WebSocket connection closed');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] Error closing WebSocket: $e');
        }
      }
      _channel = null;
    }
    
    _lastUsed = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Disposing...');
    }
    
    _disposed = true;
    
    // End current session
    if (_currentSessionId != null) {
      endSession().catchError((e) {
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] Error ending session during dispose: $e');
        }
      });
    }
    
    // Clean up connection
    _cleanupConnection().catchError((e) {
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Error cleaning up connection during dispose: $e');
      }
    });
    
    // Close stream controllers
    if (!_connectionStateController.isClosed) {
      _connectionStateController.close();
    }
    
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    
    if (!_errorController.isClosed) {
      _errorController.close();
    }
    
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Disposed successfully');
    }
  }

  // ===== Idle close helpers =====
  void _scheduleIdleClose() {
    _cancelIdleClose();
    _idleCloseTimer = Timer(_idleCloseDelay, () async {
      if (_isConnected && _currentSessionId == null) {
        if (kDebugMode) {
          debugPrint('[WebSocketAudioManager] Idle close timer fired – closing idle WebSocket');
        }
        await disconnectFromBackend();
      }
    });
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Scheduled idle close in ${_idleCloseDelay.inSeconds}s');
    }
  }

  void _cancelIdleClose() {
    _idleCloseTimer?.cancel();
    _idleCloseTimer = null;
  }

  // ===== Reconnection backoff helpers =====
  void _scheduleReconnectWithBackoff() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint('[WebSocketAudioManager] Max reconnection attempts reached; giving up');
      }
      return;
    }
    _reconnectAttempts++;
    final delay = _computeBackoffDelay(_reconnectAttempts);
    _cancelReconnectTimer();
    if (kDebugMode) {
      debugPrint('[WebSocketAudioManager] Scheduling reconnect attempt #$_reconnectAttempts in ${delay.inSeconds}s');
    }
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await reconnect();
        _resetReconnectAttempts();
      } catch (_) {
        // reconnect() schedules the next attempt on failure
      }
    });
  }

  Duration _computeBackoffDelay(int attempt) {
    final millis = _baseBackoff.inMilliseconds * (1 << (attempt - 1));
    final clamped = millis > _maxBackoff.inMilliseconds
        ? _maxBackoff.inMilliseconds
        : millis;
    return Duration(milliseconds: clamped);
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
}