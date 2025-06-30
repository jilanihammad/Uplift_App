// lib/services/simple_tts_service.dart

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/tts_request.dart';
import '../di/interfaces/i_tts_service.dart';
import 'audio_player_manager.dart';
import 'path_manager.dart';
import '../config/app_config.dart';
import 'package:ai_therapist_app/utils/audio_path_utils.dart';

/// Single-owner TTS service following best-in-class production patterns
/// 
/// This service exclusively owns:
/// - The WebSocket connection to TTS backend (one per request)
/// - The AudioPlayerManager for playback
/// - The request queue for serialization
/// 
/// All callers simply await ttsService.speak(text) without thinking about sockets.
class SimpleTTSService implements ITTSService {
  // -------- Public API -----------------------------------------------
  
  /// Speak text and return when playback is complete
  /// This is the ONLY public method callers need
  @override
  Future<void> speak(String text, {
    String voice = 'sage',
    String format = 'wav'
  }) async {
    if (text.trim().isEmpty) {
      if (kDebugMode) print('❌ [TTS] Empty text, skipping');
      return;
    }

    final req = TtsRequest(text: text.trim(), voice: voice, format: format);
    _queue.add(req);
    _pendingStreams++; // Track this TTS request
    
    if (kDebugMode) {
      print('🔍 [TTS] Queued request: ${req.id} (queue length: ${_queue.length}, pending: $_pendingStreams)');
    }
    
    _pumpQueue(); // Fire-and-forget
    return req.completion; // Caller awaits playback completion
  }

  // -------- Private Implementation ----------------------------------- 

  final ListQueue<TtsRequest> _queue = ListQueue();
  final AudioPlayerManager _audioPlayerManager;
  void Function(bool isSpeaking)? _onTTSComplete;
  
  // Production-grade completion tracking
  int _pendingStreams = 0; // Monotonic counter for overlapping instances
  
  _State _state = _State.idle;
  late String _backendUrl;
  bool _disposed = false;

  SimpleTTSService({
    required AudioPlayerManager audioPlayerManager,
    void Function(bool isSpeaking)? onTTSComplete,
  }) : _audioPlayerManager = audioPlayerManager,
       _onTTSComplete = onTTSComplete {
    _backendUrl = AppConfig().backendUrl;
  }

  /// Set the TTS completion callback (for wiring to AudioGenerator)
  void setCompletionCallback(void Function(bool isSpeaking)? callback) {
    _onTTSComplete = callback;
    if (kDebugMode) {
      print('🔍 [TTS] Completion callback ${callback != null ? 'set' : 'cleared'}');
    }
  }

  Future<void> _pumpQueue() async {
    if (_state != _State.idle || _queue.isEmpty || _disposed) return;
    
    final req = _queue.removeFirst();
    if (kDebugMode) {
      print('🔍 [TTS] Processing request: ${req.id}');
    }
    
    try {
      _state = _State.connecting;
      
      // Create fresh WebSocket for this request (simple pattern)
      final wsUrl = '$_backendUrl/voice/ws/tts'.replaceFirst('http', 'ws');
      if (kDebugMode) print('🔍 [TTS] Creating WebSocket connection to: $wsUrl');
      
      final ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _state = _State.streaming;

      // Process TTS request with fresh connection
      await _processResponse(req, ws);
      
      // Always close the WebSocket after each request (simple pattern)
      await ws.sink.close();
      if (kDebugMode) print('🔍 [TTS] WebSocket closed for ${req.id}');
      
      req.complete();
      if (kDebugMode) {
        print('✅ [TTS] Completed request: ${req.id}');
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [TTS] Request failed: ${req.id} - $e');
      }
      req.completeError(e, stackTrace);
      _fireCompletionSafely(false); // Reset TTS state on ANY error
    } finally {
      _pendingStreams--; // Decrement when done (success or error)
      if (kDebugMode) {
        print('🔍 [TTS] Pending streams decremented to: $_pendingStreams');
      }
      
      // Only fire completion when ALL streams are done
      if (_pendingStreams <= 0) {
        _fireCompletionSafely(false);
      }
      
      _state = _State.idle;
      // Tail-recursion: pump next job
      _pumpQueue();
    }
  }

  Future<void> _processResponse(TtsRequest req, WebSocketChannel ws) async {
    final audioBuffer = <int>[];
    bool gotHello = false;
    
    // Send TTS request
    ws.sink.add(jsonEncode({
      'text': req.text,
      'voice': req.voice,
      'params': {'response_format': req.format},
      'session_id': req.id,
    }));

    // Listen for response (single subscription pattern)
    await for (final message in ws.stream) {
      if (message is String) {
        final data = jsonDecode(message);
        final type = data['type'];
        
        if (type == 'tts-hello') {
          gotHello = true;
          if (kDebugMode) print('🔍 [TTS] Got tts-hello for ${req.id}');
        } else if (type == 'tts-done') {
          if (kDebugMode) print('🔍 [TTS] Got tts-done for ${req.id}');
          break; // Exit the await for loop
        } else if (type == 'error') {
          throw Exception(data['detail'] ?? 'TTS error');
        }
      } else if (message is List<int>) {
        audioBuffer.addAll(message);
        // LOG SPAM FIX: Only log at meaningful milestones (64KB intervals) instead of every 4KB
        if (kDebugMode && audioBuffer.length % 65536 == 0) {
          print('🔍 [TTS] Buffered ${audioBuffer.length} bytes for ${req.id}');
        }
      }
    }
    
    if (!gotHello) {
      throw Exception('Did not receive tts-hello');
    }
    
    if (audioBuffer.isEmpty) {
      throw Exception('No audio data received');
    }
    
    if (kDebugMode) {
      print('🔍 [TTS] Buffering complete: ${audioBuffer.length} total bytes for ${req.id}');
    }
    
    // Save audio buffer to temporary file and play
    final audioFile = await _saveAudioBuffer(audioBuffer, req.format);
    
    try {
      if (kDebugMode) print('🔍 [TTS] Starting audio playback for ${req.id}');
      
      // Wait for audio playback to completely finish
      await _audioPlayerManager.playAudio(audioFile.path);
      
      if (kDebugMode) print('✅ [TTS] Audio playback completed for ${req.id}');
    } catch (audioError) {
      if (kDebugMode) print('❌ [TTS] Audio playback failed: $audioError');
      rethrow;
    } finally {
      // Clean up temporary file after playback (success or failure)
      try {
        await audioFile.delete();
        if (kDebugMode) print('🔍 [TTS] Cleaned up temp file for ${req.id}');
      } catch (e) {
        if (kDebugMode) print('⚠️ [TTS] Could not delete temp file: $e');
      }
    }
  }

  Future<io.File> _saveAudioBuffer(List<int> audioBuffer, String format) async {
    final ext = format == 'wav' ? 'wav' : 
               format == 'opus' ? 'ogg' : 'mp3';
    // Generate clean ID without extension using utility - prevents double extensions
    final fileId = AudioPathUtils.generateTimestampId('tts');
    final filePath = PathManager.instance.ttsFile(fileId, ext);
    
    final file = io.File(filePath);
    await file.writeAsBytes(audioBuffer);
    
    if (kDebugMode) {
      print('🔍 [TTS] Saved ${audioBuffer.length} bytes to: $filePath');
    }
    
    return file;
  }

  // -------- ITTSService Interface (Minimal Implementation) -----------

  @override
  Future<void> initialize() async {
    // Pre-warm AudioPlayerManager if needed
  }

  @override
  Future<String> generateSpeech(String text, {String voice = 'alloy'}) async {
    // Not used in new architecture - everything goes through speak()
    throw UnimplementedError('Use speak() method instead');
  }

  @override
  Future<void> streamAndPlayTTS(String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  }) async {
    // Legacy method - delegate to new speak() API
    try {
      await speak(text);
      onDone?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> streamAndPlayTTSChunked(Stream<String> textStream, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  }) async {
    // Collect all text first, then speak it
    final buffer = StringBuffer();
    await for (final chunk in textStream) {
      buffer.write(chunk);
    }
    
    try {
      await speak(buffer.toString());
      onDone?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> playAudio(String audioPath) async {
    await _audioPlayerManager.playAudio(audioPath);
  }

  @override
  Future<void> stopAudio() async {
    await _audioPlayerManager.stopAudio();
  }

  @override
  Future<void> pauseAudio() async {
    await _audioPlayerManager.stopAudio();
  }

  @override
  Future<void> resumeAudio() async {
    // Not supported
  }

  @override
  bool get isPlaying => _audioPlayerManager.isPlaying;

  @override
  bool get isSpeaking => _state != _State.idle;

  @override
  Stream<bool> get playbackStateStream => _audioPlayerManager.isPlayingStream;

  @override
  Stream<bool> get speakingStateStream => 
      Stream.periodic(const Duration(milliseconds: 100), (_) => isSpeaking);

  @override
  void setVoiceSettings(String voice, double speed, double pitch) {
    // Settings stored but not used in this simplified version
  }

  @override
  void setAudioFormat(String format) {
    // Settings stored but not used in this simplified version
  }

  @override
  void resetTTSState() {
    // State is automatically managed
  }

  @override
  void setAiSpeaking(bool speaking) {
    // State is automatically managed
  }

  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    // Not used in new architecture
    return null;
  }

  @override
  Future<void> cleanupAudioFiles() async {
    // AudioPlayerManager handles cleanup
  }

  /// Safely fire completion callback on main thread (handles background isolate events)
  void _fireCompletionSafely(bool isSpeaking) {
    if (_onTTSComplete != null) {
      // Handle background thread events from just_audio using scheduleMicrotask
      scheduleMicrotask(() {
        _onTTSComplete!(isSpeaking);
        if (kDebugMode) {
          print('🔍 [TTS] Fired completion callback: isSpeaking=$isSpeaking (pending: $_pendingStreams)');
        }
      });
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    // Complete all pending requests with error
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      req.completeError(Exception('Service disposed'));
    }
    
    // Reset TTS state on disposal
    _fireCompletionSafely(false);
    
    if (kDebugMode) print('🔍 [TTS] Service disposed');
  }
}

enum _State { idle, connecting, streaming }