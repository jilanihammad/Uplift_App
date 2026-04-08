// lib/services/websocket_audio_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../data/datasources/remote/api_client.dart';
import '../config/app_config.dart';
class WebSocketAudioManager implements IWebSocketAudioManager {
  // Note: ApiClient reserved for future use (authentication, etc.)
  final ApiClient _apiClient;
  WebSocketChannel? _channel;
  DateTime? _lastUsed;
  Timer? _keepAliveTimer;
  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _keepAliveInterval = Duration(seconds: 25);
  Timer? _idleCloseTimer;
  static const Duration _idleCloseDelay = Duration(seconds: 30);
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  Timer? _reconnectTimer;
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  String? _currentSessionId;
  final Map<String, StreamController<dynamic>> _activeSessions = {};
  StreamSubscription? _wsSubscription;
  bool _isConnected = false;
  bool _disposed = false;
  Map<String, dynamic> _compressionSettings = {};
  String _streamingQuality = 'high';
  WebSocketAudioManager({required ApiClient apiClient})
      : _apiClient = apiClient;
  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
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
    if (_channel != null &&
        _channel!.closeCode == null &&
        _lastUsed != null &&
        now.difference(_lastUsed!) < _connectionTimeout) {
      _lastUsed = now;
      return;
    }
    await _cleanupConnection();
    try {
      final backendUrl = AppConfig().backendUrl;
      final wsUrl = '${backendUrl.replaceAll('http', 'ws')}/ws/audio';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _lastUsed = now;
      _resetReconnectAttempts();
      _cancelReconnectTimer();
      _setupMessageHandling();
      _startKeepAliveTimer();
      _isConnected = true;
      _connectionStateController.add(true);
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      _errorController.add('Connection failed: $e');
      rethrow;
    }
  }
  @override
  Future<void> disconnectFromBackend() async {
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
    } catch (e) {
      _errorController.add('Audio streaming failed: $e');
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
    } catch (e) {
      _errorController.add('Audio chunk sending failed: $e');
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
    } catch (e) {
      _errorController.add('Audio stream finalization failed: $e');
      rethrow;
    }
  }
  @override
  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected) {
      throw StateError('Not connected to backend');
    }
    try {
      if (_currentSessionId != null && !message.containsKey('session_id')) {
        message['session_id'] = _currentSessionId;
      }
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
    } catch (e) {
      _errorController.add('Message sending failed: $e');
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
    final sessionController = StreamController<dynamic>.broadcast();
    _activeSessions[sessionId] = sessionController;
    if (!_isConnected) {
      await connectToBackend();
    }
    try {
      final message = {
        'type': 'session_start',
        'session_id': sessionId,
        'quality': _streamingQuality,
        'compression': _compressionSettings,
      };
      await sendMessage(message);
    } catch (e) {
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
      final message = {
        'type': 'session_end',
        'session_id': sessionId,
      };
      if (_isConnected) {
        await sendMessage(message);
      }
    } catch (e) {
    } finally {
      final controller = _activeSessions.remove(sessionId);
      controller?.close();
      _currentSessionId = null;
      if (_isConnected) {
        _scheduleIdleClose();
      }
    }
  }
  @override
  void setStreamingQuality(String quality) {
    _streamingQuality = quality;
  }
  @override
  void setCompressionSettings(Map<String, dynamic> settings) {
    _compressionSettings = settings;
  }
  @override
  Future<void> sendKeepAlive() async {
    if (!_isConnected) {
      return;
    }
    try {
      final message = {'type': 'ping'};
      _channel!.sink.add(jsonEncode(message));
      _lastUsed = DateTime.now();
    } catch (e) {
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
  }
  @override
  void stopKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }
  @override
  Future<void> handleConnectionError(String error) async {
    _isConnected = false;
    _connectionStateController.add(false);
    _errorController.add(error);
    await _cleanupConnection();
    final now = DateTime.now();
    final shouldAttemptReconnect = _currentSessionId != null ||
        (_lastUsed != null && now.difference(_lastUsed!) < _connectionTimeout);
    if (shouldAttemptReconnect && !_disposed) {
      _scheduleReconnectWithBackoff();
    }
  }
  @override
  Future<void> reconnect() async {
    if (_disposed) {
      throw StateError('WebSocketAudioManager has been disposed');
    }
    await _cleanupConnection();
    try {
      await connectToBackend();
      if (_currentSessionId != null) {
        final sessionId = _currentSessionId!;
        _currentSessionId = null; // Reset to allow startSession to work
        await startSession(sessionId);
      }
    } catch (e) {
      _errorController.add('Reconnection failed: $e');
      _scheduleReconnectWithBackoff();
    }
  }
  void _setupMessageHandling() {
    _wsSubscription?.cancel();
    _wsSubscription = _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'pong') {
            return;
          }
          final sessionId = data['session_id'] as String?;
          if (sessionId != null && _activeSessions.containsKey(sessionId)) {
            _activeSessions[sessionId]!.add(data);
          }
          _messageController.add(data);
        } catch (e) {
          _errorController.add('Message parsing error: $e');
        }
      },
      onError: (error) {
        handleConnectionError('WebSocket error: $error');
      },
      onDone: () {
        _isConnected = false;
        _connectionStateController.add(false);
        _cleanupConnection();
      },
    );
  }
  void _startKeepAliveTimer() {
    startKeepAliveTimer();
  }
  Future<void> _cleanupConnection() async {
    stopKeepAliveTimer();
    _cancelIdleClose();
    _cancelReconnectTimer();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    for (final controller in _activeSessions.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _activeSessions.clear();
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {}
      _channel = null;
    }
    _lastUsed = null;
  }
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_currentSessionId != null) {
      endSession().catchError((e) {
      });
    }
    _cleanupConnection().catchError((e) {
    });
    if (!_connectionStateController.isClosed) {
      _connectionStateController.close();
    }
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_errorController.isClosed) {
      _errorController.close();
    }
  }
  // ===== Idle close helpers =====
  void _scheduleIdleClose() {
    _cancelIdleClose();
    _idleCloseTimer = Timer(_idleCloseDelay, () async {
      if (_isConnected && _currentSessionId == null) {
        await disconnectFromBackend();
      }
    });
  }
  void _cancelIdleClose() {
    _idleCloseTimer?.cancel();
    _idleCloseTimer = null;
  }
  // ===== Reconnection backoff helpers =====
  void _scheduleReconnectWithBackoff() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }
    _reconnectAttempts++;
    final delay = _computeBackoffDelay(_reconnectAttempts);
    _cancelReconnectTimer();
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await reconnect();
        _resetReconnectAttempts();
      } catch (_) {}
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
