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
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
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

class VoiceService {
  // Singleton instance
  static VoiceService? _instance;

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

  // Stream controllers for audio playback states
  final StreamController<bool> _audioPlaybackController =
      StreamController<bool>.broadcast();
  Stream<bool> get audioPlaybackStream => _audioPlaybackController.stream;

  // Stream specifically for TTS speaking state - we keep this for API compatibility
  final StreamController<bool> _ttsSpeakingStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get isTtsActuallySpeaking => _ttsSpeakingStateController.stream;

  AudioPlayer? _currentPlayer; // Central reference for current player

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
        await _deleteFile(recordedFilePath);
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
        await _deleteFile(recordedFilePath);
        return transcription.isNotEmpty ? transcription : "";
      } catch (e) {
        if (kDebugMode) {
          print(
              '❌ VOICE ERROR: processRecordedAudioFile: Error calling transcription API: $e');
        }
        await _deleteFile(recordedFilePath);
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
          await _deleteFile(recordedFilePath);
        }
      } catch (delErr) {
        if (kDebugMode)
          print(
              '❌ VOICE ERROR: processRecordedAudioFile: Error deleting file during cleanup: $delErr');
      }
      return "Error: Problem processing audio. Please try again.";
    }
  }

  // Helper method to delete a file if it exists
  Future<void> _deleteFile(String filePath) async {
    try {
      final file = io.File(filePath);
      if (await file.exists()) {
        await file.delete();
        if (kDebugMode) {
          print('🗑️ File deleted: $filePath');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting file $filePath: $e');
      }
    }
  }

  /// Stream TTS audio from backend and play it
  Future<String?> streamAndPlayTTS({
    required String text,
    String voice = 'sage',
    String responseFormat = 'opus',
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    isAiSpeaking = true;
    if (kDebugMode)
      print('[VoiceService] [TTS] isAiSpeaking set to true (streamAndPlayTTS)');
    _ttsSpeakingStateController.add(true);
    if (kDebugMode) print('[VoiceService] [TTS] TTS state stream set to true');
    String? filePath;
    io.File? tempFile; // Keep a reference to the file

    try {
      final wsUrl =
          'wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts';
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      final List<int> audioBuffer = [];
      StreamSubscription? subscription;

      final request = jsonEncode({
        'text': text,
        'voice': voice,
        'params': {'response_format': responseFormat},
      });

      final completer = Completer<String?>();

      subscription = channel.stream.listen((event) async {
        try {
          final data = jsonDecode(event);
          if (data['type'] == 'audio_chunk') {
            final chunk = base64Decode(data['data']);
            audioBuffer.addAll(chunk);
            // Optionally, call onProgress
          } else if (data['type'] == 'done') {
            // Write buffer to temp file
            try {
              final tempDir = await getTemporaryDirectory();
              final ext = responseFormat == 'opus' ? 'ogg' : 'mp3';
              filePath =
                  '${tempDir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.$ext';
              tempFile = io.File(filePath!);
              await tempFile!.writeAsBytes(audioBuffer);

              if (kDebugMode) {
                final fileSize = await tempFile!.length();
                print('TTS audio written to $filePath (size: $fileSize bytes)');
              }

              // Use AudioPlayerManager to play the audio and await its completion
              await _audioPlayerManager.playAudio(filePath!);
              // Playback is complete here

              onDone?.call();
              if (kDebugMode)
                print(
                    '[VoiceService] [TTS] TTS stream done, audio played by manager');

              // Clean up temp file AFTER playback is fully complete
              // The explicit await _audioPlayerManager.playAudio() handles completion.
              // No need for player.playerStateStream.listen here for deletion.

              completer.complete(filePath);
            } catch (e) {
              onError?.call('Playback error: $e');
              completer.complete(null);
            }
            await subscription?.cancel();
            await channel.sink.close();
          } else if (data['type'] == 'error') {
            if (kDebugMode)
              print(
                  '[VoiceService] [TTS] TTS stream error: ${data['detail'] ?? 'Unknown error'}');
            onError?.call(data['detail'] ?? 'Unknown error');
            completer.complete(null);
            await subscription?.cancel();
            await channel.sink.close();
          }
        } catch (e) {
          if (kDebugMode)
            print('[VoiceService] [TTS] Failed to process TTS stream: $e');
          onError?.call('Failed to process TTS stream: $e');
          completer.complete(null);
          await subscription?.cancel();
          await channel.sink.close();
        }
      }, onError: (err) async {
        if (kDebugMode) print('[VoiceService] [TTS] WebSocket error: $err');
        onError?.call('WebSocket error: $err');
        completer.complete(null);
        await subscription?.cancel();
        await channel.sink.close();
      }, onDone: () async {
        if (kDebugMode) print('[VoiceService] [TTS] WebSocket stream closed');
        await subscription?.cancel();
        await channel.sink.close();
      });

      // Send the TTS request
      channel.sink.add(request);
      return await completer.future;
    } finally {
      isAiSpeaking = false;
      if (kDebugMode)
        print(
            '[VoiceService] [TTS] isAiSpeaking set to false (streamAndPlayTTS)');
      _ttsSpeakingStateController.add(false);
      if (kDebugMode)
        print('[VoiceService] [TTS] TTS state stream set to false');

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

  // Refactor generateAudio to use WebSocket streaming with automatic mp3 fallback
  Future<String?> generateAudio(
    String text, {
    String voice = 'sage',
    String responseFormat = 'opus',
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    _setAiSpeaking(true);
    if (kDebugMode) {
      print(
          '[VoiceService] [TTS] TTS state stream set to true (generateAudio)');
    }

    String? finalFilePath;
    bool primarySucceeded = false;
    bool anErrorOccurred = false;

    try {
      // Attempt primary format (e.g., opus)
      if (kDebugMode)
        print(
            '[VoiceService] generateAudio: Attempting primary TTS format: $responseFormat');
      finalFilePath = await streamAndPlayTTS(
        text: text,
        voice: voice,
        responseFormat: responseFormat,
        onDone: () {
          if (kDebugMode)
            print(
                '[VoiceService] generateAudio: Primary TTS ($responseFormat) succeeded and played.');
          primarySucceeded = true;
          // Don't call the main onDone here yet, wait for the whole method to finish.
        },
        onError: (err) async {
          if (kDebugMode) {
            print(
                '[VoiceService] generateAudio: Primary TTS streaming error ($responseFormat): $err');
          }
          // If primary was opus and it failed, try mp3 as a fallback
          if (responseFormat == 'opus') {
            if (kDebugMode) {
              print(
                  '[VoiceService] generateAudio: Retrying TTS streaming with mp3 fallback...');
            }
            try {
              finalFilePath = await streamAndPlayTTS(
                text: text,
                voice: voice,
                responseFormat: 'mp3', // Fallback to mp3
                onDone: () {
                  if (kDebugMode)
                    print(
                        '[VoiceService] generateAudio: MP3 fallback TTS succeeded and played.');
                  primarySucceeded = true; // Mark success if fallback worked
                  // Don't call the main onDone here.
                },
                onError: (fallbackErr) {
                  if (kDebugMode)
                    print(
                        '[VoiceService] generateAudio: MP3 fallback TTS also failed: $fallbackErr');
                  anErrorOccurred = true;
                  // Don't call main onError here yet.
                },
              );
            } catch (fallbackException) {
              if (kDebugMode)
                print(
                    '[VoiceService] generateAudio: MP3 fallback TTS threw exception: $fallbackException');
              anErrorOccurred = true;
              // Don't call main onError here yet.
            }
          } else {
            // If it wasn't opus, or no fallback defined
            anErrorOccurred = true;
          }
        },
      );

      // After all attempts, decide whether to call main onDone or onError
      if (primarySucceeded && !anErrorOccurred) {
        onDone?.call();
        return finalFilePath;
      } else {
        // If an error occurred in any path (primary non-opus fail, or fallback fail)
        // and we haven't already returned a successful path from primary.
        // The original onError (from streamAndPlayTTS) should have been specific.
        // Let's use a generic error if finalFilePath is null and an error occurred.
        String errorMessage = 'TTS generation failed after all attempts.';
        if (finalFilePath == null && anErrorOccurred) {
          // If error occurred and no path was set
          onError?.call(errorMessage);
        } else if (finalFilePath != null && anErrorOccurred) {
          // This case should ideally not happen if logic is correct (e.g. primary succeeded but error flag also set)
          // but if it does, success takes precedence if a path is available.
          onDone?.call();
          return finalFilePath;
        } else if (finalFilePath == null &&
            !primarySucceeded &&
            !anErrorOccurred) {
          // No success, no explicit error from inner calls, but no path.
          onError?.call("TTS failed to produce an audio file.");
        } else {
          // If primarySucceeded is true, we should have called onDone.
          // If we reached here and primarySucceeded is true, something is amiss or it's already handled.
          // This path implies finalFilePath might be null but primarySucceeded is false.
          onError?.call(errorMessage);
        }
        return null; // Indicate failure if we fall through here
      }
    } catch (e) {
      // This catch is for direct exceptions from the initial primary streamAndPlayTTS call,
      // or any other synchronous error in this block.
      if (kDebugMode) {
        print('[VoiceService] generateAudio caught direct exception: $e');
      }
      onError?.call('TTS generation error: ${e.toString()}');
      return null; // Indicate failure
    } finally {
      _setAiSpeaking(false); // Use the new helper
      if (kDebugMode) {
        print(
            '[VoiceService] [TTS] TTS state stream set to false (generateAudio final)');
      }
    }
  }

  // Play an audio file
  Future<void> playAudio(String audioPath) async {
    _audioPlaybackController.add(true);

    try {
      if (kDebugMode) {
        print('🔊 VoiceService: Beginning audio playback of $audioPath');
      }

      // Dispose previous player if exists
      await _currentPlayer?.dispose();
      _currentPlayer = null;

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
          _currentPlayer = AudioPlayer();
          try {
            await _currentPlayer!.setUrl(audioPath);
            _currentPlayer!.playerStateStream.listen((state) async {
              if (state.processingState == ProcessingState.completed) {
                _audioPlaybackController.add(false);
                await _currentPlayer?.dispose();
                _currentPlayer = null;
              }
            });
            await _currentPlayer!.play();
          } catch (e) {
            if (kDebugMode) print('🔊 VoiceService: Error playing URL: $e');
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS if URL play fails
            await _currentPlayer?.dispose();
            _currentPlayer = null;
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
          _currentPlayer = AudioPlayer();
          try {
            await _currentPlayer!.setFilePath(audioPath);
            _currentPlayer!.playerStateStream.listen((state) async {
              if (state.processingState == ProcessingState.completed) {
                _audioPlaybackController.add(false);
                await _currentPlayer?.dispose();
                _currentPlayer = null;
              }
            });
            await _currentPlayer!.play();
          } catch (e) {
            if (kDebugMode)
              print('🔊 VoiceService: Error playing local file: $e');
            _audioPlaybackController.add(false);
            await _useTtsBackup(); // Fallback to TTS
            await _currentPlayer?.dispose();
            _currentPlayer = null;
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
      await _currentPlayer?.dispose();
      _currentPlayer = null;
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

      // Stop and dispose current player
      if (_currentPlayer != null) {
        await _currentPlayer!.stop();
        await _currentPlayer!.dispose();
        _currentPlayer = null;
      }

      // ALSO stop the AudioPlayerManager and force its state
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

      // Get temporary directory for caching
      final tempDir = await getTemporaryDirectory();
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = '${tempDir.path}/$fileName';

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
      // Make sure TTS is initialized
      if (_currentPlayer == null) {
        _currentPlayer = AudioPlayer();
      }

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

      // Speak the text
      await _currentPlayer!.setAudioSource(
        ProgressiveAudioSource(
          Uri.parse(textToSpeak),
          // Lower buffer size helps start playback faster
          headers: {
            'Range': 'bytes=0-'
          }, // Request range to enable progressive playback
        ),
        preload: false, // Don't preload the entire audio file
      );

      await _currentPlayer!.play();

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

    // Dispose current player
    if (_currentPlayer != null) {
      _currentPlayer!.dispose();
      _currentPlayer = null;
    }

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
