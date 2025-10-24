// lib/di/interfaces/i_websocket_audio_manager.dart

import 'dart:async';
import 'dart:typed_data';

/// Interface for WebSocket audio streaming management
/// Handles real-time audio communication with backend services
abstract class IWebSocketAudioManager {
  // Connection management
  Future<void> connectToBackend();
  Future<void> disconnectFromBackend();
  bool get isConnected;
  Stream<bool> get connectionStateStream;

  // Audio streaming
  Future<void> streamAudio(Uint8List audioData);
  Future<void> sendAudioChunk(Uint8List chunk, int chunkIndex);
  Future<void> finalizeAudioStream();

  // Message handling
  Stream<dynamic> get messageStream;
  Future<void> sendMessage(Map<String, dynamic> message);

  // Session management
  Future<void> startSession(String sessionId);
  Future<void> endSession();
  String? get currentSessionId;

  // Configuration
  void setStreamingQuality(String quality);
  void setCompressionSettings(Map<String, dynamic> settings);

  // Connection health
  Future<void> sendKeepAlive();
  void startKeepAliveTimer();
  void stopKeepAliveTimer();

  // Error handling
  Stream<String> get errorStream;
  Future<void> handleConnectionError(String error);
  Future<void> reconnect();

  // Initialization and cleanup
  Future<void> initialize();
  void dispose();
}
