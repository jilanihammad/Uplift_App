// lib/di/interfaces/i_websocket_audio_manager.dart
import 'dart:async';
import 'dart:typed_data';
abstract class IWebSocketAudioManager {
  Future<void> connectToBackend();
  Future<void> disconnectFromBackend();
  bool get isConnected;
  Stream<bool> get connectionStateStream;
  Future<void> streamAudio(Uint8List audioData);
  Future<void> sendAudioChunk(Uint8List chunk, int chunkIndex);
  Future<void> finalizeAudioStream();
  Stream<dynamic> get messageStream;
  Future<void> sendMessage(Map<String, dynamic> message);
  Future<void> startSession(String sessionId);
  Future<void> endSession();
  String? get currentSessionId;
  void setStreamingQuality(String quality);
  void setCompressionSettings(Map<String, dynamic> settings);
  Future<void> sendKeepAlive();
  void startKeepAliveTimer();
  void stopKeepAliveTimer();
  Stream<String> get errorStream;
  Future<void> handleConnectionError(String error);
  Future<void> reconnect();
  Future<void> initialize();
  void dispose();
}
