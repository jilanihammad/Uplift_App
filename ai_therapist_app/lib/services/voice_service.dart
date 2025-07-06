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
import 'auto_listening_coordinator.dart';
import 'vad_manager.dart';
import 'audio_player_manager.dart';
import 'recording_manager.dart';
import 'audio_recording_service.dart';
import 'base_voice_service.dart' as base_voice;
import 'path_manager.dart';
import '../di/interfaces/i_audio_settings.dart';

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

  // WebSocket functionality removed - now handled by WebSocketAudioManager
  
  // Mutex to prevent concurrent TTS operations
  final Mutex _ttsLock = Mutex();
  
  // NEW: Debounce mechanism to prevent duplicate playback calls
  String? _lastPlayedFile;
  Timer? _playbackDebounceTimer;
  
  // Stream controllers for voice recording states - REMOVED
  // StreamController<RecordingState>? _recordingStateController;
  // Stream<RecordingState>? _recordingStateStream;
  // Stream<RecordingState> get recordingState {
  //   _ensureStreamControllerIsActive();
  //   return _recordingStateStream!;
  // }
  // Phase 2.1.1: Expose AudioRecordingService's stream (delegates to RecordingManager)
  Stream<base_voice.RecordingState> get recordingState =>
      _audioRecordingService.recordingStateStream;

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
  
  // Audio settings for global mute functionality
  final IAudioSettings? _audioSettings;

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

  // RACE CONDITION FIX: Track current TTS state to prevent duplicate calls
  bool _currentTtsState = false;

  // Add coordinator and VAD manager
  late final VADManager _vadManager;
  late final AutoListeningCoordinator _autoListeningCoordinator;
  late final AudioPlayerManager _audioPlayerManager;
  late final RecordingManager _recordingManager;
  late final AudioRecordingService _audioRecordingService;

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
  factory VoiceService({
    required ApiClient apiClient,
    IAudioSettings? audioSettings,
  }) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        print('Reusing existing VoiceService instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = VoiceService._internal(
      apiClient: apiClient, 
      audioSettings: audioSettings,
    );
    return _instance!;
  }

  // Private constructor for singleton pattern
  VoiceService._internal({
    required ApiClient apiClient,
    IAudioSettings? audioSettings,
  }) : _apiClient = apiClient,
        _audioSettings = audioSettings {
    // _audioRecorder = AudioRecorder(); // REMOVED
    // _ensureStreamControllerIsActive(); // REMOVED, no local controller
    _audioPlayerManager = AudioPlayerManager(audioSettings: audioSettings);
    _recordingManager = RecordingManager(); // Already initialized here
    _audioRecordingService = AudioRecordingService(recordingManager: _recordingManager); // Phase 2.1.1: Inject shared RecordingManager
    _vadManager = VADManager();
    _autoListeningCoordinator = AutoListeningCoordinator(
      audioPlayerManager: _audioPlayerManager,
      recordingManager: _recordingManager,
      voiceService: this,
    );
    if (kDebugMode) {
      print('VoiceService initialized with constructor injection');
      print('[VoiceService] AudioRecordingService added with shared RecordingManager - Phase 2.1.1 Hotfix');
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

      // Phase 2.1.1: Initialize AudioRecordingService
      if (kDebugMode) {
        print('[VoiceService] Initializing AudioRecordingService...');
      }
      await _audioRecordingService.initialize();
      if (kDebugMode) {
        print('[VoiceService] AudioRecordingService initialized successfully');
      }

      // _currentState = RecordingState.ready; // REMOVED
      // _recordingStateController!.add(_currentState); // REMOVED

      _isInitialized = true;

      // WebSocket pre-warming removed - handled by TTSService

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
    // Phase 2.1.1: Delegate to AudioRecordingService instead of RecordingManager directly
    if (kDebugMode) {
      print(
          '⏺️ VOICE DEBUG: VoiceService.startRecording called - delegating to AudioRecordingService');
    }

    if (_isWeb) {
      // Simulate recording in web mode - AudioRecordingService handles web compatibility
      if (kDebugMode) {
        print(
            'Recording started (web mode) - AudioRecordingService handles web compatibility');
      }
      // AudioRecordingService will handle web mode appropriately
    }

    // Phase 2.1.1: Delegate to AudioRecordingService
    await _audioRecordingService.startRecording();

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
        // Phase 2.1.1: Delegate to AudioRecordingService
        recordedFilePath = await _audioRecordingService.stopRecording();
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
        // RACE CONDITION FIX: Mark transcription complete even on file processing error
        _recordingManager.markTranscriptionComplete(recordedFilePath);
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
        // Use custom timeout for transcription (longer than default 15s)
        final response = await _transcribeWithCustomTimeout({
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
        // RACE CONDITION FIX: Mark transcription complete before file cleanup
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        
        // Successfully transcribed, now delete the file
        await FileCleanupManager.safeDelete(recordedFilePath);
        return transcription.isNotEmpty ? transcription : "";
      } catch (e) {
        if (kDebugMode) {
          print(
              '❌ VOICE ERROR: processRecordedAudioFile: Error calling transcription API: $e');
        }
        // RACE CONDITION FIX: Mark transcription complete even on error to prevent path reuse
        _recordingManager.markTranscriptionComplete(recordedFilePath);
        await FileCleanupManager.safeDelete(recordedFilePath);
        return "Error: Unable to transcribe audio. Please try again.";
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '❌ VOICE ERROR: processRecordedAudioFile: Error processing audio file: $e');
      }
      try {
        // RACE CONDITION FIX: Mark transcription complete even on processing error
        _recordingManager.markTranscriptionComplete(recordedFilePath);
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

  /// Custom transcription method with extended timeout for large audio files
  Future<dynamic> _transcribeWithCustomTimeout(Map<String, dynamic> body) async {
    try {
      // Use a longer timeout for transcription (45 seconds instead of 15)
      const transcriptionTimeout = Duration(seconds: 45);
      
      if (kDebugMode) {
        print('⏹️ VOICE DEBUG: Using extended timeout (45s) for transcription');
      }
      
      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      // Build headers
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      // Make direct HTTP call with extended timeout
      final response = await http.post(
        Uri.parse('$_backendUrl/voice/transcribe'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(transcriptionTimeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Transcription API returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ VOICE ERROR: _transcribeWithCustomTimeout failed: $e');
      }
      rethrow;
    }
  }

  // WebSocket TTS methods removed - now handled by TTSService

  // TTS methods removed - now handled by TTSService to eliminate duplicate calls

  // Helper TTS methods removed - handled by TTSService

  // generateAudio method removed - now handled by TTSService to eliminate duplicate calls

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

    // WebSocket cleanup removed - handled by TTSService
    
    // Clean up debounce timer
    _playbackDebounceTimer?.cancel();

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
    
    // Phase 2.1.1: Dispose AudioRecordingService
    _audioRecordingService.dispose();

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

  // CRITICAL FIX: Method to play audio with debounce to prevent duplicate calls
  Future<void> playAudioWithCallbacks(
    String filePath, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    // DEBOUNCE: Prevent duplicate calls for the same file within 100ms
    if (_lastPlayedFile == filePath) {
      if (kDebugMode) {
        print('[VoiceService] playAudioWithCallbacks: DEBOUNCED duplicate call for $filePath');
      }
      // Still trigger callbacks since caller expects them
      onDone?.call();
      return;
    }
    
    // Cancel any pending debounce timer
    _playbackDebounceTimer?.cancel();
    
    _lastPlayedFile = filePath;
    _setAiSpeaking(true);
    if (kDebugMode)
      print('[VoiceService] playAudioWithCallbacks: Playing $filePath');
    
    try {
      // Ensure the AudioPlayerManager's playAudio method is awaited
      // and it signals completion appropriately for onDone/onError.
      await _audioPlayerManager.playAudio(filePath);
      onDone?.call();
    } catch (e) {
      if (kDebugMode) print('❌ ERROR playing audio with callbacks: $e');
      onError?.call('Error playing audio: ${e.toString()}');
    } finally {
      _setAiSpeaking(false);
      
      // Clear the debounce after a short delay
      _playbackDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        _lastPlayedFile = null;
      });
    }
  }

  void _setAiSpeaking(bool speaking) {
    isAiSpeaking = speaking;
    _ttsSpeakingStateController.add(speaking);
    
    // SIMPLIFIED: Only update TTS state - AutoListeningCoordinator handles VAD coordination
    // The single TTS "done" signal approach eliminates competing VAD restart triggers
    if (kDebugMode) {
      print('[VoiceService] _setAiSpeaking: TTS state set to $speaking (VAD coordination handled by AutoListeningCoordinator)');
    }
  }

  /// Centralized callback for when TTS playback is done successfully
  void _onPlaybackDone() {
    isAiSpeaking = false;      // single source of truth
    _ttsSpeakingStateController.add(false);
    if (kDebugMode) {
      print('[VoiceService] _onPlaybackDone: TTS state cleared (AutoListeningCoordinator handles VAD restart)');
    }
  }

  /// Update TTS speaking state for auto-listening coordination
  /// This is the clean interface for external TTS state updates
  void updateTTSSpeakingState(bool isSpeaking) {
    // RACE CONDITION FIX: Prevent duplicate calls with same state
    if (_currentTtsState == isSpeaking) {
      if (kDebugMode) {
        print('[VoiceService] updateTTSSpeakingState: State already $_currentTtsState, ignoring duplicate call');
      }
      return;
    }
    
    _currentTtsState = isSpeaking; // Update tracked state
    _setAiSpeaking(isSpeaking);
    
    // NEW: only toggle listening, never touch autoModeEnabled
    if (!isSpeaking) {
      autoListeningCoordinator.startListening();   // guarantees VAD on
      if (kDebugMode) {
        print('[VoiceService] updateTTSSpeakingState: TTS done, starting listening');
      }
    } else {
      autoListeningCoordinator.stopListening();    // guarantees VAD off
      if (kDebugMode) {
        print('[VoiceService] updateTTSSpeakingState: TTS started, stopping listening');
      }
    }
  }

  /// Legacy VAD pause method - now no-op as echo-loop prevention removed
  Future<void> pauseVAD() async {
    if (kDebugMode) {
      print('[VoiceService] pauseVAD: Legacy method - no action needed with new TTS architecture');
    }
  }

  /// Legacy VAD resume method - now no-op as echo-loop prevention removed
  Future<void> resumeVAD() async {
    if (kDebugMode) {
      print('[VoiceService] resumeVAD: Legacy method - no action needed with new TTS architecture');
    }
  }

  // Public method to reset TTS state
  void resetTTSState() {
    if (kDebugMode) {
      print('[VoiceService] resetTTSState: Resetting TTS state to false (VAD coordination handled by AutoListeningCoordinator)');
    }
    _setAiSpeaking(false);
  }

  /// Mute or unmute the speaker (local device only, does not affect streams)
  Future<void> setSpeakerMuted(bool muted) async {
    // Use AudioSettings if available for global mute
    if (_audioSettings != null) {
      _audioSettings!.setMuted(muted);
      if (kDebugMode) {
        print('[VoiceService] Updated global mute to $muted via AudioSettings');
      }
    } else {
      // Fallback to old behavior for backward compatibility
      final volume = muted ? 0.0 : 1.0;
      await _audioPlayerManager.setVolume(volume);
      if (kDebugMode) {
        print('[VoiceService] setSpeakerMuted: muted=$muted (volume=$volume) - legacy mode');
      }
    }
  }
}
