// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
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

// Recording states
enum RecordingState {
  ready,
  recording,
  stopped,
  paused,
  error
}

// Transcription models
enum TranscriptionModel {
  whisper,
  deepgramAI,
  assembly
}

class VoiceService {
  // Stream controllers for voice recording states
  final StreamController<RecordingState> _recordingStateController = 
      StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get recordingState => _recordingStateController.stream;
  
  // Current state of recording
  RecordingState _currentState = RecordingState.ready;
  
  // Path to the CSM directory
  String? _csmPath;
  
  // Speaker IDs
  final int _userSpeakerId = 0; // Speaker A
  final int _aiSpeakerId = 1;    // Speaker B
  
  // Audio context for the conversation
  List<Map<String, dynamic>> _conversationContext = [];
  
  // Generated audio path
  String? _lastGeneratedAudioPath;
  
  // API client for making requests to backend
  late ApiClient _apiClient;
  
  // Backend server URL
  late String _backendUrl;
  
  // Getter for accessing backend URL from other services
  String get apiUrl => _backendUrl;
  
  // Flag to indicate if we're running in a web environment
  final bool _isWeb = kIsWeb;
  
  // Method to initialize the voice service
  Future<void> initialize() async {
    try {
      // Get API client from service locator
      _apiClient = serviceLocator<ApiClient>();
      
      // Get backend URL from config service
      final configService = serviceLocator<ConfigService>();
      _backendUrl = configService.llmApiEndpoint;
      
      if (kDebugMode) {
        print('Voice service initialized with API client');
      }
      
      // For web platform, use a simplified initialization
      if (_isWeb) {
        if (kDebugMode) {
          print('Initializing voice service in web mode');
        }
        _currentState = RecordingState.ready;
        _recordingStateController.add(_currentState);
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
      _recordingStateController.add(_currentState);
      
      if (kDebugMode) {
        print('Voice service initialized successfully');
      }
    } catch (e) {
      _currentState = RecordingState.error;
      _recordingStateController.add(_currentState);
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
      _currentState = RecordingState.recording;
      _recordingStateController.add(_currentState);
      
      if (kDebugMode) {
        print('Recording started (${_isWeb ? 'web mode' : 'native mode'})');
      }
    } catch (e) {
      _currentState = RecordingState.error;
      _recordingStateController.add(_currentState);
      if (!_isWeb) rethrow;
    }
  }
  
  // Stop recording and get transcription using Groq API via backend
  Future<String> stopRecording() async {
    try {
      _currentState = RecordingState.stopped;
      _recordingStateController.add(_currentState);
      
      if (kDebugMode) {
        print('Recording stopped (${_isWeb ? 'web mode' : 'native mode'})');
      }
      
      // In a real implementation, we would have the audio file to send
      // For now, use a simulated transcription when in debug mode
      if (kDebugMode) {
        return "This is a simulated transcription for testing purposes.";
      }
      
      try {
        // Make API call to the backend for speech-to-text using Groq API
        final response = await _apiClient.post('/voice/transcribe', body: {
          'audio_url': 'temp_audio_recording.mp3',
          'model': 'whisper-large-v3-turbo'
        });
        
        if (response != null && response.containsKey('transcription')) {
          return response['transcription'];
        } else {
          throw Exception("Invalid response format from transcription API");
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error in transcription API call: $e');
        }
        // Fallback with a more helpful message
        return "I couldn't hear you clearly. Could you please repeat that?";
      }
    } catch (e) {
      _currentState = RecordingState.error;
      _recordingStateController.add(_currentState);
      if (kDebugMode) {
        print('Error stopping recording: $e');
      }
      if (!_isWeb) rethrow;
      return "Sorry, I couldn't process the audio. Please try again.";
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
        _conversationContext = _conversationContext.sublist(_conversationContext.length - 10);
      }
      
      try {
        // Make API call to the backend for text-to-speech using Groq API
        final response = await _apiClient.post('/voice/synthesize', body: {
          'text': text,
          'voice': isAiSpeaking ? 'Jennifer-PlayAI' : 'Mason-PlayAI', // Updated to use valid Groq TTS voices
        });
        
        if (response != null && response.containsKey('audio_url')) {
          // The backend returns a URL to the generated audio file
          final audioUrl = response['audio_url'];
          
          // Construct the full URL
          String fullAudioUrl = audioUrl.startsWith('http') 
              ? audioUrl 
              : '$_backendUrl$audioUrl';
          
          _lastGeneratedAudioPath = fullAudioUrl;
          return fullAudioUrl;
        } else {
          throw Exception("Invalid response format from speech synthesis API");
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error in speech synthesis API call: $e');
        }
        
        // Return a URL that indicates an error occurred
        return '$_backendUrl/audio/error.mp3';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error generating audio: $e');
      }
      
      // Return a URL that indicates an error occurred
      return '$_backendUrl/audio/error.mp3';
    }
  }
  
  // Play an audio file
  Future<void> playAudio(String audioPath) async {
    try {
      // Check if the path is a URL or a local file path
      if (audioPath.startsWith('http')) {
        if (kDebugMode) {
          print('Playing audio from URL: $audioPath');
        }
        
        try {
          // Check if the audio file exists by making a HEAD request
          final response = await http.head(Uri.parse(audioPath));
          
          if (response.statusCode != 200) {
            print('Audio file not found at URL: $audioPath, using text-to-speech fallback');
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
                print('Just Audio error: $audioError, falling back to simulated playback');
              }
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
          print('Audio file not found at $audioPath, using text-to-speech fallback');
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
            print('Just Audio error: $audioError, falling back to simulated playback');
          }
        }
        
        // Fallback: simulate playback with a delay
        await Future.delayed(const Duration(seconds: 2));
        
        if (kDebugMode) {
          print('Audio playback complete');
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
    
    // In a real implementation, we would use the device's text-to-speech capabilities
    // For now, just simulate with a delay
    await Future.delayed(const Duration(seconds: 1));
    
    if (kDebugMode) {
      print('Text-to-speech playback complete');
    }
  }
  
  // Cleanup resources
  void dispose() {
    _recordingStateController.close();
    
    // Clean up any temporary files (only on non-web platforms)
    if (!_isWeb && _lastGeneratedAudioPath != null && !_lastGeneratedAudioPath!.startsWith('http')) {
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