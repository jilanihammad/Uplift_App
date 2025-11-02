import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../services/audio_player_manager.dart';
import '../services/live_tts_audio_source.dart';
import '../services/config_service.dart';
import '../di/interfaces/i_audio_recording_service.dart';

abstract class GeminiLiveEvent {
  const GeminiLiveEvent();
}

class GeminiLiveReadyEvent extends GeminiLiveEvent {
  final String sessionId;
  final int sampleRate;
  final int channels;

  const GeminiLiveReadyEvent({
    required this.sessionId,
    required this.sampleRate,
    required this.channels,
  });
}

class GeminiLiveTextEvent extends GeminiLiveEvent {
  final String text;
  final bool isFinal;
  final int? sequence;

  const GeminiLiveTextEvent({
    required this.text,
    required this.isFinal,
    this.sequence,
  });
}

class GeminiLiveTurnCompleteEvent extends GeminiLiveEvent {
  final int? sequence;

  const GeminiLiveTurnCompleteEvent({this.sequence});
}

class GeminiLiveAudioStartedEvent extends GeminiLiveEvent {
  const GeminiLiveAudioStartedEvent();
}

class GeminiLiveAudioCompletedEvent extends GeminiLiveEvent {
  const GeminiLiveAudioCompletedEvent();
}

class GeminiLiveErrorEvent extends GeminiLiveEvent {
  final String message;

  const GeminiLiveErrorEvent(this.message);
}

class GeminiLiveDisconnectedEvent extends GeminiLiveEvent {
  const GeminiLiveDisconnectedEvent();
}

class GeminiLiveDuplexController {
  GeminiLiveDuplexController({
    required IAudioRecordingService recordingService,
    required AudioPlayerManager audioPlayerManager,
    ConfigService? configService,
    AppConfig? appConfig,
  })  : _recordingService = recordingService,
        _audioPlayerManager = audioPlayerManager,
        _configService = configService ??
            (GetIt.instance.isRegistered<ConfigService>()
                ? GetIt.instance<ConfigService>()
                : null),
        _appConfig = appConfig ?? AppConfig();

  final IAudioRecordingService _recordingService;
  final AudioPlayerManager _audioPlayerManager;
  final ConfigService? _configService;
  final AppConfig _appConfig;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamController<Uint8List>? _audioStreamController;
  LiveTtsAudioSource? _liveAudioSource;
  Future<void>? _playbackFuture;
  bool _audioPlaybackStarted = false;

  final StreamController<GeminiLiveEvent> _eventController =
      StreamController<GeminiLiveEvent>.broadcast();

  bool _connected = false;
  bool _micStreaming = false;
  String? _sessionId;
  int? _sampleRate;
  int? _channels;
  int _audioBytesReceived = 0;

  bool get isConnected => _connected;
  bool get isMicStreaming => _micStreaming;
  String? get sessionId => _sessionId;

  Stream<GeminiLiveEvent> get events => _eventController.stream;

  bool get isEnabled => _configService?.geminiLiveDuplexEnabled ?? false;

  Future<void> connect({String? userId}) async {
    if (!isEnabled) {
      throw StateError('Gemini Live duplex mode is disabled');
    }

    if (_connected) {
      return;
    }

    final backendUrl = _appConfig.backendUrl;
    final wsUri = Uri.parse(
      '${backendUrl.replaceFirst('http', 'ws')}/ws/gemini/live'
          '${userId != null ? '?userId=${Uri.encodeComponent(userId)}' : ''}',
    );

    if (kDebugMode) {
      debugPrint('🔌 [GeminiLive] Connecting to $wsUri');
    }

    try {
      _channel = WebSocketChannel.connect(wsUri);
      _connected = true;
      _audioBytesReceived = 0;
      _setupWebSocketListener();
    } catch (e) {
      _connected = false;
      _eventController.add(GeminiLiveErrorEvent('Connection failed: $e'));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _stopMicStream(sendEndSignal: false);
    await _wsSubscription?.cancel();
    _wsSubscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _connected = false;
    _sessionId = null;
    _resetAudioStream();
    _eventController.add(const GeminiLiveDisconnectedEvent());
  }

  Future<void> startMicStream({int sampleRate = 24000, int numChannels = 1})
      async {
    if (!isEnabled) {
      throw StateError('Gemini Live duplex mode is disabled');
    }

    if (!_connected || _channel == null) {
      throw StateError('Gemini Live WebSocket is not connected');
    }

    if (_micStreaming) {
      return;
    }

    final micStream = await _recordingService.startStreaming(
      sampleRate: sampleRate,
      numChannels: numChannels,
    );

    _micSubscription = micStream.listen(
      (chunk) {
        if (chunk.isEmpty) {
          return;
        }
        try {
          _channel?.sink.add(chunk);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ [GeminiLive] Error sending mic chunk: $e');
          }
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [GeminiLive] Mic stream error: $error');
        }
        _eventController.add(
            GeminiLiveErrorEvent('Microphone streaming error: $error'));
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint('🎤 [GeminiLive] Mic stream completed');
        }
      },
      cancelOnError: true,
    );

    _micStreaming = true;
  }

  Future<void> stopMicStream() async {
    await _stopMicStream();
  }

  Future<void> _stopMicStream({bool sendEndSignal = true}) async {
    if (!_micStreaming) {
      return;
    }

    await _micSubscription?.cancel();
    _micSubscription = null;
    await _recordingService.stopStreaming();
    _micStreaming = false;

    if (sendEndSignal) {
      try {
        _channel?.sink
            .add(jsonEncode({'type': 'audio_stream_end', 'timestamp': DateTime.now().toIso8601String()}));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [GeminiLive] Failed to send audio_stream_end: $e');
        }
      }
    }
  }

  Future<void> sendText(String text, {bool turnComplete = false}) async {
    if (!_connected || _channel == null) {
      throw StateError('Gemini Live WebSocket is not connected');
    }

    final payload = {
      'type': 'client_content',
      'text': text,
      'role': 'user',
      'turn_complete': turnComplete,
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      _eventController.add(
          GeminiLiveErrorEvent('Failed to send text content to Gemini: $e'));
      rethrow;
    }
  }

  void _setupWebSocketListener() {
    _wsSubscription = _channel!.stream.listen(
      _handleWebSocketMessage,
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [GeminiLive] WebSocket error: $error');
        }
        _eventController
            .add(GeminiLiveErrorEvent('WebSocket error: $error'));
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint('🔌 [GeminiLive] WebSocket closed by server');
        }
        _connected = false;
        _eventController.add(const GeminiLiveDisconnectedEvent());
      },
      cancelOnError: true,
    );
  }

  void _handleWebSocketMessage(dynamic message) {
    if (message is List<int>) {
      _handleAudioChunk(Uint8List.fromList(message));
      return;
    }

    if (message is String) {
      try {
        final data = json.decode(message) as Map<String, dynamic>;
        _handleJsonPayload(data);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [GeminiLive] Failed to parse JSON message: $e');
        }
      }
    }
  }

  void _handleJsonPayload(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'ready':
        _sessionId = data['session_id'] as String?;
        final audio = data['audio'] as Map<String, dynamic>?;
        _sampleRate = audio?['sample_rate_hz'] as int?;
        _channels = audio?['channels'] as int?;
        _eventController.add(GeminiLiveReadyEvent(
          sessionId: _sessionId ?? 'unknown',
          sampleRate: _sampleRate ?? 24000,
          channels: _channels ?? 1,
        ));
        break;
      case 'model_text':
        final text = data['text'] as String? ?? '';
        final isFinal = data['isFinal'] as bool? ?? false;
        final sequence = data['sequence'] as int?;
        _eventController.add(GeminiLiveTextEvent(
          text: text,
          isFinal: isFinal,
          sequence: sequence,
        ));
        break;
      case 'turn_complete':
        _eventController.add(
          GeminiLiveTurnCompleteEvent(sequence: data['sequence'] as int?),
        );
        _finalizeAudioStream();
        break;
      case 'error':
        final detail = data['detail']?.toString() ?? 'Unknown error';
        _eventController.add(GeminiLiveErrorEvent(detail));
        break;
      default:
        if (kDebugMode) {
          debugPrint('ℹ️ [GeminiLive] Ignoring message type: $type');
        }
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (chunk.isEmpty) {
      return;
    }

    _audioBytesReceived += chunk.length;

    _ensureAudioStream();
    _audioStreamController?.add(chunk);

    if (!_audioPlaybackStarted) {
      _audioPlaybackStarted = true;
      _eventController.add(const GeminiLiveAudioStartedEvent());
    }
  }

  void _ensureAudioStream() {
    if (_audioStreamController != null && !_audioStreamController!.isClosed) {
      return;
    }

    _audioStreamController = StreamController<Uint8List>.broadcast();
    _liveAudioSource = LiveTtsAudioSource(
      _audioStreamController!.stream,
      contentType: 'audio/wav',
      debugName: 'gemini-live',
    );

    _playbackFuture = _audioPlayerManager
        .playLiveTtsStream(_liveAudioSource!, debugName: 'gemini-live')
        .then((_) {
      _eventController.add(const GeminiLiveAudioCompletedEvent());
      _audioPlaybackStarted = false;
    }).catchError((error) {
      _eventController
          .add(GeminiLiveErrorEvent('Audio playback error: $error'));
      _audioPlaybackStarted = false;
    });
  }

  void _finalizeAudioStream() {
    _liveAudioSource?.markWebSocketClosed(_audioBytesReceived);
    _liveAudioSource?.markStreamCompleted();
    _audioStreamController?.close();
    _audioStreamController = null;
    _liveAudioSource = null;
    _audioBytesReceived = 0;
  }

  void _resetAudioStream() {
    _audioPlaybackStarted = false;
    _audioBytesReceived = 0;
    _liveAudioSource?.markWebSocketClosed();
    _liveAudioSource?.markStreamCompleted();
    _playbackFuture = null;
    _liveAudioSource = null;
    _audioStreamController?.close();
    _audioStreamController = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
  }
}
