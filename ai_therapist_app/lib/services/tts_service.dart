// lib/services/tts_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mutex/mutex.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../di/interfaces/i_tts_service.dart';
import '../data/datasources/remote/api_client.dart';
import '../config/app_config.dart';
import 'audio_player_manager.dart';
import 'path_manager.dart';

/// Exception class for TTS-specific errors
class TTSException implements Exception {
  final String message;
  TTSException(this.message);
  @override
  String toString() => 'TTSException: $message';
}

/// Text-to-Speech service that handles speech generation and playback
/// 
/// Extracts all TTS functionality from VoiceService into a focused,
/// single-responsibility service that preserves critical timing fixes.
class TTSService implements ITTSService {
  final AudioPlayerManager _audioPlayerManager;
  final ApiClient _apiClient;

  // WebSocket connection reuse with proper stream handling
  WebSocketChannel? _reusableChannel;
  DateTime? _lastUsed;
  Timer? _keepAliveTimer;
  static const Duration _connectionTimeout = Duration(seconds: 30);
  
  // Stream controller to broadcast WebSocket messages
  StreamController<dynamic>? _messageStreamController;
  StreamSubscription? _wsSubscription;
  
  // Track active TTS sessions to handle concurrent requests
  final Map<String, StreamController<dynamic>> _activeSessions = {};
  
  // Mutex to prevent concurrent TTS operations
  final Mutex _ttsLock = Mutex();
  
  // State management
  bool _isPlaying = false;
  bool _isSpeaking = false;
  bool _disposed = false;
  
  // Stream controllers for state management
  final StreamController<bool> _playbackStateController = StreamController<bool>.broadcast();
  final StreamController<bool> _speakingStateController = StreamController<bool>.broadcast();
  
  // Voice configuration
  String _currentVoice = 'sage';
  String _audioFormat = 'wav';
  
  // Backend URL
  late String _backendUrl;
  
  // File cleanup tracking
  final Set<String> _tempFiles = <String>{};

  /// Constructor
  TTSService({
    required AudioPlayerManager audioPlayerManager,
    required ApiClient apiClient,
  }) : _audioPlayerManager = audioPlayerManager,
       _apiClient = apiClient {
    _initialize();
  }

  // Initialize the service
  void _initialize() {
    _backendUrl = AppConfig().backendUrl;
    
    // Listen to audio player state changes
    _audioPlayerManager.isPlayingStream.listen((isPlaying) {
      _updatePlaybackState(isPlaying);
    });
    
    if (kDebugMode) {
      print('TTSService initialized with backend: $_backendUrl');
    }
  }

  @override
  Future<void> initialize() async {
    // Pre-warm WebSocket connection for faster TTS
    if (!kIsWeb) {
      _getWebSocketConnection().then((connection) {
        if (kDebugMode) print('🔍 [TTS] Pre-warmed connection ready');
      }).catchError((e) {
        if (kDebugMode) print('Pre-warming WebSocket connection failed: $e');
        // Don't fail initialization if WebSocket fails, it will retry when needed
      });
    }
  }

  @override
  Future<String> generateSpeech(String text, {String voice = 'alloy'}) async {
    if (_disposed) throw TTSException('TTSService has been disposed');
    
    try {
      final response = await _apiClient.post('/voice/tts', {
        'text': text,
        'voice': voice,
        'response_format': _audioFormat,
      });
      
      if (response['audio_url'] != null) {
        return response['audio_url'] as String;
      } else if (response['audio_data'] != null) {
        // Handle base64 encoded audio data
        final audioData = base64Decode(response['audio_data']);
        final filePath = await _saveAudioToFile(audioData, _audioFormat);
        return filePath;
      } else {
        throw TTSException('No audio data received from TTS service');
      }
    } catch (e) {
      throw TTSException('Failed to generate speech: $e');
    }
  }

  @override
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
  }) async {
    // START TIMING DIAGNOSTICS
    final totalStopwatch = Stopwatch()..start();
    final wsConnectStopwatch = Stopwatch();
    final firstChunkStopwatch = Stopwatch();

    if (kDebugMode) {
      print('🔍 [TTS TIMING] Starting TTS for text length: ${text.length} chars');
    }

    // Use per-request connections to avoid race conditions
    await _ttsLock.acquire();
    
    try {
      _setIsSpeaking(true);
      
      String? filePath;
      io.File? tempFile;

      try {
        wsConnectStopwatch.start();
        final channel = await _getWebSocketConnection();
        wsConnectStopwatch.stop();
        
        if (kDebugMode) {
          print('🔍 [TTS TIMING] WebSocket ready in: ${wsConnectStopwatch.elapsedMilliseconds}ms');
        }
        
        final List<int> audioBuffer = [];
        final completer = Completer<void>();
        bool firstChunkReceived = false;
        firstChunkStopwatch.start();

        // Generate unique session ID for this TTS request
        final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
        
        // Create session-specific controller
        final sessionController = StreamController<dynamic>.broadcast();
        _activeSessions[sessionId] = sessionController;
        
        // Bullet-proof completer to prevent double completion
        bool done = false;
        void finishTTS([Object? error, StackTrace? st]) {
          if (done) return; // Prevents double complete
          done = true;
          
          // Cleanup session
          _activeSessions.remove(sessionId);
          if (!sessionController.isClosed) {
            sessionController.close();
          }
          
          if (error == null) {
            if (!completer.isCompleted) completer.complete();
          } else {
            if (!completer.isCompleted) completer.completeError(error, st);
          }
        }
        
        // Listen to session-specific messages
        sessionController.stream.listen((data) async {
          try {
            if (data['type'] == 'audio_chunk') {
              if (!firstChunkReceived) {
                firstChunkStopwatch.stop();
                if (kDebugMode) {
                  print('🔍 [TTS TIMING] First audio chunk received after: ${firstChunkStopwatch.elapsedMilliseconds}ms');
                }
                firstChunkReceived = true;
              }
              final chunk = base64Decode(data['data']);
              audioBuffer.addAll(chunk);
              onProgress?.call(audioBuffer.length.toDouble());
            } else if (data['type'] == 'done') {
              // Write buffer to temp file
              try {
                final ext = _audioFormat == 'wav' ? 'wav' : 
                           _audioFormat == 'opus' ? 'ogg' : 'mp3';
                final baseId = DateTime.now().microsecondsSinceEpoch.toString();
                filePath = PathManager.instance.ttsFile(baseId, ext);
                tempFile = io.File(filePath!);
                await tempFile!.writeAsBytes(audioBuffer);
                _tempFiles.add(filePath!);

                if (kDebugMode) {
                  final fileSize = await tempFile!.length();
                  print('TTS audio written to $filePath (size: $fileSize bytes)');
                }

                try {
                  // CRITICAL: 125ms buffer timing fix to prevent Maya from detecting her own voice
                  await Future.delayed(const Duration(milliseconds: 125));
                  
                  // Use AudioPlayerManager to play the audio and await its completion
                  await _audioPlayerManager.playAudio(filePath!);
                  
                  totalStopwatch.stop();
                  if (kDebugMode) {
                    print('🔍 [TTS TIMING] === TOTAL BREAKDOWN ===');
                    print('🔍 [TTS TIMING] WebSocket connect: ${wsConnectStopwatch.elapsedMilliseconds}ms');
                    print('🔍 [TTS TIMING] First chunk wait: ${firstChunkStopwatch.elapsedMilliseconds}ms');
                    print('🔍 [TTS TIMING] TOTAL TIME: ${totalStopwatch.elapsedMilliseconds}ms');
                  }

                  onDone?.call();
                  if (kDebugMode) {
                    print('[TTSService] TTS stream done, audio played successfully');
                  }

                  // Successfully completed
                  finishTTS();
                } catch (e) {
                  if (kDebugMode) print('❌ TTS Playback error: $e');
                  onError?.call('Playback error: $e');
                  finishTTS(e);
                }
              } catch (e) {
                onError?.call('File write error: $e');
                finishTTS(e);
              }
            } else if (data['type'] == 'error') {
              if (kDebugMode) {
                print('[TTSService] TTS stream error: ${data['detail'] ?? 'Unknown error'}');
              }
              onError?.call(data['detail'] ?? 'Unknown error');
              finishTTS(Exception(data['detail'] ?? 'Unknown error'));
            } else if (data['type'] == 'ping') {
              // Handle ping response, don't process as TTS
              if (kDebugMode) print('🔍 [WS] Received ping response');
              return;
            }
          } catch (e) {
            if (kDebugMode) print('[TTSService] Failed to process TTS stream: $e');
            onError?.call('Failed to process TTS stream: $e');
            finishTTS(e);
          }
        }, onError: (err) {
          if (kDebugMode) print('[TTSService] WebSocket error: $err');
          onError?.call('WebSocket error: $err');
          finishTTS(err);
          // Mark connection as invalid so it gets recreated
          _reusableChannel = null;
        }, onDone: () {
          if (kDebugMode) print('[TTSService] WebSocket stream closed');
          // Mark connection as invalid so it gets recreated
          _reusableChannel = null;
        });

        // Send the TTS request with session ID
        final request = {
          'text': text,
          'voice': _currentVoice,
          'params': {'response_format': _audioFormat},
          'session_id': sessionId,
        };
        
        channel.sink.add(jsonEncode(request));
        await completer.future;
        
      } finally {
        // Clean up temp file
        if (tempFile != null && await tempFile!.exists()) {
          try {
            await tempFile!.delete();
            _tempFiles.remove(filePath);
            if (kDebugMode) {
              print('Deleted temp TTS file: $filePath');
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error deleting temp TTS file: $e');
            }
          }
        }
        _setIsSpeaking(false);
      }
    } finally {
      _ttsLock.release();
    }
  }

  @override
  Future<void> playAudio(String audioPath) async {
    if (_disposed) return;
    
    _setIsPlaying(true);
    try {
      await _audioPlayerManager.playAudio(audioPath);
    } catch (e) {
      if (kDebugMode) print('❌ TTSService: Error playing audio: $e');
      rethrow;
    } finally {
      _setIsPlaying(false);
    }
  }

  @override
  Future<void> stopAudio() async {
    await _audioPlayerManager.stopAudio();
    _setIsPlaying(false);
    _setIsSpeaking(false);
  }

  @override
  Future<void> pauseAudio() async {
    // AudioPlayerManager doesn't expose pause, so we stop
    await stopAudio();
  }

  @override
  Future<void> resumeAudio() async {
    // Not supported by current AudioPlayerManager implementation
    if (kDebugMode) {
      print('TTSService: Resume not supported by AudioPlayerManager');
    }
  }

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get playbackStateStream => _playbackStateController.stream;

  @override
  Stream<bool> get speakingStateStream => _speakingStateController.stream;

  @override
  void setVoiceSettings(String voice, double speed, double pitch) {
    _currentVoice = voice;
    // Note: Speed and pitch settings are stored but not currently used in streaming TTS
    // They can be implemented when backend supports these parameters
    
    if (kDebugMode) {
      print('TTSService: Voice settings updated - voice: $voice, speed: $speed, pitch: $pitch');
    }
  }

  @override
  void setAudioFormat(String format) {
    _audioFormat = format;
    
    if (kDebugMode) {
      print('TTSService: Audio format set to: $format');
    }
  }

  @override
  void resetTTSState() {
    _setIsPlaying(false);
    _setIsSpeaking(false);
    
    if (kDebugMode) {
      print('TTSService: State reset');
    }
  }

  @override
  void setAiSpeaking(bool speaking) {
    _setIsSpeaking(speaking);
  }

  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final fileName = 'cached_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = PathManager.instance.ttsFile(fileName, 'mp3');
      
      final file = io.File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      _tempFiles.add(filePath);

      return filePath;
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading audio: $e');
      }
      return null;
    }
  }

  @override
  Future<void> cleanupAudioFiles() async {
    final filesToClean = List<String>.from(_tempFiles);
    _tempFiles.clear();
    
    for (final filePath in filesToClean) {
      try {
        final file = io.File(filePath);
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {
            print('Cleaned up audio file: $filePath');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error cleaning up audio file $filePath: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    if (kDebugMode) print('[TTSService] dispose called');
    
    // Clean up WebSocket connection
    _cleanupConnection();
    
    // Close stream controllers
    _playbackStateController.close();
    _speakingStateController.close();
    
    // Clean up temporary files
    cleanupAudioFiles();
  }

  // Private helper methods

  /// Get or create a reusable WebSocket connection with broadcast stream
  Future<WebSocketChannel> _getWebSocketConnection() async {
    final now = DateTime.now();
    
    // Check if we have a valid connection that's not too old
    if (_reusableChannel != null && 
        _reusableChannel!.closeCode == null &&
        _lastUsed != null &&
        now.difference(_lastUsed!) < _connectionTimeout) {
      _lastUsed = now;
      if (kDebugMode) print('🔍 [TTS WS] Reusing existing connection');
      return _reusableChannel!;
    }
    
    // Clean up old connection
    await _cleanupConnection();
    
    // Create new connection
    final wsUrl = '$_backendUrl/voice/ws/tts'.replaceFirst('http', 'ws');
    if (kDebugMode) print('🔍 [TTS WS] Creating new WebSocket connection to: $wsUrl');
    
    _reusableChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _lastUsed = now;
    
    // Set up broadcast stream for the WebSocket messages
    _setupBroadcastStream();
    
    // Start keep-alive for reusable connection
    _startKeepAlive();
    
    return _reusableChannel!;
  }

  /// Setup broadcast stream to handle multiple concurrent TTS requests
  void _setupBroadcastStream() {
    _messageStreamController?.close();
    _wsSubscription?.cancel();
    
    _messageStreamController = StreamController<dynamic>.broadcast();
    
    _wsSubscription = _reusableChannel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          
          // Route messages to specific sessions
          final sessionId = data['session_id'] as String?;
          if (sessionId != null && _activeSessions.containsKey(sessionId)) {
            _activeSessions[sessionId]!.add(data);
          } else if (data['type'] == 'ping') {
            // Handle ping globally
            if (kDebugMode) print('🔍 [TTS WS] Received ping response');
          } else {
            // Backward compatibility: send to all sessions if no session ID
            for (final controller in _activeSessions.values) {
              if (!controller.isClosed) {
                controller.add(data);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('🔍 [TTS WS] Error parsing message: $e');
        }
      },
      onError: (error) {
        if (kDebugMode) print('🔍 [TTS WS] Stream error: $error');
        // Notify all active sessions of the error
        for (final controller in _activeSessions.values) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        }
        _reusableChannel = null;
      },
      onDone: () {
        if (kDebugMode) print('🔍 [TTS WS] Stream closed');
        // Close all active session controllers
        for (final controller in _activeSessions.values) {
          if (!controller.isClosed) {
            controller.close();
          }
        }
        _activeSessions.clear();
        _messageStreamController?.close();
        _reusableChannel = null;
      },
    );
  }

  /// Clean up WebSocket connection and streams
  Future<void> _cleanupConnection() async {
    _keepAliveTimer?.cancel();
    _wsSubscription?.cancel();
    _messageStreamController?.close();
    
    // Close all active session controllers
    for (final controller in _activeSessions.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _activeSessions.clear();
    
    if (_reusableChannel != null) {
      try {
        await _reusableChannel!.sink.close();
        if (kDebugMode) print('🔍 [TTS WS] WebSocket connection closed');
      } catch (_) {}
      _reusableChannel = null;
    }
  }

  /// Start keep-alive mechanism
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_reusableChannel?.closeCode == null) {
        try {
          _reusableChannel?.sink.add(jsonEncode({'type': 'ping'}));
          if (kDebugMode) print('🔍 [TTS WS] Keep-alive ping sent');
        } catch (e) {
          if (kDebugMode) print('🔍 [TTS WS] Keep-alive failed: $e');
          // Connection failed, will be recreated on next use
          _reusableChannel = null;
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Save audio data to a temporary file
  Future<String> _saveAudioToFile(Uint8List audioData, String format) async {
    final ext = format == 'wav' ? 'wav' : 
               format == 'opus' ? 'ogg' : 'mp3';
    final baseId = DateTime.now().microsecondsSinceEpoch.toString();
    final filePath = PathManager.instance.ttsFile(baseId, ext);
    
    final file = io.File(filePath);
    await file.writeAsBytes(audioData);
    _tempFiles.add(filePath);
    
    if (kDebugMode) {
      print('Audio saved to: $filePath (${audioData.length} bytes)');
    }
    
    return filePath;
  }

  /// Update playback state and notify listeners
  void _updatePlaybackState(bool isPlaying) {
    if (_isPlaying != isPlaying) {
      _isPlaying = isPlaying;
      _playbackStateController.add(isPlaying);
      
      if (kDebugMode) {
        print('TTSService: Playback state changed to $isPlaying');
      }
    }
  }

  /// Set playing state and notify listeners
  void _setIsPlaying(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      _playbackStateController.add(playing);
      
      if (kDebugMode) {
        print('TTSService: Is playing set to $playing');
      }
    }
  }

  /// Set speaking state and notify listeners
  void _setIsSpeaking(bool speaking) {
    if (_isSpeaking != speaking) {
      _isSpeaking = speaking;
      _speakingStateController.add(speaking);
      
      if (kDebugMode) {
        print('TTSService: Is speaking set to $speaking');
      }
    }
  }
}