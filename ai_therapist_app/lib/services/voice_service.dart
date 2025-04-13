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
        
        // In a real implementation, we would use a audio player plugin to play the audio
        // For now, just simulate the playback with a delay
        await Future.delayed(const Duration(seconds: 2));
        
        if (kDebugMode) {
          print('Audio playback complete');
        }
      } else if (!_isWeb) {
        // It's a local file path, check if it exists (only on non-web platforms)
        final file = io.File(audioPath);
        if (!await file.exists()) {
          throw Exception("Audio file not found at $audioPath");
        }
        
        if (kDebugMode) {
          print('Playing local audio file at $audioPath');
        }
        
        // In a real implementation, we'd use a Flutter audio player plugin
        // For now, just simulate the playback with a delay
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
      if (!_isWeb) rethrow;
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