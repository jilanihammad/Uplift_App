import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Manages text-to-speech functionality
///
/// Responsible for generating audio from text using a backend API
/// or local TTS as fallback
class TTSManager {
  // TTS API URL
  final String _apiUrl;

  // Local TTS engine for fallback
  final FlutterTts _flutterTts = FlutterTts();

  // Stream controllers
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final StreamController<bool> _ttsStateController =
      StreamController<bool>.broadcast();

  // Streams for external components to listen to
  Stream<String?> get errorStream => _errorController.stream;
  Stream<bool> get ttsStateStream => _ttsStateController.stream;

  // Last generated audio path
  String? _lastGeneratedAudioPath;
  String? get lastGeneratedAudioPath => _lastGeneratedAudioPath;

  // Track current TTS state
  bool _isCurrentlySpeaking = false;
  bool get isCurrentlySpeaking => _isCurrentlySpeaking;

  // Constructor
  TTSManager({
    required String apiUrl,
  }) : _apiUrl = apiUrl {
    _initializeLocalTts();
  }

  // Initialize the local TTS engine
  Future<void> _initializeLocalTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        if (kDebugMode) {
          print('🔊 Local TTS started');
        }
        _isCurrentlySpeaking = true;
        _ttsStateController.add(true);
      });

      _flutterTts.setCompletionHandler(() {
        if (kDebugMode) {
          print('🔊 Local TTS completed');
        }
        _isCurrentlySpeaking = false;
        _ttsStateController.add(false);
      });

      _flutterTts.setErrorHandler((error) {
        if (kDebugMode) {
          print('🔊 Local TTS error: $error');
        }
        _isCurrentlySpeaking = false;
        _errorController.add('TTS error: $error');
        _ttsStateController.add(false);
      });
    } catch (e) {
      _errorController.add('Error initializing local TTS: $e');
      if (kDebugMode) {
        print('❌ Error initializing local TTS: $e');
      }
    }
  }

  // Generate audio from text using the API
  Future<String> generateAudio(String text) async {
    if (text.isEmpty) {
      _errorController.add('Empty text provided for TTS');
      return '';
    }

    try {
      if (kDebugMode) {
        print('🔊 Generating audio for text: $text');
      }

      // Prepare the request
      final response = await http.post(
        Uri.parse('$_apiUrl/tts'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'text': text,
          'voice': 'alloy', // Default voice ID
        }),
      );

      if (response.statusCode == 200) {
        // Save the audio file
        final Directory tempDir = await getTemporaryDirectory();
        final String uuid = const Uuid().v4();
        final String filePath = '${tempDir.path}/$uuid.mp3';

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        _lastGeneratedAudioPath = filePath;

        // Add debug logging for file size and duration
        if (kDebugMode) {
          final fileSize = await file.length();
          print(
              '🔊 Audio generated and saved to: $filePath (size: $fileSize bytes)');
          // Optionally, try to get duration if possible (requires just_audio or similar)
        }

        return filePath;
      } else {
        _errorController
            .add('TTS API error: ${response.statusCode}, ${response.body}');
        return '';
      }
    } catch (e) {
      _errorController.add('Error generating audio: $e');
      if (kDebugMode) {
        print('❌ TTS error: $e');
      }
      return '';
    }
  }

  // Speak text using local TTS
  Future<void> speakWithTts(String text) async {
    if (text.isEmpty) {
      _errorController.add('Empty text provided for local TTS');
      return;
    }

    try {
      _ttsStateController.add(true);

      if (kDebugMode) {
        print('🔊 Speaking with local TTS: $text');
      }

      await _flutterTts.speak(text);
    } catch (e) {
      _errorController.add('Error with local TTS: $e');
      _ttsStateController.add(false);
      if (kDebugMode) {
        print('❌ Local TTS error: $e');
      }
    }
  }

  // Stop local TTS
  Future<void> stopTts() async {
    try {
      await _flutterTts.stop();
      _ttsStateController.add(false);
    } catch (e) {
      _errorController.add('Error stopping TTS: $e');
      if (kDebugMode) {
        print('❌ Error stopping TTS: $e');
      }
    }
  }

  // Added for manual state management when using API-based TTS
  void notifyTtsPlaying(bool isPlaying) {
    if (kDebugMode) {
      print(
          '🔊 TTS state manually set to: ${isPlaying ? 'playing' : 'stopped'}');
    }
    _isCurrentlySpeaking = isPlaying;
    _ttsStateController.add(isPlaying);
  }

  // Clean up resources
  Future<void> dispose() async {
    await _flutterTts.stop();
    await _errorController.close();
    await _ttsStateController.close();
  }
}
