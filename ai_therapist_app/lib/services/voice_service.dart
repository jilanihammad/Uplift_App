// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
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

// Recording states
enum RecordingState { ready, recording, stopped, paused, error }

// Transcription models
enum TranscriptionModel { whisper, deepgramAI, assembly }

class VoiceService {
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
  late ApiClient _apiClient;

  // Backend server URL
  late String _backendUrl;

  // Getter for accessing backend URL from other services
  String get apiUrl => _backendUrl;

  // Flag to indicate if we're running in a web environment
  final bool _isWeb = kIsWeb;

  // Constructor - initialize recorder
  VoiceService() {
    _audioRecorder = AudioRecorder();
    _ensureStreamControllerIsActive();
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
    try {
      // Make sure the stream controller is active
      _ensureStreamControllerIsActive();

      // Get API client from service locator
      _apiClient = serviceLocator<ApiClient>();

      // Get backend URL from config service and update to use the URL that's working
      _backendUrl = 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';

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
      if (status != PermissionStatus.granted) {
        throw Exception('Microphone permission not granted');
      }

      // Get temp directory to store the recording
      final tempDir = await getTemporaryDirectory();
      _recordingPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (kDebugMode) {
        print('Will save recording to: $_recordingPath');
      }

      // Check if the recorder has been initialized
      if (!await _audioRecorder.isRecording()) {
        // Start recording
        await _audioRecorder.start(
          RecordConfig(
            encoder:
                AudioEncoder.aacLc, // We keep AAC for recording for quality
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _recordingPath ??
              '${(await getTemporaryDirectory()).path}/recording_fallback.m4a',
        );

        // Update state
        _currentState = RecordingState.recording;
        _recordingStateController!.add(_currentState);

        if (kDebugMode) {
          print('Recording started with path: $_recordingPath');
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
          print('Error sending state to stream: $streamError');
        }
      }

      if (kDebugMode) {
        print('Error starting recording: $e');
      }
      if (!_isWeb) rethrow;
    }
  }

  // Stop recording and get transcription using OpenAI API via backend
  Future<String> stopRecording() async {
    try {
      String recordedFilePath = '';

      // Stop recording and get the file path
      if (!_isWeb && await _audioRecorder.isRecording()) {
        try {
          // Stop recording
          recordedFilePath = await _audioRecorder.stop() ?? '';

          if (kDebugMode) {
            print('Recording stopped, file saved at: $recordedFilePath');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error stopping recording: $e');
          }
        }
      }

      // Update state
      _currentState = RecordingState.stopped;
      _recordingStateController!.add(_currentState);

      if (kDebugMode) {
        print('Recording stopped (${_isWeb ? 'web mode' : 'native mode'})');
      }

      // If we have a recording, process it
      if (!_isWeb && recordedFilePath.isNotEmpty) {
        try {
          // Read the recorded audio file
          final io.File audioFile = io.File(recordedFilePath);
          if (await audioFile.exists()) {
            final bytes = await audioFile.readAsBytes();

            if (bytes.isNotEmpty) {
              if (kDebugMode) {
                print('Audio file size: ${bytes.length} bytes');
              }

              final base64Audio = base64Encode(bytes);

              if (kDebugMode) {
                print(
                    'Audio file encoded successfully, size: ${base64Audio.length} chars, sending to transcription API...');
              }

              try {
                // Make API call with the actual audio data
                final startTime = DateTime.now();
                if (kDebugMode) {
                  print('Using API URL: $_backendUrl for transcription');
                  print('Sending request to: $_backendUrl/voice/transcribe');
                }

                final response =
                    await _apiClient.post('/voice/transcribe', body: {
                  'audio_data': base64Audio,
                  'audio_format':
                      'm4a', // Send as m4a format which is compatible with GROQ
                  'model':
                      'distil-whisper-large-v3-en' // Use the GROQ-supported model
                });

                final duration =
                    DateTime.now().difference(startTime).inMilliseconds;
                if (kDebugMode) {
                  print(
                      'Transcription API response in ${duration}ms: $response');
                }

                if (response != null && response.containsKey('text')) {
                  final transcribedText = response['text'];
                  if (kDebugMode) {
                    print('Transcription successful: $transcribedText');
                  }

                  // Check if we got a meaningful transcription or an error message
                  if (transcribedText != null && transcribedText.isNotEmpty) {
                    // Check if this is an error message from the backend transcription service
                    if (transcribedText
                            .toLowerCase()
                            .contains("error transcribing audio") ||
                        transcribedText
                            .toLowerCase()
                            .contains("error processing") ||
                        transcribedText
                            .toLowerCase()
                            .contains("couldn't understand") ||
                        transcribedText
                            .toLowerCase()
                            .contains("please try again")) {
                      if (kDebugMode) {
                        print(
                            'Received error message from transcription service: $transcribedText');
                      }

                      // Return an empty string to signal UI to focus text input instead of showing error
                      return "";
                    }

                    // This appears to be a valid transcription
                    return transcribedText;
                  } else {
                    if (kDebugMode) {
                      print('Received empty transcription: $transcribedText');
                    }
                    // Fall through to user prompt
                  }
                } else {
                  if (kDebugMode) {
                    print(
                        'Error: Invalid response format from transcription API: $response');
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  print('Error calling transcription API: $e');
                }
              }
            } else {
              if (kDebugMode) {
                print('Error: Audio file is empty.');
              }
            }
          } else {
            if (kDebugMode) {
              print(
                  'Error: Audio file does not exist at path: $recordedFilePath');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error processing audio file: $e');
          }
          // Fall through to user prompt
        } finally {
          // Clean up the temporary recording file
          try {
            final file = io.File(recordedFilePath);
            if (await file.exists()) {
              await file.delete();
              if (kDebugMode) {
                print('Deleted temporary recording file');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error cleaning up recording file: $e');
            }
          }
        }
      }

      // If we reach here, either there was no recording, or transcription failed
      // Instead of using a hardcoded message, prompt the user to type their message
      return ""; // Return empty string to signal UI to focus the text input field
    } catch (e) {
      _currentState = RecordingState.error;
      _recordingStateController!.add(_currentState);
      if (kDebugMode) {
        print('Error in stopRecording: $e');
      }
      // Return empty string to signal UI to focus text input
      return "";
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
            // Use the correct backend URL (without "new---" prefix)
            fullAudioUrl =
                'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app$audioUrl';
          } else {
            // Use the correct backend URL (without "new---" prefix)
            fullAudioUrl =
                'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app/$audioUrl';
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

  // Play an audio file
  Future<void> playAudio(String audioPath) async {
    try {
      // Check if this is a local TTS fallback path
      if (audioPath.startsWith('local_tts://')) {
        await _useTtsBackup();
        return;
      }

      // Check if the path is a URL or a local file path
      if (audioPath.startsWith('http')) {
        if (kDebugMode) {
          print('Playing audio from URL: $audioPath');
        }

        try {
          // Check if the audio file exists by making a HEAD request
          final response = await http.head(Uri.parse(audioPath));

          if (response.statusCode != 200) {
            print(
                'Audio file not found at URL: $audioPath, using text-to-speech fallback');
            // Fallback to text-to-speech for the message content
            await _useTtsBackup();
            return;
          }

          // Try to play audio using just_audio
          if (!_isWeb) {
            try {
              final player = AudioPlayer();
              await player.setUrl(audioPath);
              await player.play();
              // Wait for the audio to finish
              await player.processingStateStream.firstWhere(
                (state) => state == ProcessingState.completed,
              );
              await player.dispose();

              if (kDebugMode) {
                print('Audio playback complete');
              }
              return;
            } catch (audioError) {
              if (kDebugMode) {
                print(
                    'Just Audio error: $audioError, falling back to simulated playback');
              }
              // Fallback to text-to-speech
              await _useTtsBackup();
              return;
            }
          }

          // Fallback: simulate playback with a delay
          await Future.delayed(const Duration(seconds: 2));

          if (kDebugMode) {
            print('Audio playback complete');
          }
        } catch (e) {
          print('Error accessing audio URL: $e');
          // Fallback to text-to-speech
          await _useTtsBackup();
        }
      } else if (!_isWeb) {
        // It's a local file path, check if it exists (only on non-web platforms)
        final file = io.File(audioPath);
        if (!await file.exists()) {
          print(
              'Audio file not found at $audioPath, using text-to-speech fallback');
          // Fallback to text-to-speech
          await _useTtsBackup();
          return;
        }

        if (kDebugMode) {
          print('Playing local audio file at $audioPath');
        }

        // Try to play audio using just_audio
        try {
          final player = AudioPlayer();
          await player.setFilePath(audioPath);
          await player.play();
          // Wait for the audio to finish
          await player.processingStateStream.firstWhere(
            (state) => state == ProcessingState.completed,
          );
          await player.dispose();

          if (kDebugMode) {
            print('Audio playback complete');
          }
          return;
        } catch (audioError) {
          if (kDebugMode) {
            print(
                'Just Audio error: $audioError, falling back to simulated playback');
          }
          // Fallback to text-to-speech
          await _useTtsBackup();
          return;
        }
      } else {
        // Web platform - simulate playback
        if (kDebugMode) {
          print('Web platform: playing audio from $audioPath');
        }

        await Future.delayed(const Duration(seconds: 2));

        if (kDebugMode) {
          print('Audio playback complete');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error playing audio: $e');
      }
      // Fallback to text-to-speech
      await _useTtsBackup();
      if (!_isWeb) rethrow;
    }
  }

  // Stop any ongoing audio playback
  Future<void> stopAudio() async {
    try {
      if (kDebugMode) {
        print('Stopping any ongoing audio playback');
      }

      // Stop Flutter TTS if it's speaking
      final FlutterTts flutterTts = FlutterTts();
      await flutterTts.stop();

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
      print('Using text-to-speech fallback');
    }

    try {
      // Use actual Flutter TTS
      final FlutterTts flutterTts = FlutterTts();

      // Get the text to speak - start with default error message
      String textToSpeak =
          "I'm sorry, there was an issue with the audio playback.";

      try {
        // Try to get the saved text from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final savedText = prefs.getString('last_tts_text');

        if (savedText != null && savedText.isNotEmpty) {
          textToSpeak = savedText;
          if (kDebugMode) {
            print('Using saved text for TTS: $textToSpeak');
          }
        } else if (_conversationContext.isNotEmpty) {
          // Fallback to conversation context if SharedPreferences doesn't have the text
          for (int i = _conversationContext.length - 1; i >= 0; i--) {
            if (_conversationContext[i]['speaker_id'] == _aiSpeakerId) {
              textToSpeak = _conversationContext[i]['text'];
              if (kDebugMode) {
                print('Using conversation context text for TTS: $textToSpeak');
              }
              break;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print(
              'Error retrieving saved text: $e, falling back to conversation context');
        }

        // Fallback to conversation context
        if (_conversationContext.isNotEmpty) {
          for (int i = _conversationContext.length - 1; i >= 0; i--) {
            if (_conversationContext[i]['speaker_id'] == _aiSpeakerId) {
              textToSpeak = _conversationContext[i]['text'];
              break;
            }
          }
        }
      }

      // Configure TTS
      await flutterTts.setLanguage("en-US");
      await flutterTts.setPitch(1.0);
      await flutterTts.setSpeechRate(0.5); // Slightly slower for better clarity

      if (kDebugMode) {
        print('Speaking text: $textToSpeak');
      }

      // Speak the text
      await flutterTts.speak(textToSpeak);

      // Wait for speaking to complete
      await flutterTts.awaitSpeakCompletion(true);

      if (kDebugMode) {
        print('Text-to-speech playback complete');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error using Flutter TTS: $e');
        // Fallback to just a delay if TTS fails
        await Future.delayed(const Duration(seconds: 1));
        print('Simulated text-to-speech playback complete');
      }
    }
  }

  // Cleanup resources
  void dispose() {
    try {
      if (_recordingStateController != null &&
          !_recordingStateController!.isClosed) {
        _recordingStateController!.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error closing stream controller: $e');
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
}
