import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
    String responseFormat =
        'wav', // Changed from 'opus' to 'wav' for lowest latency streaming
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
      // Write buffer to a temporary file and play from file
      final tempDir = await getTemporaryDirectory();
      // Updated file extension logic for WAV format
      final ext = format == 'wav'
          ? 'wav'
          : format == 'opus'
              ? 'ogg'
              : 'mp3';
      final tempFile = File(
          '${tempDir.path}/tts_stream_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await tempFile.writeAsBytes(_audioBuffer);

      await _player.setFilePath(tempFile.path);
      await _player.play();

      // Clean up temp file after playback
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          tempFile.delete().catchError((_) {});
        }
      });
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
