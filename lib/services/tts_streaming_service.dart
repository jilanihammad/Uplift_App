import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ... existing code ...

      if (frameType == 0x01) {
        // Audio frame
        final audioData = data.sublist(11, 11 + audioLength);
        if (kDebugMode) {
          debugPrint(
              'TTSStreaming: Processing binary audio frame with ${audioData.length} bytes');
        }
        _handleAudioChunk(audioData, timestamp, sequenceNumber);
      } else if (frameType == 0x02) {
        // ... existing code ...
      }

  /// Set up message listening
  _streamSubscription = _channel!.stream.listen(
    _handleMessage,
    onError: (error) {
      debugPrint('TTSStreaming: WebSocket error: $error');
      _connectionState = ConnectionState.error;
      _onError?.call('WebSocket connection error: $error');
    },
    onDone: () {
      debugPrint('TTSStreaming: WebSocket connection closed');
      debugPrint('TTSStreaming: Connection state was: $_connectionState');
      debugPrint('TTSStreaming: Audio buffer had ${_audioBuffer.length} chunks');
      _connectionState = ConnectionState.disconnected;
    },
  );

  // Jitter buffer management
  final List<AudioChunk> _audioBuffer = [];
  Timer? _playbackTimer;
  Timer? _bufferTimeout; // New: timeout for starting playback
  bool _isPlaying = false;
  int _lastPlayedChunkIndex = -1; // Track last played chunk for progressive playback
  bool _streamComplete = false; // 🔧 Engineer's Fix: Track stream completion state

  // Connection resilience constants
  static const int maxReconnectAttempts = 5;
  static const Duration baseReconnectDelay = Duration(seconds: 1);

  /// 🎯 NEW: Start progressive audio playback as chunks arrive
  /// This method plays audio immediately as it arrives rather than waiting for completion
  Future<void> _startProgressivePlayback() async {
    if (_isPlaying || _audioBuffer.isEmpty) return;

    _isPlaying = true;

    try {
      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: Starting progressive playback with ${_audioBuffer.length} initial chunks');
      }

      // Cancel any existing player state listener
      await _playerStateSubscription?.cancel();

      // 🔧 ENGINEER'S FIX: Calculate chunks to play BEFORE updating index
      final chunksToPlay = _audioBuffer.length - (_lastPlayedChunkIndex + 1);
      if (chunksToPlay <= 0) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: No new chunks to play');
        }
        _isPlaying = false;
        return;
      }

      // Process available chunks into audio data (only new chunks since last play)
      final audioData = _concatenateAudioChunks(_audioBuffer);

      if (audioData.isEmpty) {
        if (kDebugMode) {
          debugPrint('TTSStreaming: No new audio data for progressive chunks');
        }
        _isPlaying = false;
        return;
      }

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: Playing chunks ${_lastPlayedChunkIndex + 1} to ${_audioBuffer.length - 1} (${chunksToPlay} chunks)');
      }

      // Create WAV file and start playing
      final completeWavFile = _createWavFile(audioData);
      final tempFile = await _createTempAudioFile(completeWavFile);

      if (kDebugMode) {
        debugPrint(
            'TTSStreaming: Progressive playback started with ${completeWavFile.length} bytes');
      }

      await _audioPlayer.setFilePath(tempFile.path);
      await _audioPlayer.play();

      // 🔧 ENGINEER'S FIX: ONLY update index after successfully starting playback
      _lastPlayedChunkIndex = _audioBuffer.length - 1;

      // Set up completion listener that handles both progressive completion and final completion
      _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (kDebugMode) {
            debugPrint('TTSStreaming: Progressive playback segment completed');
          }

          // Clean up temp file
          _cleanupTempFile(tempFile);

          // Check if we have more chunks to play
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

  /// Handle completion of a progressive playback segment
  Future<void> _handleProgressiveCompletion() async {
    _isPlaying = false;

    // 🔧 ENGINEER'S FIX: Check for more chunks OR stream completion with remaining chunks
    if (_audioBuffer.length > _lastPlayedChunkIndex + 1) {
      if (kDebugMode) {
        debugPrint('TTSStreaming: ${_audioBuffer.length - _lastPlayedChunkIndex - 1} more chunks to play');
      }
      // DON'T update _lastPlayedChunkIndex here - let _startProgressivePlayback() handle it
      await _startProgressivePlayback();
    } else {
      // No more chunks, playback complete
      if (kDebugMode) {
        debugPrint('TTSStreaming: Progressive playback fully complete');
      }
      _scheduleCompletion();
    }
  }
}