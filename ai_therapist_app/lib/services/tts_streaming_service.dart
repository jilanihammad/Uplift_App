import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:just_audio/just_audio.dart';

class TTSStreamingService {
  static const String wsUrl =
      'wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final List<int> _audioBuffer = [];
  final _player = AudioPlayer();

  Future<void> connectAndRequestTTS({
    required String text,
    String voice = 'sage',
    String responseFormat = 'opus',
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    _audioBuffer.clear();
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    final request = jsonEncode({
      'text': text,
      'voice': voice,
      'params': {'response_format': responseFormat},
    });

    // Listen for incoming audio chunks
    _subscription = _channel!.stream.listen((event) async {
      try {
        final data = jsonDecode(event);
        if (data['type'] == 'audio_chunk') {
          final chunk = base64Decode(data['data']);
          _audioBuffer.addAll(chunk);
          // Optionally, call onProgress with percent complete (if available)
        } else if (data['type'] == 'done') {
          await _playBufferedAudio(responseFormat);
          onDone?.call();
          await close();
        } else if (data['type'] == 'error') {
          onError?.call(data['detail'] ?? 'Unknown error');
          await close();
        }
      } catch (e) {
        onError?.call('Failed to process TTS stream: $e');
        await close();
      }
    }, onError: (err) async {
      onError?.call('WebSocket error: $err');
      await close();
    }, onDone: () async {
      await close();
    });

    // Send the TTS request
    _channel!.sink.add(request);
  }

  Future<void> _playBufferedAudio(String format) async {
    try {
      // Write buffer to a temp file or use a custom audio source
      // For simplicity, use AudioPlayer's BytesAudioSource
      final audioSource = BytesAudioSource(
        Uint8List.fromList(_audioBuffer),
        contentType: format == 'opus' ? 'audio/ogg' : 'audio/mpeg',
      );
      await _player.setAudioSource(audioSource);
      await _player.play();
    } catch (e) {
      // Handle playback errors
      rethrow;
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _player.stop();
    _audioBuffer.clear();
  }

  void dispose() {
    close();
    _player.dispose();
  }
}

/// Usage:
/// final ttsService = TTSStreamingService();
/// ttsService.connectAndRequestTTS(
///   text: 'Hello world',
///   onDone: () => print('Playback done'),
///   onError: (err) => print('Error: $err'),
/// );
