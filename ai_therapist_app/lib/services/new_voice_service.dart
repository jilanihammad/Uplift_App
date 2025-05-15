import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'audio_player_manager.dart';
import 'auto_listening_coordinator.dart';
import 'base_voice_service.dart';
import 'recording_manager.dart';
import 'resource_cleaner.dart';
import 'transcription_service.dart';
import 'tts_manager.dart';
import 'vad_manager.dart';

/// Voice service implementation that coordinates all audio components
///
/// This is a facade that coordinates the various managers and provides
/// a simpler interface for the rest of the application to use
class VoiceService implements BaseVoiceService {
  // API base URL for backend services
  final String _apiBaseUrl;

  // Component managers
  late final RecordingManager _recordingManager;
  late final TranscriptionService _transcriptionService;
  late final TTSManager _ttsManager;
  late final VADManager _vadManager;
  late final AudioPlayerManager _audioPlayerManager;
  late final ResourceCleaner _resourceCleaner;
  late final AutoListeningCoordinator _autoListeningCoordinator;

  // Stream controllers
  final _recordingStateController =
      StreamController<RecordingState>.broadcast();
  final _playingStateController = StreamController<bool>.broadcast();
  final _ttsStateController = StreamController<bool>.broadcast();
  final _autoListeningStateController =
      StreamController<AutoListeningState>.broadcast();
  final _errorController = StreamController<String?>.broadcast();

  // Stream implementation from base interface
  @override
  Stream<RecordingState> get recordingState => _recordingStateController.stream;

  @override
  Stream<RecordingState> get recordingStateStream =>
      _recordingStateController.stream;

  @override
  Stream<bool> get audioPlaybackStream => _playingStateController.stream;

  @override
  Stream<bool> get isPlayingStream => _playingStateController.stream;

  @override
  Stream<String?> get errorStream => _errorController.stream;

  // Auto mode state
  @override
  bool get isAutoModeEnabled => _autoListeningCoordinator.autoModeEnabled;

  // Stream for listening to the auto coordinator's state
  Stream<AutoListeningState> get autoListeningStateStream =>
      _autoListeningStateController.stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Constructor
  VoiceService({required String apiBaseUrl}) : _apiBaseUrl = apiBaseUrl {
    _initializeComponents();
  }

  // Initialize all component managers
  void _initializeComponents() {
    // Create component instances
    _recordingManager = RecordingManager();
    _transcriptionService = TranscriptionService(apiUrl: _apiBaseUrl);
    _ttsManager = TTSManager(apiUrl: _apiBaseUrl);
    _vadManager = VADManager();
    _audioPlayerManager = AudioPlayerManager();
    _resourceCleaner = ResourceCleaner();

    // Create the coordinator last since it depends on other components
    _autoListeningCoordinator = AutoListeningCoordinator(
      audioPlayerManager: _audioPlayerManager,
      recordingManager: _recordingManager,
      ttsManager: _ttsManager,
      vadManager: _vadManager,
    );

    // Set up the callbacks
    _setupListeners();
    _setupAutoListeningCallbacks();
  }

  // Set up listeners for internal component events
  void _setupListeners() {
    // Forward recording state events
    _recordingManager.recordingStateStream.listen((state) {
      _recordingStateController.add(state);
    });

    // Forward playback state events
    _audioPlayerManager.isPlayingStream.listen((isPlaying) {
      _playingStateController.add(isPlaying);

      // When audio playback stops, notify the TTS system too
      // This ensures TTS state correctly reflects when playback ends
      if (!isPlaying) {
        // Add a slight delay to ensure all processing is complete
        Future.delayed(const Duration(milliseconds: 100), () {
          // Notify that TTS is done speaking
          if (kDebugMode) {
            print(
                '🔄 Voice service: Audio playback ended, notifying TTS system');
          }
          _ttsManager.notifyTtsPlaying(false);

          // If auto mode is enabled, explicitly trigger listening
          if (isAutoModeEnabled) {
            if (kDebugMode) {
              print(
                  '🔄 Voice service: Auto mode enabled, explicitly triggering listening');
            }
            _autoListeningCoordinator.triggerListening();
          }
        });
      }
    });

    // Process processing state changes to detect when playback truly ends
    _audioPlayerManager.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (kDebugMode) {
          print('🔄 Voice service: Audio processing completed');
        }

        // When playback truly completes, make sure TTS state is updated
        _ttsManager.notifyTtsPlaying(false);

        // If auto mode is enabled, explicitly trigger listening
        if (isAutoModeEnabled) {
          if (kDebugMode) {
            print(
                '🔄 Voice service: Processing completed, explicitly triggering listening');
          }
          _autoListeningCoordinator.triggerListening();
        }
      }
    });

    // Forward TTS state changes
    _ttsManager.ttsStateStream.listen((isSpeaking) {
      _ttsStateController.add(isSpeaking);
    });

    // Forward errors
    _recordingManager.errorStream.listen((error) {
      if (error != null) _errorController.add('Recording: $error');
    });
    _audioPlayerManager.errorStream.listen((error) {
      if (error != null) _errorController.add('Audio Player: $error');
    });
    _transcriptionService.errorStream.listen((error) {
      if (error != null) _errorController.add('Transcription: $error');
    });
    _ttsManager.errorStream.listen((error) {
      if (error != null) _errorController.add('TTS: $error');
    });
    _autoListeningCoordinator.errorStream.listen((error) {
      if (error != null) _errorController.add('Auto Listening: $error');
    });

    // The VADManager error stream is handled differently
    _vadManager.onError.listen((error) {
      _errorController.add('VAD: $error');
    });

    _resourceCleaner.errorStream.listen((error) {
      if (error != null) _errorController.add('Resource Cleaner: $error');
    });
  }

  // Set up callbacks for the auto listening coordinator
  void _setupAutoListeningCallbacks() {
    // When speech is detected in auto mode
    _autoListeningCoordinator.onSpeechDetectedCallback = () {
      if (kDebugMode) {
        print('🤖 Auto mode: Speech detected, recording started');
      }
    };

    // When recording is completed in auto mode
    _autoListeningCoordinator.onRecordingCompleteCallback = (audioPath) async {
      if (kDebugMode) {
        print('🤖 Auto mode: Recording completed, transcribing');
      }

      // Automatically process the recording
      final transcription = await transcribeAudio(audioPath);

      if (kDebugMode && transcription.isNotEmpty) {
        print('🤖 Auto mode: Transcription: $transcription');
      }
    };
  }

  @override
  Future<void> initialize() async {
    try {
      await _recordingManager.initialize();
      await _vadManager.initialize();
      await _autoListeningCoordinator.initialize();

      // Run a cleanup of old temp files on startup
      await _resourceCleaner.cleanupTempFiles();

      // Set up listeners for auto listening state forwarding
      _autoListeningCoordinator.stateStream.listen((state) {
        _autoListeningStateController.add(state);
      });

      // Enable auto listening mode by default
      await enableAutoMode();

      // Set up all other event listeners
      _setupListeners();

      _isInitialized = true;

      if (kDebugMode) {
        print('🎤 Voice service initialized with auto-listening enabled');
      }
    } catch (e) {
      _errorController.add('Error initializing voice service: $e');
      if (kDebugMode) {
        print('❌ Voice service initialization error: $e');
      }
      _isInitialized = false;
    }
  }

  @override
  Future<void> startRecording() async {
    try {
      // If in auto mode, disable it temporarily
      if (isAutoModeEnabled) {
        await disableAutoMode();
      }

      await _recordingManager.startRecording();
    } catch (e) {
      _errorController.add('Error starting recording: $e');
      rethrow;
    }
  }

  @override
  Future<String> stopRecording() async {
    try {
      final filePath = await _recordingManager.stopRecording();
      return filePath;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      rethrow;
    }
  }

  @override
  Future<String> transcribeAudio(String audioFilePath) async {
    try {
      return await _transcriptionService.transcribeAudio(audioFilePath);
    } catch (e) {
      _errorController.add('Error transcribing audio: $e');
      rethrow;
    }
  }

  @override
  Future<String> generateAudio(String text) async {
    try {
      return await _ttsManager.generateAudio(text);
    } catch (e) {
      _errorController.add('Error generating audio: $e');
      rethrow;
    }
  }

  @override
  Future<void> playAudio(String audioPath) async {
    try {
      // Notify TTS system that audio is playing (this is Maya speaking)
      // Set this BEFORE starting playback to ensure proper state
      _ttsManager.notifyTtsPlaying(true);

      // If in auto mode, pause listening while playing audio
      if (isAutoModeEnabled) {
        // The coordinator will handle restarting listening when playback ends
        if (kDebugMode) {
          print('🎤 Auto mode: Starting audio playback, pausing listening');
        }
      }

      await _audioPlayerManager.playAudio(audioPath);
    } catch (e) {
      // Make sure to reset TTS state if playback fails
      _ttsManager.notifyTtsPlaying(false);
      _errorController.add('Error playing audio: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopAudio() async {
    try {
      await _audioPlayerManager.stopAudio();
      // Notify TTS system that audio stopped playing
      _ttsManager.notifyTtsPlaying(false);
    } catch (e) {
      _errorController.add('Error stopping audio: $e');
      rethrow;
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      final audioPath = await generateAudio(text);
      if (audioPath.isNotEmpty) {
        await playAudio(audioPath);
      } else {
        // Fallback to local TTS if API-based TTS fails
        await speakWithTts(text);
      }
    } catch (e) {
      _errorController.add('Error speaking text: $e');
      // Fallback to local TTS
      await speakWithTts(text);
    }
  }

  @override
  Future<void> speakWithTts(String text) async {
    try {
      await _ttsManager.speakWithTts(text);
    } catch (e) {
      _errorController.add('Error speaking with TTS: $e');
      rethrow;
    }
  }

  @override
  Future<void> enableAutoMode() async {
    if (!_autoListeningCoordinator.autoModeEnabled) {
      try {
        await Future.microtask(
            () => _autoListeningCoordinator.enableAutoMode());
      } catch (e) {
        _errorController.add('Error enabling auto mode: $e');
        rethrow;
      }
    }
  }

  @override
  Future<void> disableAutoMode() async {
    await _autoListeningCoordinator.disableAutoMode();
  }

  // Clean up temporary files
  Future<int> cleanupTempFiles() async {
    return await _resourceCleaner.cleanupTempFiles();
  }

  @override
  Future<void> dispose() async {
    // Dispose all components
    await _recordingManager.dispose();
    await _transcriptionService.dispose();
    await _ttsManager.dispose();
    await _vadManager.dispose();
    await _audioPlayerManager.dispose();
    await _resourceCleaner.dispose();
    await _autoListeningCoordinator.dispose();

    // Close stream controllers
    await _recordingStateController.close();
    await _playingStateController.close();
    await _ttsStateController.close();
    await _autoListeningStateController.close();
    await _errorController.close();
  }
}
