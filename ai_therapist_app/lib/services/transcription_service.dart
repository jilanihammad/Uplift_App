import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Handles audio transcription functionality
///
/// Responsible for sending audio to the backend API for transcription
/// and processing the results
class TranscriptionService {
  // Transcription API URL
  final String _apiUrl;

  // Stream controllers
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  // Streams for external components to listen to
  Stream<String?> get errorStream => _errorController.stream;

  // Constructor
  TranscriptionService({
    required String apiUrl,
  }) : _apiUrl = apiUrl;

  // Transcribe audio from a file path
  Future<String> transcribeAudio(String audioFilePath) async {
    if (audioFilePath.isEmpty) {
      _errorController.add('Empty audio file path provided for transcription');
      return '';
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      _errorController.add('Audio file does not exist: $audioFilePath');
      return '';
    }

    try {
      if (kDebugMode) {
        debugPrint('🎤 Transcribing audio from: $audioFilePath');
      }

      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiUrl/transcribe'),
      );

      // Add audio file to the request
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();

      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: audioFilePath.split('/').last,
      );

      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Parse the response
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final String transcription = jsonResponse['text'] ?? '';

        if (kDebugMode) {
          debugPrint('🔤 Transcription result: $transcription');
        }

        return transcription;
      } else {
        _errorController.add(
            'Transcription API error: ${response.statusCode}, ${response.body}');
        return '';
      }
    } catch (e) {
      _errorController.add('Error during transcription: $e');
      if (kDebugMode) {
        debugPrint('❌ Transcription error: $e');
      }
      return '';
    }
  }

  // Fallback to offline transcription if available
  Future<String> _fallbackTranscription(String audioFilePath) async {
    // In a real implementation, this could use on-device transcription
    // or another fallback mechanism. For now, we'll just return an error message.
    return '[Transcription failed - network error]';
  }

  // Clean up resources
  Future<void> dispose() async {
    await _errorController.close();
  }
}
