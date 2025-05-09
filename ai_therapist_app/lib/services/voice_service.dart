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
import 'package:flutter_tts/flutter_tts.dart';
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

// Recording states
enum RecordingState { ready, recording, stopped, paused, error }

// Transcription models
enum TranscriptionModel { gpt4oMini, deepgramAI, assembly }

class VoiceService {
  // Singleton instance
  static VoiceService? _instance;

  // Stream controllers for voice recording states
  StreamController<RecordingState>? _recordingStateController;
  Stream<RecordingState>? _recordingStateStream;
  Stream<RecordingState> get recordingState {
    _ensureStreamControllerIsActive();
    return _recordingStateStream!;
  }

  // Current state of recording
  RecordingState _currentState = RecordingState.ready;

  // Path to the CSM directory
  String? _csmPath;

  // Speaker IDs
  final int _userSpeakerId = 0; // Speaker A
  final int _aiSpeakerId = 1; // Speaker B

  // Audio context for the conversation
  List<Map<String, dynamic>> _conversationContext = [];

  // Generated audio path
  String? _lastGeneratedAudioPath;

  // Recording related
  late final AudioRecorder _audioRecorder;
  String? _recordingPath;

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

  // TTS instance to reuse
  FlutterTts? _flutterTts;

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
    _audioRecorder = AudioRecorder();
    _ensureStreamControllerIsActive();
    _initTts();
    if (kDebugMode) {
      print('VoiceService initialized with constructor injection');
    }
  }

  // Initialize TTS engine
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts!.setLanguage("en-US");
    await _flutterTts!.setPitch(1.0);
    await _flutterTts!.setSpeechRate(0.5);

    if (kDebugMode) {
      print('🎙️ TTS: TTS engine initialized');
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

  // Ensure the StreamController is active and not closed
  void _ensureStreamControllerIsActive() {
    if (_recordingStateController == null ||
        _recordingStateController!.isClosed) {
      _recordingStateController = StreamController<RecordingState>.broadcast();
      _recordingStateStream = _recordingStateController!.stream;
      if (kDebugMode) {
        print('Created new recording state StreamController');
      }
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
      // Make sure the stream controller is active
      _ensureStreamControllerIsActive();

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
        _currentState = RecordingState.ready;
        _recordingStateController!.add(_currentState);
        _isInitialized = true;
        return;
      }

      // Request microphone permissions for recording (non-web platforms)
      if (!_isWeb) {
        var status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          throw Exception("Microphone permission not granted");
        }
      }

      // Reset the conversation context
      _conversationContext = [];

      _currentState = RecordingState.ready;
      _recordingStateController!.add(_currentState);

      _isInitialized = true;

      if (kDebugMode) {
        print('Voice service initialized successfully');
      }
    } catch (e) {
      _currentState = RecordingState.error;
      try {
        if (_recordingStateController != null &&
            !_recordingStateController!.isClosed) {
          _recordingStateController!.add(_currentState);
        }
      } catch (streamError) {
        if (kDebugMode) {
          print('Error sending state to stream: $streamError');
        }
      }

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
    try {
      // Ensure stream controller is active
      _ensureStreamControllerIsActive();

      if (kDebugMode) {
        print('⏺️ VOICE DEBUG: startRecording called');
      }

      if (_isWeb) {
        // Simulate recording in web mode
        _currentState = RecordingState.recording;
        _recordingStateController!.add(_currentState);

        if (kDebugMode) {
          print('Recording started (web mode simulation)');
        }
        return;
      }

      // Check that microphone permission is granted
      final status = await Permission.microphone.request();
      if (kDebugMode) {
        print('⏺️ VOICE DEBUG: Microphone permission status: $status');
      }

      if (status != PermissionStatus.granted) {
        if (kDebugMode) {
          print('❌ VOICE ERROR: Microphone permission denied: $status');
        }
        throw Exception('Microphone permission not granted');
      }

      // Check recorder status before starting
      bool isRecorderInitialized = _audioRecorder != null;
      bool isCurrentlyRecording = false;
      try {
        isCurrentlyRecording = await _audioRecorder.isRecording();
        if (kDebugMode) {
          print(
              '⏺️ VOICE DEBUG: AudioRecorder current state - Initialized: $isRecorderInitialized, Currently recording: $isCurrentlyRecording');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ VOICE ERROR: Failed to check recorder state: $e');
        }
      }

      // Get temp directory to store the recording
      final tempDir = await getTemporaryDirectory();
      _recordingPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (kDebugMode) {
        print('⏺️ VOICE DEBUG: Will save recording to: $_recordingPath');
        print(
            '⏺️ VOICE DEBUG: Temp directory exists: ${await Directory(tempDir.path).exists()}');
      }

      // Check if the recorder has been initialized
      if (!isCurrentlyRecording) {
        try {
          if (kDebugMode) {
            print(
                '⏺️ VOICE DEBUG: Starting recording with config: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100');
          }

          // Start recording
          await _audioRecorder.start(
            RecordConfig(
              encoder: AudioEncoder.aacLc,
              bitRate: 128000,
              sampleRate: 44100,
            ),
            path: _recordingPath ??
                '${(await getTemporaryDirectory()).path}/recording_fallback.m4a',
          );

          if (kDebugMode) {
            print('⏺️ VOICE DEBUG: Recording started successfully');
            print('⏺️ VOICE DEBUG: Verifying recording is in progress...');
          }

          // Verify recording started
          bool recordingStarted = await _audioRecorder.isRecording();
          if (kDebugMode) {
            print('⏺️ VOICE DEBUG: Recording in progress: $recordingStarted');
          }

          if (!recordingStarted) {
            if (kDebugMode) {
              print(
                  '❌ VOICE ERROR: Recorder reported successful start but isRecording() returned false');
            }
            throw Exception('Failed to start recording');
          }

          // Update state
          _currentState = RecordingState.recording;
          _recordingStateController!.add(_currentState);

          if (kDebugMode) {
            print(
                '⏺️ VOICE DEBUG: Recording started with path: $_recordingPath');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ VOICE ERROR: Failed to start recording: $e');
          }
          throw Exception('Failed to start recording: $e');
        }
      } else {
        if (kDebugMode) {
          print(
              '⚠️ VOICE WARNING: Recorder is already recording, cannot start a new recording');
        }
      }
    } catch (e) {
      _currentState = RecordingState.error;
      try {
        if (_recordingStateController != null &&
            !_recordingStateController!.isClosed) {
          _recordingStateController!.add(_currentState);
        }
      } catch (streamError) {
        if (kDebugMode) {
          print('❌ VOICE ERROR: Error sending state to stream: $streamError');
        }
      }

      if (kDebugMode) {
        print('❌ VOICE ERROR: Error starting recording: $e');
      }
      if (!_isWeb) rethrow;
    }
  }

  // Stop recording and get transcription using OpenAI API via backend
  Future<String> stopRecording() async {
    try {
      if (kDebugMode) {
        print('⏹️ VOICE DEBUG: stopRecording called');
      }

      String recordedFilePath = '';

      // Stop recording and get the file path
      if (!_isWeb) {
        bool isRecording = false;
        try {
          isRecording = await _audioRecorder.isRecording();
          if (kDebugMode) {
            print('⏹️ VOICE DEBUG: Is currently recording: $isRecording');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ VOICE ERROR: Error checking recording status: $e');
          }
        }

        if (isRecording) {
          try {
            // Stop recording
            if (kDebugMode) {
              print('⏹️ VOICE DEBUG: Stopping recording...');
            }

            recordedFilePath = await _audioRecorder.stop() ?? '';

            if (kDebugMode) {
              print(
                  '⏹️ VOICE DEBUG: Recording stopped, file saved at: $recordedFilePath');
              if (recordedFilePath.isEmpty) {
                print(
                    '❌ VOICE ERROR: Recording stopped but returned empty file path');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ VOICE ERROR: Error stopping recording: $e');
            }
          }
        } else {
          if (kDebugMode) {
            print(
                '⚠️ VOICE WARNING: stopRecording called but recorder was not recording');
          }
        }
      }

      // Update state
      _currentState = RecordingState.stopped;
      _recordingStateController!.add(_currentState);

      if (kDebugMode) {
        print(
            '⏹️ VOICE DEBUG: Recording stopped (${_isWeb ? 'web mode' : 'native mode'})');
      }

      // If we have a recording, process it
      if (!_isWeb && recordedFilePath.isNotEmpty) {
        try {
          // Read the recorded audio file
          final io.File audioFile = io.File(recordedFilePath);
          bool fileExists = await audioFile.exists();

          if (kDebugMode) {
            print('⏹️ VOICE DEBUG: Audio file exists: $fileExists');
          }

          if (fileExists) {
            final bytes = await audioFile.readAsBytes();

            if (kDebugMode) {
              print('⏹️ VOICE DEBUG: Audio file read successfully');
            }

            if (bytes.isNotEmpty) {
              if (kDebugMode) {
                print('⏹️ VOICE DEBUG: Audio file size: ${bytes.length} bytes');
              }

              // Ensure proper base64 encoding and padding
              String base64Audio = base64Encode(bytes);

              // Make sure base64 string is properly padded
              while (base64Audio.length % 4 != 0) {
                base64Audio += '=';
              }

              if (kDebugMode) {
                print(
                    '⏹️ VOICE DEBUG: Audio file encoded successfully, size: ${base64Audio.length} chars');
                print(
                    '⏹️ VOICE DEBUG: First 50 chars of base64: ${base64Audio.substring(0, min(50, base64Audio.length))}...');
                print(
                    '⏹️ VOICE DEBUG: Last 10 chars of base64: ${base64Audio.substring(max(0, base64Audio.length - 10))}');
                print(
                    '⏹️ VOICE DEBUG: Using API URL: $_backendUrl for transcription');
                print(
                    '⏹️ VOICE DEBUG: Sending request to: $_backendUrl/voice/transcribe');
              }

              try {
                // Make API call with the actual audio data
                final startTime = DateTime.now();

                // VERBOSE LOGGING FOR DEBUGGING
                if (kDebugMode) {
                  print('⏹️ VOICE DEBUG: API URL: $_backendUrl');
                  print('⏹️ VOICE DEBUG: Endpoint: /voice/transcribe');
                  print('⏹️ VOICE DEBUG: Audio format: m4a');
                  print(
                      '⏹️ VOICE DEBUG: Audio data length: ${base64Audio.length}');
                }

                if (kDebugMode) {
                  print(
                      '⏹️ VOICE DEBUG: Making API call to transcribe audio...');
                }

                final response =
                    await _apiClient.post('/voice/transcribe', body: {
                  'audio_data': base64Audio,
                  'audio_format': 'm4a', // Changed back to m4a format
                  'model':
                      'gpt-4o-mini-transcribe' // Update to use the correct model expected by the backend
                });

                final duration =
                    DateTime.now().difference(startTime).inMilliseconds;
                if (kDebugMode) {
                  print(
                      '⏹️ VOICE DEBUG: Transcription API response in ${duration}ms: $response');
                }

                // Check API response format
                if (response != null && response.containsKey('text')) {
                  final transcription = response['text'] as String;
                  if (kDebugMode) {
                    print(
                        '⏹️ VOICE DEBUG: Transcription result: $transcription');
                  }
                  if (transcription.isNotEmpty) {
                    // Check if this is an error message from the backend transcription service
                    if (transcription
                            .toLowerCase()
                            .contains("error transcribing audio") ||
                        transcription
                            .toLowerCase()
                            .contains("error processing") ||
                        transcription
                            .toLowerCase()
                            .contains("couldn't understand") ||
                        transcription
                            .toLowerCase()
                            .contains("please try again")) {
                      if (kDebugMode) {
                        print(
                            '⏹️ VOICE DEBUG: Received error message from transcription service: $transcription');
                      }

                      // Return an empty string to signal UI to focus text input instead of showing error
                      return "";
                    }
                    return transcription;
                  } else {
                    if (kDebugMode) {
                      print('⚠️ VOICE WARNING: Transcription was empty');
                    }
                    return "";
                  }
                } else {
                  if (kDebugMode) {
                    print(
                        '❌ VOICE ERROR: Invalid response format from transcription API: $response');
                  }
                  // Return with error message to show in UI
                  return "Error: Invalid response from transcription service";
                }
              } catch (e) {
                if (kDebugMode) {
                  print('❌ VOICE ERROR: Error calling transcription API: $e');
                }
                // Return with error message to show in UI
                return "Error: Unable to transcribe audio. Please try again.";
              }
            } else {
              if (kDebugMode) {
                print('❌ VOICE ERROR: Audio file is empty.');
              }
              return "Error: Audio recording was empty. Please try again.";
            }
          } else {
            if (kDebugMode) {
              print(
                  '❌ VOICE ERROR: Audio file does not exist at path: $recordedFilePath');
            }
            return "Error: Could not find recorded audio file.";
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ VOICE ERROR: Error processing audio file: $e');
          }
          return "Error: Problem processing audio. Please try again.";
        } finally {
          // Clean up the temporary recording file
          try {
            final file = io.File(recordedFilePath);
            if (await file.exists()) {
              await file.delete();
              if (kDebugMode) {
                print('⏹️ VOICE DEBUG: Deleted temporary recording file');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ VOICE ERROR: Error cleaning up recording file: $e');
            }
          }
        }
      } else if (!_isWeb && recordedFilePath.isEmpty) {
        if (kDebugMode) {
          print('❌ VOICE ERROR: No recording file path returned from recorder');
        }
        return "Error: No audio was recorded. Please try again.";
      }

      // If we reach here, either there was no recording, or transcription failed
      if (kDebugMode) {
        print(
            '⚠️ VOICE WARNING: No valid recording found or transcription failed');
      }
      return "Tap to speak or type your message";
    } catch (e) {
      _currentState = RecordingState.error;
      _recordingStateController!.add(_currentState);
      if (kDebugMode) {
        print('❌ VOICE ERROR: Error in stopRecording: $e');
      }
      // Return error message to show in UI
      return "Error: ${e.toString()}";
    }
  }

  // Generate audio using Groq API via backend
  Future<String> generateAudio(String text, {bool isAiSpeaking = true}) async {
    try {
      if (kDebugMode) {
        print('Generating audio for text: $text');
      }

      // Add this utterance to the conversation context
      _conversationContext.add({
        'text': text,
        'speaker_id': isAiSpeaking ? _aiSpeakerId : _userSpeakerId,
      });

      // We'll only keep the last 10 utterances to avoid context length issues
      if (_conversationContext.length > 10) {
        _conversationContext =
            _conversationContext.sublist(_conversationContext.length - 10);
      }

      // Store the text for TTS fallback right away
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_tts_text', text);
        if (kDebugMode) {
          print('Stored text for TTS fallback: $text');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error storing text for TTS fallback: $e');
        }
        // Continue anyway, we still have the conversation context as backup
      }

      try {
        // Make API call to the backend for text-to-speech using Groq API
        // Include additional debugging for network requests
        if (kDebugMode) {
          print('Using API URL: $_backendUrl');
          print('Sending request to: $_backendUrl/voice/synthesize');
          print(
              'Request body: {"text": "${text.substring(0, min(30, text.length))}...", "voice": "${isAiSpeaking ? 'sage' : 'onyx'}"}');
        }

        final startTime = DateTime.now();
        final response = await _apiClient.post('/voice/synthesize', body: {
          'text': text,
          'voice': isAiSpeaking
              ? 'sage'
              : 'onyx', // Updated to use valid OpenAI TTS voices
          'format': 'ogg_opus', // More efficient than mp3
          'bitrate': '24k', // Lower than default (64k), still good quality
          'mono': true, // Single channel saves ~50% bandwidth
        });

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        if (kDebugMode) {
          print(
              'Response received in ${duration}ms with status code: ${response != null ? "200" : "null"}');
          print('Response content: $response');
        }

        if (response != null) {
          // The backend returns a URL to the generated audio file
          final audioUrl = response['url'];

          if (kDebugMode) {
            print('Raw audio URL from response: $audioUrl');
          }

          if (audioUrl == null || audioUrl.toString().isEmpty) {
            if (kDebugMode) {
              print(
                  'Error: Received null or empty audio URL from backend. Using local TTS.');
            }

            // Fall back to local TTS immediately
            // Generate a fake URL to trigger the fallback mechanism in playAudio
            String localFallbackPath =
                'local_tts://${DateTime.now().millisecondsSinceEpoch}';
            _lastGeneratedAudioPath = localFallbackPath;

            return localFallbackPath;
          }

          // Construct the full URL - ensure we're handling null correctly
          String fullAudioUrl;
          if (audioUrl.startsWith('http')) {
            fullAudioUrl = audioUrl;
          } else if (audioUrl.startsWith('/')) {
            // Use the backend URL from AppConfig instead of hardcoded value
            fullAudioUrl = '${AppConfig().backendUrl}$audioUrl';
          } else {
            // Use the backend URL from AppConfig instead of hardcoded value
            fullAudioUrl = '${AppConfig().backendUrl}/$audioUrl';
          }

          if (kDebugMode) {
            print('Successfully generated audio, URL: $fullAudioUrl');
          }

          _lastGeneratedAudioPath = fullAudioUrl;
          return fullAudioUrl;
        } else {
          if (kDebugMode) {
            print(
                'Error: Received null response from backend. Using local TTS.');
          }

          // Generate a fake URL to trigger the fallback mechanism in playAudio
          String localFallbackPath =
              'local_tts://${DateTime.now().millisecondsSinceEpoch}';
          _lastGeneratedAudioPath = localFallbackPath;

          return localFallbackPath;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error in speech synthesis API call: $e. Using local TTS.');
        }

        // Generate a fake URL to trigger the fallback mechanism in playAudio
        String localFallbackPath =
            'local_tts://${DateTime.now().millisecondsSinceEpoch}';
        _lastGeneratedAudioPath = localFallbackPath;

        return localFallbackPath;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error generating audio: $e. Using local TTS.');
      }

      // Generate a fake URL to trigger the fallback mechanism in playAudio
      String localFallbackPath =
          'local_tts://${DateTime.now().millisecondsSinceEpoch}';
      _lastGeneratedAudioPath = localFallbackPath;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_tts_text', text);
      } catch (_) {
        // Ignore error, we'll use conversation context
      }

      return localFallbackPath;
    }
  }

  // Use TTS backup and save to a specific file
  Future<void> _useTtsBackupToFile(String text, String filePath) async {
    try {
      // Get the text from last TTS message
      String textToSpeak = text;
      try {
        if (textToSpeak.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          textToSpeak = prefs.getString('last_tts_text') ?? '';
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error retrieving TTS text: $e');
        }
      }

      // Use FlutterTts as a fallback
      final flutterTts = FlutterTts();
      await flutterTts.setLanguage('en-US');
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setPitch(1.0);

      // Save the synthesized speech to a file
      Directory directory = Directory(path.dirname(filePath));
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      await flutterTts.synthesizeToFile(textToSpeak, filePath);
      _lastGeneratedAudioPath = filePath;

      if (kDebugMode) {
        print('TTS fallback used and saved to file: $filePath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in TTS fallback: $e');
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
          final player = AudioPlayer();
          try {
            await player.setUrl(audioPath);
            player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                _audioPlaybackController.add(false);
                player.dispose();
              }
            });
            await player.play();
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
          final player = AudioPlayer();
          try {
            await player.setFilePath(audioPath);
            player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                _audioPlaybackController.add(false);
                player.dispose();
              }
            });
            await player.play();
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

      // Stop Flutter TTS if it's speaking
      if (_flutterTts != null) {
        await _flutterTts!.stop();
      }

      // Stop any ongoing audio player
      if (!_isWeb) {
        try {
          final player = AudioPlayer();
          await player.stop();
          await player.dispose();
        } catch (e) {
          if (kDebugMode) {
            print('Error stopping audio player: $e');
          }
        }
      }

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
      if (_flutterTts == null) {
        await _initTts();
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
      await _flutterTts!.speak(textToSpeak);

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
    try {
      if (kDebugMode) print('VoiceService: Disposing resources');
      // Stop any ongoing TTS
      if (_flutterTts != null) {
        _flutterTts!.stop();
      }

      if (_recordingStateController != null &&
          !_recordingStateController!.isClosed) {
        _recordingStateController!.close();
      }

      if (!_audioPlaybackController.isClosed) {
        _audioPlaybackController.close();
      }

      if (!_ttsSpeakingStateController.isClosed) {
        _ttsSpeakingStateController.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error closing stream controllers: $e');
      }
    }

    _audioRecorder.dispose();

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

  // Public method to speak text directly using TTS
  Future<void> speakWithTts(String text) async {
    if (kDebugMode) {
      print(
          '🎙️ TTS: Speaking directly with TTS: "${text.substring(0, min(50, text.length))}..."');
    }

    // Save the text for fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_tts_text', text);
    } catch (e) {
      if (kDebugMode) {
        print('🎙️ TTS: Error saving text for TTS: $e');
      }
    }

    // Use the internal TTS backup method
    await _useTtsBackup();
  }
}
