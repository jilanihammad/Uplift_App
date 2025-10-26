// lib/services/websocket_audio_manager_example.dart
// Example usage of WebSocketAudioManager - for documentation purposes

import 'package:flutter/foundation.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';

/// Example demonstrating WebSocketAudioManager usage
class WebSocketAudioExample {
  late final IWebSocketAudioManager _wsManager;

  WebSocketAudioExample() {
    _wsManager = DependencyContainer().get<IWebSocketAudioManager>();
  }

  /// Example: Basic audio streaming session
  Future<void> basicAudioStreamingExample() async {
    try {
      // Initialize the manager
      await _wsManager.initialize();

      // Set streaming quality and compression
      _wsManager.setStreamingQuality('high');
      _wsManager.setCompressionSettings({
        'enabled': true,
        'level': 6,
      });

      // Connect to backend
      await _wsManager.connectToBackend();

      // Start a new session
      const sessionId = 'example_session_123';
      await _wsManager.startSession(sessionId);

      // Listen to connection state changes
      _wsManager.connectionStateStream.listen((isConnected) {
        debugPrint('Connection state changed: $isConnected');
      });

      // Listen to incoming messages
      _wsManager.messageStream.listen((message) {
        debugPrint('Received message: ${message['type']}');
      });

      // Listen to errors
      _wsManager.errorStream.listen((error) {
        debugPrint('Error: $error');
      });

      // Simulate audio streaming
      await _simulateAudioStreaming();

      // End the session
      await _wsManager.endSession();

      // Disconnect
      await _wsManager.disconnectFromBackend();
    } catch (e) {
      debugPrint('Example error: $e');
    } finally {
      _wsManager.dispose();
    }
  }

  /// Example: Chunked audio streaming
  Future<void> chunkedStreamingExample() async {
    try {
      await _wsManager.initialize();
      await _wsManager.connectToBackend();
      await _wsManager.startSession('chunked_session_456');

      // Send audio in chunks
      final audioData = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      const chunkSize = 256;

      for (int i = 0; i < audioData.length; i += chunkSize) {
        final end = (i + chunkSize < audioData.length)
            ? i + chunkSize
            : audioData.length;
        final chunk = audioData.sublist(i, end);

        await _wsManager.sendAudioChunk(chunk, i ~/ chunkSize);

        // Small delay between chunks
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Finalize the stream
      await _wsManager.finalizeAudioStream();

      await _wsManager.endSession();
      await _wsManager.disconnectFromBackend();
    } catch (e) {
      debugPrint('Chunked streaming error: $e');
    } finally {
      _wsManager.dispose();
    }
  }

  /// Example: Connection management with reconnection
  Future<void> connectionManagementExample() async {
    try {
      await _wsManager.initialize();

      // Set up connection state monitoring
      _wsManager.connectionStateStream.listen((isConnected) async {
        if (!isConnected) {
          debugPrint('Connection lost, attempting reconnection...');
          try {
            await _wsManager.reconnect();
            debugPrint('Reconnected successfully');
          } catch (e) {
            debugPrint('Reconnection failed: $e');
          }
        }
      });

      await _wsManager.connectToBackend();

      // Start keep-alive mechanism
      _wsManager.startKeepAliveTimer();

      // Simulate some work
      await Future.delayed(const Duration(seconds: 5));

      // Stop keep-alive
      _wsManager.stopKeepAliveTimer();

      await _wsManager.disconnectFromBackend();
    } catch (e) {
      debugPrint('Connection management error: $e');
    } finally {
      _wsManager.dispose();
    }
  }

  /// Simulate audio data streaming
  Future<void> _simulateAudioStreaming() async {
    // Generate some fake audio data
    final audioData = Uint8List.fromList(
        List.generate(4096, (i) => (i * 127 / 4096).round()));

    // Stream the audio
    await _wsManager.streamAudio(audioData);

    // Wait a bit to simulate processing time
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Example: Custom message handling
  Future<void> customMessageExample() async {
    try {
      await _wsManager.initialize();
      await _wsManager.connectToBackend();
      await _wsManager.startSession('message_session_789');

      // Send custom message
      await _wsManager.sendMessage({
        'type': 'custom_command',
        'command': 'start_processing',
        'parameters': {
          'format': 'pcm',
          'sample_rate': 44100,
        },
      });

      // Handle incoming messages
      _wsManager.messageStream.listen((message) {
        switch (message['type']) {
          case 'processing_started':
            debugPrint('Backend started processing');
            break;
          case 'processing_complete':
            debugPrint('Backend completed processing');
            break;
          case 'error':
            debugPrint('Backend error: ${message['detail']}');
            break;
        }
      });

      await Future.delayed(const Duration(seconds: 2));

      await _wsManager.endSession();
      await _wsManager.disconnectFromBackend();
    } catch (e) {
      debugPrint('Custom message error: $e');
    } finally {
      _wsManager.dispose();
    }
  }
}
