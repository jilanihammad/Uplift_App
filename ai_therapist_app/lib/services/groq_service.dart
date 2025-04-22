import 'package:flutter/foundation.dart';

class GroqService {
  // ... existing code ...

  // Transcribe audio using the transcription model
  Future<String> transcribeAudio({
    required String audioUrl,
  }) async {
    if (!_isAvailable) {
      throw Exception('GroqService is not available');
    }

    try {
      // Make API request to backend proxy for Groq transcription
      final response = await _apiClient.post('/voice/transcribe', body: {
        'audio_url': audioUrl,
        'model': _transcriptionModelId,
      });

      if (response != null && response.containsKey('text')) {
        return response['text'];
      } else if (response != null && response.containsKey('transcription')) {
        return response['transcription'];
      } else {
        throw Exception('Invalid response format from transcription API');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService: Error transcribing audio: $e');
      }
      rethrow;
    }
  }

  // ... existing code ...
}
