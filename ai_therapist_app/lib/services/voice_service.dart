// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:async/async.dart';
import 'package:mutex/mutex.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:just_audio/just_audio.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:ai_therapist_app/config/api.dart';
import 'package:ai_therapist_app/data/models/log_entry.dart';
import 'package:ai_therapist_app/data/repositories/log_repo.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import '../config/app_config.dart'; // Import AppConfig
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auto_listening_coordinator.dart';
import 'vad_manager.dart';
import 'audio_player_manager.dart';
import 'recording_manager.dart';
import 'base_voice_service.dart' as base_voice;
import 'path_manager.dart';

/// File cleanup manager to prevent race conditions from multiple deletion attempts
class FileCleanupManager {
  static final Set<String> _deletingFiles = <String>{};

  /// Safely delete a file, preventing race conditions from multiple deletion attempts
  static Future<void> safeDelete(String filePath) async {
    if (_deletingFiles.contains(filePath)) {
      if (kDebugMode) {
        print('🗑️ File deletion already in progress for: $filePath');
      }
      return;
    }

    _deletingFiles.add(filePath);
    try {
      final file = io.File(filePath);
      if (await file.exists()) {
        await file.delete();
        if (kDebugMode) {
          print('🗑️ Successfully deleted file: $filePath');
        }
      } else {
        if (kDebugMode) {
          print('🗑️ File already deleted: $filePath');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🗑️ Error deleting file $filePath: $e');
      }
    } finally {
      _deletingFiles.remove(filePath);
    }
  }
}

// Recording states
// enum RecordingState { ready, recording, stopped, paused, error } // Now defined in base_voice_service.dart or RecordingManager

// Transcription models
enum TranscriptionModel { gpt4oMini, deepgramAI, assembly }

// Top-level function for Isolate file processing (must be outside any class for compute)
Future<Map<String, dynamic>> processAudioFileInIsolate(
    Map<String, dynamic> args) async {
  final String recordedFilePath = args['recordedFilePath'] as String;
  final file = io.File(recordedFilePath);
  bool fileExists = await file.exists();
  if (!fileExists) {
    return {'error': 'Audio file does not exist at path: $recordedFilePath'};
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return {'error': 'Audio file is empty.'};
  }
  String base64Audio = base64Encode(bytes);
  while (base64Audio.length % 4 != 0) {
    base64Audio += '=';
  }
  return {
    'base64Audio': base64Audio,
    'fileSize': bytes.length,
  };
}

/// Exception class for playback errors
class PlaybackException implements Exception {
  final String message;
  PlaybackException(this.message);
  @override
  String toString() => 'PlaybackException: $message';
}

class VoiceService {
  // Singleton instance
  static VoiceService? _instance;

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
  
  // Stream controllers for voice recording states - REMOVED
  // StreamController<RecordingState>? _recordingStateController;
  // Stream<RecordingState>? _recordingStateStream;
  // Stream<RecordingState> get recordingState {
  //   _ensureStreamControllerIsActive();
  //   return _recordingStateStream!;
  // }
  // Expose RecordingManager's stream directly
  Stream<base_voice.RecordingState> get recordingState =>
      _recordingManager.recordingStateStream;

  // Current state of recording - REMOVED
  // RecordingState _currentState = RecordingState.ready;

  // Path to the CSM directory
  String? _csmPath;

  // Speaker IDs
  final int _userSpeakerId = 0; // Speaker A
  final int _aiSpeakerId = 1; // Speaker B

  // Audio context for the conversation
  List<Map<String, dynamic>> _conversationContext = [];

  // Generated audio path
  String? _lastGeneratedAudioPath;

  // Recording related - REMOVED
  // late final AudioRecorder _audioRecorder;
  String?
      _recordingPath; // This might still be useful if VoiceService needs to know the last path

  // API client for making requests to backend
  final ApiClient _apiClient;

  // Backend server URL
  late String _backendUrl;

  // Getter for accessing backend URL from other services
  String get apiUrl => _backendUrl;

  // Flag to indicate if we're running in a web environment
  final bool _isWeb = kIsWeb;

  bool _isInitialized = false;
  bool _disposed = false;

  // Stream controllers for audio playback states
  final StreamController<bool> _audioPlaybackController =
      StreamController<bool>.broadcast();
  Stream<bool> get audioPlaybackStream => _audioPlaybackController.stream;

  // Stream specifically for TTS speaking state - we keep this for API compatibility
  final StreamController<bool> _ttsSpeakingStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get isTtsActuallySpeaking => _ttsSpeakingStateController.stream;

  // REMOVED: AudioPlayer? _currentPlayer; // Consolidating to use only AudioPlayerManager

  bool isAiSpeaking = false;

  // Add coordinator and VAD manager
  late final VADManager _vadManager;
  late final AutoListeningCoordinator _autoListeningCoordinator;
  late final AudioPlayerManager _audioPlayerManager;
  late final RecordingManager _recordingManager;

  // Expose coordinator's streams
  Stream<AutoListeningState> get autoListeningStateStream =>
      _autoListeningCoordinator.stateStream;
  Stream<bool> get autoListeningModeEnabledStream =>
      _autoListeningCoordinator.autoModeEnabledStream;
  AutoListeningCoordinator get autoListeningCoordinator =>
      _autoListeningCoordinator;

  // Passthrough methods for auto mode control
  Future<void> enableAutoMode() async {
    if (kDebugMode) {
      print(
          '[VoiceService] enableAutoMode called (using AudioPlayerManager state)');
    }
    await _autoListeningCoordinator.enableAutoMode();
  }

  Future<void> disableAutoMode() async {
    if (kDebugMode) print('[VoiceService] disableAutoMode() called');
    await _autoListeningCoordinator.disableAutoMode();
    if (kDebugMode)
      print(
          '[VoiceService] disableAutoMode() completed. autoModeEnabled=${_autoListeningCoordinator.autoModeEnabled}');
  }

  // Enable auto mode with explicit audio state from Bloc
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    if (kDebugMode) {
      print(
          '[VoiceService] enableAutoModeWithAudioState called with isAudioPlaying=$isAudioPlaying');
    }
    await _autoListeningCoordinator
        .enableAutoModeWithAudioState(isAudioPlaying);
  }

  // Factory constructor to enforce singleton pattern
  factory VoiceService({required ApiClient apiClient}) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        print('Reusing existing VoiceService instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = VoiceService._internal(apiClient: apiClient);
    return _instance!;
  }

  // Private constructor for singleton pattern
  VoiceService._internal({required ApiClient apiClient})
      : _apiClient = apiClient {
    // _audioRecorder = AudioRecorder(); // REMOVED
    // _ensureStreamControllerIsActive(); // REMOVED, no local controller
    _audioPlayerManager = AudioPlayerManager();
    _recordingManager = RecordingManager(); // Already initialized here
    _vadManager = VADManager();
    _autoListeningCoordinator = AutoListeningCoordinator(
      audioPlayerManager: _audioPlayerManager,
      recordingManager: _recordingManager,
      voiceService: this,
      vadManager: _vadManager,
    );
    if (kDebugMode) {
      print('VoiceService initialized with constructor injection');
      print(
          '[VoiceService] AutoListeningCoordinator initialized. Forcing auto mode enabled.');
    }
  }

  // Check if service is initialized
  bool get isInitialized => _isInitialized;

  // Method to initialize the service only if it hasn't been initialized yet
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // Method to initialize the voice service
  Future<void> initialize() async {
    // Skip if already initialized
    if (_isInitialized) {
      if (kDebugMode) {
        print('VoiceService already initialized, skipping initialize()');
      }
      return;
    }

    try {
      // Get backend URL from AppConfig instead of hardcoding
      _backendUrl = AppConfig().backendUrl;

      if (kDebugMode) {
        print('Voice service initialized with API client');
      }

      // For web platform, use a simplified initialization
      if (_isWeb) {
        if (kDebugMode) {
          print('Initializing voice service in web mode');
        }
        // _currentState = RecordingState.ready; // REMOVED
        // _recordingStateController!.add(_currentState); // REMOVED
        _isInitialized = true;
        return;
      }

      // Request microphone permissions for recording (non-web platforms) - Handled by RecordingManager
      // if (!_isWeb) {
      //   var status = await Permission.microphone.request();
      //   if (status != PermissionStatus.granted) {
      //     throw Exception("Microphone permission not granted");
      //   }
      // }

      // Reset the conversation context
      _conversationContext = [];

      // _currentState = RecordingState.ready; // REMOVED
      // _recordingStateController!.add(_currentState); // REMOVED

      _isInitialized = true;

      // Pre-warm WebSocket connection for faster TTS
      if (!_isWeb) {
        _getWebSocketConnection().then((connection) {
          if (kDebugMode) print('🔍 [WS] Pre-warmed connection ready');
        }).catchError((e) {
          if (kDebugMode) print('Pre-warming WebSocket connection failed: $e');
          // Don't fail initialization if WebSocket fails, it will retry when needed
        });
      }

      if (kDebugMode) {
        print('Voice service initialized successfully');
      }
    } catch (e) {
      // _currentState = RecordingState.error;
      // try {
      //   if (_recordingStateController != null &&
      //       !_recordingStateController!.isClosed) {
      //     _recordingStateController!.add(_currentState);
      //   }
      // } catch (streamError) {
      //   if (kDebugMode) {
      //     print('Error sending state to stream: $streamError');
      //   }
      // }

      if (kDebugMode) {
        print('Error initializing voice service: $e');
      }
      // Don't rethrow the error in web mode
      if (!_isWeb) {
        rethrow;
      }
    }
  }

  // Start recording
  Future<void> startRecording() async {
    // try { // REMOVED outer try-catch, delegate to RecordingManager
    if (kDebugMode) {
      print(
          '⏺️ VOICE DEBUG: VoiceService.startRecording called - delegating to RecordingManager');
    }

    if (_isWeb) {
      // Simulate recording in web mode - Potentially remove if RecordingManager handles web differently or not at all
      // _currentState = RecordingState.recording; // REMOVED
      // _recordingStateController!.add(_currentState); // REMOVED
      if (kDebugMode) {
        print(
            'Recording started (web mode simulation in VoiceService) - Review if RecordingManager handles this');
      }
      // For now, web will be a no-op here as RecordingManager likely handles native.
      // If web recording is needed, RecordingManager should support it.
      return;
    }

    // Delegate to RecordingManager
    await _recordingManager.startRecording();

    // } catch (e) { // REMOVED
    //   _currentState = RecordingState.error;
    //   try {
    //     if (_recordingStateController != null &&
    //         !_recordingStateController!.isClosed) {
    //       _recordingStateController!.add(_currentState);
    //     }
    //   } catch (streamError) {
    //     if (kDebugMode) {
    //       print('❌ VOICE ERROR: Error sending state to stream: $streamError');
    //     }
    //   }
    //
    //   if (kDebugMode) {
    //     print('❌ VOICE ERROR: Error starting recording: $e');
    //   }
    //   if (!_isWeb) rethrow;
    // }
  }

  /// Stops the current recording session if active.
  ///
  /// Returns the path to the recorded file, or null if not recording.
  /// Throws [NotRecordingException] if called when not recording.
  Future<String?> stopRecording() async {
    if (kDebugMode) {
      print(
          '⏹️ VOICE DEBUG: VoiceService.stopRecording called - delegating to RecordingManager');
    }

    String? recordedFilePath;

    if (!_isWeb) {
      try {
        // Delegate to RecordingManager
        recordedFilePath = await _recordingManager.stopRecording();
        _recordingPath = recordedFilePath;
      } on NotRecordingException catch (e) {
        if (kDebugMode) {
          print('⏹️ VOICE DEBUG: Not recording, nothing to stop. ($e)');
        }
        return null;
      } catch (e) {
        if (kDebugMode) {
          print('⏹️ VOICE DEBUG: Error stopping recording: $e');
        }
        rethrow;
      }
    }
    return recordedFilePath;
  }

  // New method to process an already recorded audio file
  Future<String> processRecordedAudioFile(String recordedFilePath) async {
    if (kDebugMode) {
      print(
          '⏹️ VOICE DEBUG: VoiceService.processRecordedAudioFile called with path: $recordedFilePath');
    }

    if (recordedFilePath.isEmpty) {
      if (kDebugMode) {
        print(
            '❌ VOICE ERROR: processRecordedAudioFile: Empty file path provided.');
      }
      return "Error: No audio file path provided.";
    }

    try {
      // Use compute to offload file I/O and encoding
      final result = await compute(
          processAudioFileInIsolate, {'recordedFilePath': recordedFilePath});
      if (result['error'] != null) {
        if (kDebugMode) print('❌ VOICE ERROR: ${result['error']}');
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: ${result['error']} Please try again.";
      }
      final String base64Audio = result['base64Audio'];
      final int fileSize = result['fileSize'];
      if (kDebugMode) {
        print(
            '⏹️ VOICE DEBUG: Audio file encoded in isolate, size: $fileSize bytes, base64 length: ${base64Audio.length}');
      }
      // Continue with API call as before
      try {
        final startTime = DateTime.now();
        if (kDebugMode) {
          print(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Making API call to transcribe audio...');
        }
        final response = await _apiClient.post('/voice/transcribe', body: {
          'audio_data': base64Audio,
          'audio_format': 'm4a',
          'model': 'gpt-4o-mini-transcribe'
        });
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        if (kDebugMode) {
          print(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Transcription API response in \\${duration}ms: $response');
        }
        final transcription = response['text'] as String;
        if (kDebugMode) {
          print(
              '⏹️ VOICE DEBUG: processRecordedAudioFile: Transcription result: $transcription');
        }
        // Successfully transcribed, now delete the file
        await FileCleanupManager.safeDelete(recordedFilePath);
        return transcription.isNotEmpty ? transcription : "";
      } catch (e) {
        if (kDebugMode) {
          print(
              '❌ VOICE ERROR: processRecordedAudioFile: Error calling transcription API: $e');
        }
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: Unable to transcribe audio. Please try again.";
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ VOICE ERROR: processRecordedAudioFile: Error processing audio file: $e');
      }
      try {
        final file = io.File(recordedFilePath);
        if (await file.exists()) {
          await FileCleanupManager.safeDelete(recordedFilePath);
        }
      } catch (delErr) {
        if (kDebugMode)
          print(
              '❌ VOICE ERROR: processRecordedAudioFile: Error deleting file during cleanup: $delErr');
      }
      return "Error: Problem processing audio. Please try again.";
    }
  }

  // Note: File deletion is now handled by FileCleanupManager.safeDelete

  /// Get or create a reusable WebSocket connection with broadcast stream
  Future<WebSocketChannel> _getWebSocketConnection() async {
    final now = DateTime.now();
    
    // Check if we have a valid connection that's not too old
    if (_reusableChannel != null && 
        _reusableChannel!.closeCode == null &&
        _lastUsed != null &&
        now.difference(_lastUsed!) < _connectionTimeout) {
      _lastUsed = now;
      if (kDebugMode) print('🔍 [WS] Reusing existing connection');
      return _reusableChannel!;
    }
    
    // Clean up old connection
    await _cleanupConnection();
    
    // Create new connection
    final wsUrl = 'wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts';
    if (kDebugMode) print('🔍 [WS] Creating new WebSocket connection...');
    
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
            if (kDebugMode) print('🔍 [WS] Received ping response');
          } else {
            // Backward compatibility: send to all sessions if no session ID
            for (final controller in _activeSessions.values) {
              if (!controller.isClosed) {
                controller.add(data);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('🔍 [WS] Error parsing message: $e');
        }
      },
      onError: (error) {
        if (kDebugMode) print('🔍 [WS] Stream error: $error');
        // Notify all active sessions of the error
        for (final controller in _activeSessions.values) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        }
        _reusableChannel = null;
      },
      onDone: () {
        if (kDebugMode) print('🔍 [WS] Stream closed');
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
      } catch (_) {}
      _reusableChannel = null;
    }
  }

  /// Start keep-alive mechanism
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 25), (timer) {
      if (_reusableChannel?.closeCode == null) {
        try {
          _reusableChannel?.sink.add(jsonEncode({'type': 'ping'}));
          if (kDebugMode) print('🔍 [WS] Keep-alive ping sent');
        } catch (e) {
          if (kDebugMode) print('🔍 [WS] Keep-alive failed: $e');
          // Connection failed, will be recreated on next use
          _reusableChannel = null;
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Stream TTS audio from backend and play it
  Future<String?> streamAndPlayTTS({
    required String text,
    String voice = 'sage',
    String responseFormat = 'wav',
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    // START TIMING DIAGNOSTICS
    final totalStopwatch = Stopwatch()..start();
    final wsConnectStopwatch = Stopwatch();
    final firstChunkStopwatch = Stopwatch();

    if (kDebugMode)
      print(
          '🔍 [TTS TIMING] Starting TTS for text length: ${text.length} chars');

    // Note: isAiSpeaking state is managed by the calling helper methods and _onPlaybackDone()
    String? filePath;
    io.File? tempFile; // Keep a reference to the file

    try {
      // Use per-request connections to avoid race conditions
      wsConnectStopwatch.start();
      // Note: Connection creation is now done below in the subscription setup
      wsConnectStopwatch.stop();
      
      if (kDebugMode) {
        print('🔍 [TTS TIMING] WebSocket connecting...');
      }
      
      final List<int> audioBuffer = [];
      StreamSubscription? subscription;

      final request = jsonEncode({
        'text': text,
        'voice': voice,
        'params': {'response_format': responseFormat},
      });

      final completer = Completer<String?>();
      bool firstChunkReceived = false;
      firstChunkStopwatch.start();

      // Generate unique session ID for this TTS request
      final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
      
      // Use connection reuse but with proper session isolation
      wsConnectStopwatch.start();
      final channel = await _getWebSocketConnection();
      wsConnectStopwatch.stop();
      
      if (kDebugMode) {
        print('🔍 [TTS TIMING] WebSocket ready in: ${wsConnectStopwatch.elapsedMilliseconds}ms');
      }
      
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
          if (!completer.isCompleted) completer.complete(filePath);
        } else {
          if (!completer.isCompleted) completer.completeError(error, st);
        }
      }
      
      // Listen to session-specific messages
      subscription = sessionController.stream.listen((data) async {
        try {
          if (data['type'] == 'audio_chunk') {
            if (!firstChunkReceived) {
              firstChunkStopwatch.stop();
              if (kDebugMode)
                print(
                    '🔍 [TTS TIMING] First audio chunk received after: ${firstChunkStopwatch.elapsedMilliseconds}ms');
              firstChunkReceived = true;
            }
            final chunk = base64Decode(data['data']);
            audioBuffer.addAll(chunk);
            // Optionally, call onProgress
          } else if (data['type'] == 'done') {
            // Write buffer to temp file
            try {
              // Updated file extension logic for WAV format
              final ext = responseFormat == 'wav'
                  ? 'wav'
                  : responseFormat == 'opus'
                      ? 'ogg'
                      : 'mp3';
              // NEW CODE (collision-resistant with cleaner API):
              final baseId = DateTime.now().microsecondsSinceEpoch.toString();
              filePath = PathManager.instance.ttsFile(baseId, ext);
              tempFile = io.File(filePath!);
              await tempFile!.writeAsBytes(audioBuffer);

              if (kDebugMode) {
                final fileSize = await tempFile!.length();
                print('TTS audio written to $filePath (size: $fileSize bytes)');
              }

              try {
                // Use AudioPlayerManager to play the audio and await its completion
                await _audioPlayerManager.playAudio(filePath!);
                // Playback is complete here
                // Note: isAiSpeaking state will be cleared by _onPlaybackDone() in generateAudio()

                totalStopwatch.stop();
                if (kDebugMode) {
                  print('🔍 [TTS TIMING] === TOTAL BREAKDOWN ===');
                  print(
                      '🔍 [TTS TIMING] WebSocket connect: ${wsConnectStopwatch.elapsedMilliseconds}ms');
                  print(
                      '🔍 [TTS TIMING] First chunk wait: ${firstChunkStopwatch.elapsedMilliseconds}ms');
                  print(
                      '🔍 [TTS TIMING] TOTAL TIME: ${totalStopwatch.elapsedMilliseconds}ms');
                }

                onDone?.call();
                if (kDebugMode)
                  print(
                      '[VoiceService] [TTS] TTS stream done, audio played by manager');

                // Successfully completed - return immediately to prevent fallback
                finishTTS();
                return; // ← EXIT HERE ON SUCCESS - prevents double completion
              } catch (e) {
                if (kDebugMode) print('❌ Playback error: $e');
                onError?.call('Playback error: $e');
                finishTTS(e);
              }
            } catch (e) {
              onError?.call('File write error: $e');
              finishTTS(e);
            }
            await subscription?.cancel();
          } else if (data['type'] == 'error') {
            if (kDebugMode)
              print(
                  '[VoiceService] [TTS] TTS stream error: ${data['detail'] ?? 'Unknown error'}');
            onError?.call(data['detail'] ?? 'Unknown error');
            finishTTS(Exception(data['detail'] ?? 'Unknown error'));
            await subscription?.cancel();
          } else if (data['type'] == 'ping') {
            // Handle ping response, don't process as TTS
            if (kDebugMode) print('🔍 [WS] Received ping response');
            return;
          }
        } catch (e) {
          if (kDebugMode)
            print('[VoiceService] [TTS] Failed to process TTS stream: $e');
          onError?.call('Failed to process TTS stream: $e');
          finishTTS(e);
          await subscription?.cancel();
        }
      }, onError: (err) async {
        if (kDebugMode) print('[VoiceService] [TTS] WebSocket error: $err');
        onError?.call('WebSocket error: $err');
        finishTTS(err);
        await subscription?.cancel();
        // Mark connection as invalid so it gets recreated
        _reusableChannel = null;
      }, onDone: () async {
        if (kDebugMode) print('[VoiceService] [TTS] WebSocket stream closed');
        await subscription?.cancel();
        // Mark connection as invalid so it gets recreated
        _reusableChannel = null;
      });

      // Send the TTS request with session ID
      final requestData = jsonDecode(request);
      requestData['session_id'] = sessionId;
      channel.sink.add(jsonEncode(requestData));
      return await completer.future;
    } finally {
      // No longer set isAiSpeaking = false here, already done immediately after playback

      // Ensure file deletion even if errors occurred before playback completion,
      // or if playback itself errored (handled by playAudio returning Future.error)
      if (tempFile != null && await tempFile!.exists()) {
        try {
          await tempFile!.delete();
          if (kDebugMode)
            print('Deleted temp TTS file (finally block): $filePath');
        } catch (e) {
          if (kDebugMode)
            print('Error deleting temp TTS file (finally block): $e');
        }
      }
    }
  }

  /// Helper method to stream and play WAV audio
  Future<String?> _streamAndPlayWav(String text) async {
    // Set speaking state to true when starting TTS
    _setAiSpeaking(true);
    try {
      final result = await streamAndPlayTTS(
        text: text,
        responseFormat: 'wav',
      );
      if (result == null) {
        throw PlaybackException('WAV TTS generation failed');
      }
      return result;
    } catch (e) {
      throw PlaybackException('WAV TTS error: $e');
    }
  }

  /// Helper method to stream and play MP3 audio as fallback
  Future<String?> _streamAndPlayMp3(String text) async {
    // State should already be true from WAV attempt or explicit setting
    try {
      final result = await streamAndPlayTTS(
        text: text,
        responseFormat: 'mp3',
      );
      if (result == null) {
        throw PlaybackException('MP3 TTS generation failed');
      }
      return result;
    } catch (e) {
      throw PlaybackException('MP3 TTS error: $e');
    }
  }

  // Serialized TTS generation with automatic fallback using mutex lock
  Future<String?> generateAudio(
    String text, {
    String voice = 'sage',
    String responseFormat =
        'wav', // Changed from 'opus' to 'wav' for lowest latency
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    // Serialize all TTS requests to prevent concurrent access
    await _ttsLock.acquire();
    try {
      if (_disposed) return null;

      String? filePath;
      try {
        filePath = await _streamAndPlayWav(text);
        _onPlaybackDone(); // Clear state only after successful completion
        onDone?.call();
        return filePath;
      } on PlaybackException catch (_) {
        // When entering retry/fallback, keep isAiSpeaking = true so coordinator doesn't start VAD
        _setAiSpeaking(true); // Ensure state stays true during retry
        if (kDebugMode) {
          print('[VoiceService] Entering MP3 fallback, keeping isAiSpeaking = true');
        }
        try {
          filePath = await _streamAndPlayMp3(text); // one-shot fallback
          _onPlaybackDone(); // Clear state only after successful completion
          onDone?.call();
          return filePath;
        } catch (fallbackError) {
          // Only clear the state if both attempts failed completely
          _onPlaybackDone();
          onError?.call('Both WAV and MP3 TTS failed: $fallbackError');
          return null;
        }
      }
    } catch (e) {
      // Clear state on any unexpected error
      _onPlaybackDone();
      onError?.call('TTS generation error: $e');
      return null;
    } finally {
      _ttsLock.release();
    }
  }

  // Play an audio file
  Future<void> playAudio(String audioPath) async {
    _audioPlaybackController.add(true);

    try {
      if (kDebugMode) {
        print('🔊 VoiceService: Beginning audio playback of $audioPath');
      }

      // Stop any existing audio before starting new playback
      await _audioPlayerManager.stopAudio();

      // Request audio focus before playback
      final session = await AudioSession.instance;
      final focusGranted = await session.setActive(true);
      if (!focusGranted) {
        if (kDebugMode)
          print('🔊 VoiceService: Audio session activation NOT granted');
        _audioPlaybackController.add(false);
        return;
      } else {
        if (kDebugMode) print('🔊 VoiceService: Audio session activated');
      }

      session.becomingNoisyEventStream.listen((_) {
        if (kDebugMode)
          print(
              '🔊 VoiceService: Audio becoming noisy (e.g. headphones unplugged)');
        stopAudio();
      });
      session.interruptionEventStream.listen((event) {
        if (kDebugMode) print('🔊 VoiceService: Audio interruption: $event');
        if (event.begin) stopAudio();
      });

      if (audioPath.startsWith('local_tts://')) {
        if (kDebugMode) {
          print(
              '🔊 VoiceService: Detected local TTS fallback path, using text-to-speech');
        }
        // _useTtsBackup will manage the _ttsSpeakingStateController
        await _useTtsBackup();
        _audioPlaybackController
            .add(false); // Signal general audio playback ended
        return;
      }

      if (audioPath.startsWith('http')) {
        if (kDebugMode) {
          print('🔊 VoiceService: Playing audio from URL: $audioPath');
        }
        if (!_isWeb) {
          // Use AudioPlayerManager for URL playback by downloading first
          try {
            final localPath = await _downloadAndCacheAudio(audioPath);
            if (localPath != null) {
              await _audioPlayerManager.playAudio(localPath);
              // AudioPlayerManager will handle state updates
              _audioPlayerManager.isPlayingStream.listen((isPlaying) {
                _audioPlaybackController.add(isPlaying);
              });
            } else {
              throw Exception('Failed to download audio from URL');
            }
          } catch (e) {
            if (kDebugMode) print('🔊 VoiceService: Error playing URL: $e');
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS if URL play fails
          }
        } else {
          // Web playback simulation
          await Future.delayed(const Duration(seconds: 2));
          _audioPlaybackController.add(false);
        }
      } else if (!_isWeb) {
        final file = io.File(audioPath);
        if (await file.exists()) {
          if (kDebugMode)
            print('🔊 VoiceService: Playing local audio file: $audioPath');
          try {
            await _audioPlayerManager.playAudio(audioPath);
            // AudioPlayerManager will handle state updates
            _audioPlayerManager.isPlayingStream.listen((isPlaying) {
              _audioPlaybackController.add(isPlaying);
            });
          } catch (e) {
            if (kDebugMode)
              print('🔊 VoiceService: Error playing local file: $e');
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS
          }
        } else {
          if (kDebugMode)
            print('🔊 VoiceService: File not found $audioPath, using TTS');
          _audioPlaybackController.add(false);
          await _useTtsBackup();
        }
      } else {
        // Web, non-HTTP path - likely an error or needs TTS
        if (kDebugMode)
          print(
              '🔊 VoiceService: Unhandled audio path on web: $audioPath, using TTS');
        _audioPlaybackController.add(false);
        await _useTtsBackup();
      }
    } catch (e) {
      if (kDebugMode) print('🔊 VoiceService: Error in playAudio: $e');
      _audioPlaybackController.add(false);
      await _useTtsBackup(); // Fallback to TTS on any error
      // AudioPlayerManager handles its own cleanup
    }
  }

  // Stop any ongoing audio playback
  Future<void> stopAudio() async {
    try {
      if (kDebugMode) {
        print('Stopping any ongoing audio playback');
      }

      // Signal that audio playback has stopped to listeners
      _audioPlaybackController.add(false);

      // Stop the AudioPlayerManager and force its state
      await _audioPlayerManager.stopAudio();
      _audioPlayerManager
          .forceStopState(); // Force the state to false immediately

      if (kDebugMode) {
        print('Audio playback stopped successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping audio: $e');
      }

      // Ensure we signal playback stopped even on error
      try {
        _audioPlaybackController.add(false);
        _audioPlayerManager.forceStopState(); // Force stop even on error
      } catch (_) {}
    }
  }

  // Download a remote audio file and cache it locally
  Future<String?> _downloadAndCacheAudio(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      // Get temporary directory for caching using PathManager
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final cacheDir = PathManager.instance.cacheDir;
      final filePath = p.join(cacheDir, fileName);

      // Write the audio data to a file
      final file = io.File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      return filePath;
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading audio: $e');
      }
      return null;
    }
  }

  // Fallback to text-to-speech when audio file is not available
  Future<void> _useTtsBackup() async {
    if (kDebugMode) {
      print('🎙️ TTS: Using text-to-speech fallback');
    }

    try {
      String textToSpeak =
          "I'm sorry, I couldn't play the audio right now."; // Default error

      try {
        final prefs = await SharedPreferences.getInstance();
        final savedText = prefs.getString('last_tts_text');
        if (savedText != null && savedText.isNotEmpty) {
          textToSpeak = savedText;
        }
      } catch (e) {
        if (kDebugMode) {
          print('🎙️ TTS: Error retrieving saved text for TTS: $e');
        }
      }

      if (kDebugMode) {
        print('🎙️ TTS: Preparing to speak: "$textToSpeak"');
      }

      // Use system TTS instead of audio player for text
      // This is a simple fallback - the actual TTS implementation should be replaced
      // with proper system TTS calls
      if (kDebugMode) {
        print('🎙️ TTS fallback would speak: $textToSpeak');
      }

      if (kDebugMode) {
        print('🎙️ TTS: speak() called');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎙️ TTS: Error in _useTtsBackup: $e');
      }
    }
  }

  // Play audio with progressive streaming (starts playing while still downloading)
  Future<void> playStreamingAudio(String audioUrl) async {
    try {
      if (kDebugMode) {
        print('Playing streaming audio from URL: $audioUrl');
      }

      if (_isWeb) {
        if (kDebugMode) {
          print(
              'Web platform does not support streaming audio, using fallback');
        }
        await playAudio(audioUrl);
        return;
      }

      // Check if the URL exists before attempting to stream
      try {
        final response = await http.head(Uri.parse(audioUrl));
        if (response.statusCode != 200) {
          if (kDebugMode) {
            print('Audio URL not accessible: $audioUrl, using TTS fallback');
          }
          await _useTtsBackup();
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error checking audio URL: $e, falling back to TTS');
        }
        await _useTtsBackup();
        return;
      }

      // Create a player instance for streaming
      final player = AudioPlayer();

      try {
        // Set the audio source with low buffer size for quicker start
        await player.setAudioSource(
          ProgressiveAudioSource(
            Uri.parse(audioUrl),
            // Lower buffer size helps start playback faster
            headers: {
              'Range': 'bytes=0-'
            }, // Request range to enable progressive playback
          ),
          preload: false, // Don't preload the entire audio file
        );

        // Start playing as soon as enough is buffered
        final playbackStartTime = DateTime.now();
        await player.play();

        if (kDebugMode) {
          print(
              'Streaming audio playback started in ${DateTime.now().difference(playbackStartTime).inMilliseconds}ms');
        }

        // Wait for playback to complete
        await player.processingStateStream.firstWhere(
          (state) => state == ProcessingState.completed,
        );

        if (kDebugMode) {
          print('Streaming audio playback completed');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error streaming audio: $e');
        }
        // Try fallback to regular download and play method
        try {
          await playAudio(audioUrl);
        } catch (fallbackError) {
          if (kDebugMode) {
            print('Fallback playback also failed: $fallbackError, using TTS');
          }
          await _useTtsBackup();
        }
      } finally {
        // Clean up resources
        await player.dispose();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in streaming playback: $e');
      }
      // Last resort fallback
      await _useTtsBackup();
    }
  }

  // New method to check if audio is currently playing
  Future<bool> isPlaying() async {
    try {
      // Create a temporary player to check status
      final player = AudioPlayer();

      // Check if the player is playing
      final isPlaying = player.playing;

      // Dispose the temporary player
      await player.dispose();

      return isPlaying;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking audio playback state: $e');
      }
      return false;
    }
  }

  // Cleanup resources
  void dispose() {
    if (kDebugMode) print('[VoiceService] dispose called');
    _disposed = true;

    // Clean up reusable WebSocket connection
    _cleanupConnection();

    // if (_recordingStateController != null &&
    //     !_recordingStateController!.isClosed) {
    //   _recordingStateController!.close();
    // }

    if (!_audioPlaybackController.isClosed) {
      _audioPlaybackController.close();
    }

    if (!_ttsSpeakingStateController.isClosed) {
      _ttsSpeakingStateController.close();
    }

    // AudioPlayerManager is disposed separately by its own dispose method

    // if (_recordingStateController != null && !_recordingStateController!.isClosed) {
    //   _recordingStateController!.close();
    // }

    _recordingManager.dispose();

    // Clean up any temporary files (only on non-web platforms)
    if (!_isWeb &&
        _lastGeneratedAudioPath != null &&
        !_lastGeneratedAudioPath!.startsWith('http')) {
      try {
        final file = io.File(_lastGeneratedAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error cleaning up audio file: $e');
        }
      }
    }
  }

  // Method to dispose the voice service
  // void emitRecordingState(RecordingState state) {
  //   if (_recordingStateController != null && !_recordingStateController!.isClosed) {
  //     _recordingStateController!.add(state);
  //   }
  // }

  // Method to get the AudioPlayerManager instance
  AudioPlayerManager getAudioPlayerManager() {
    return _audioPlayerManager;
  }

  // Method to get the RecordingManager instance
  RecordingManager getRecordingManager() {
    return _recordingManager;
  }

  // ADDED: Method to play an existing audio file and trigger onDone/onError callbacks
  Future<void> playAudioWithCallbacks(
    String filePath, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    _setAiSpeaking(true);
    if (kDebugMode)
      print('[VoiceService] playAudioWithCallbacks: Playing $filePath');
    try {
      // Ensure the AudioPlayerManager's playAudio method is awaited
      // and it signals completion appropriately for onDone/onError.
      // (This was established in prior refactoring of AudioPlayerManager.playAudio)
      await _audioPlayerManager.playAudio(filePath);
      onDone?.call();
    } catch (e) {
      if (kDebugMode) print('❌ ERROR playing audio with callbacks: $e');
      onError?.call('Error playing audio: ${e.toString()}');
    } finally {
      _setAiSpeaking(false);
    }
  }

  void _setAiSpeaking(bool speaking) {
    isAiSpeaking = speaking;
    _ttsSpeakingStateController.add(speaking);
    if (kDebugMode) {
      print(
          '[VoiceService] _setAiSpeaking: isAiSpeaking set to $speaking, stream updated.');
    }
  }

  /// Centralized callback for when TTS playback is done successfully
  void _onPlaybackDone() {
    isAiSpeaking = false;      // single source of truth
    _ttsSpeakingStateController.add(false);
    if (kDebugMode) {
      print('[VoiceService] _onPlaybackDone: isAiSpeaking set to false, TTS state cleared');
    }
  }

  // Public method to reset TTS state
  void resetTTSState() {
    if (kDebugMode) {
      print('[VoiceService] resetTTSState: Resetting TTS state to false');
    }
    _setAiSpeaking(false);
  }

  /// Mute or unmute the speaker (local device only, does not affect streams)
  Future<void> setSpeakerMuted(bool muted) async {
    final volume = muted ? 0.0 : 1.0;
    await _audioPlayerManager.setVolume(volume);
    if (kDebugMode) {
      print('[VoiceService] setSpeakerMuted: muted=$muted (volume=$volume)');
    }
  }
}
