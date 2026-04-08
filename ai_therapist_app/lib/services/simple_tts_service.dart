// lib/services/simple_tts_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import '../utils/box_logger.dart';
import '../utils/log_channels.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/tts_request.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_audio_settings.dart';
import '../di/dependency_container.dart';
import 'audio_player_manager.dart';
import 'path_manager.dart';
import '../config/app_config.dart';
import '../config/tts_streaming_config.dart';
import '../config/audio_format_config.dart';
import '../config/llm_config.dart';
import 'tts_streaming_monitor.dart';
import 'tts_completion_tracker.dart';
import 'package:ai_therapist_app/utils/audio_path_utils.dart';
import '../utils/wav_header_utils.dart';
import 'live_tts_audio_source.dart';
import 'audio_format_negotiator.dart';
import '../utils/opus_header_utils.dart';
import '../utils/throttled_debug_print.dart';
import '../exceptions/tts_exception.dart';
const bool kTTSUseInMemoryPlayback = true;
class SimpleTTSService implements ITTSService {
  // -------- Log Suppression Flags ------------------------------------
  static bool _formatMismatchLogged = false;
  bool get _ttsTraceEnabled => kDebugMode && LogChannels.ttsTrace;
  void _ttsTrace(String message) {
    if (_ttsTraceEnabled) {
    }
  }
  // -------- Public API -----------------------------------------------
  @override
  Future<void> speak(
    String text, {
    String? voice,
    String format = 'auto', // Let negotiator determine optimal format
    bool makeBackupFile = true,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      if (kDebugMode) _ttsTrace('❌ [TTS] Empty text, skipping');
      return;
    }
    await _ensureTTSConfig();
    final caller = _getCallerInfo();
    final selectedVoice = voice ?? LLMConfig.activeTTSVoice;
    final pendingDisplay = (_pendingStreams < 0 ? 0 : _pendingStreams) + 1;
    final upcomingQueueSize = _queue.length + 1;
    AudioFormatNegotiator.updateFromConfig();
    final optimalFormat =
        format == 'auto' ? AudioFormatNegotiator.getBackendFormat() : format;
    final preview = trimmedText.length > 80
        ? '${trimmedText.substring(0, 80)}...'
        : trimmedText;
    BoxLogger.debug(
      '🎯',
      'TTS',
      'Starting playback',
      details: {
        'Text': preview,
        'Voice': selectedVoice,
        'Format': optimalFormat,
        'Provider': LLMConfig.activeTTSProvider.name,
        'Mode': LLMConfig.activeTTSMode,
        'Queue(next)': '$upcomingQueueSize',
        'Pending': '$pendingDisplay',
        'Caller': caller,
      },
    );
    final req = TtsRequest(
      text: trimmedText,
      voice: selectedVoice,
      format: optimalFormat,
      makeBackupFile: makeBackupFile,
    );
    _queue.add(req);
    _pendingStreams++; // Track this TTS request
    if (_ttsTraceEnabled) {
      BoxLogger.debug(
        '🔍',
        'TTS',
        'Queued request ${req.id}',
        details: {
          'Queue length': '${_queue.length}',
          'Pending': '$_pendingStreams',
          'Backup': '${req.makeBackupFile}',
        },
      );
    }
    _pumpQueue(); // Fire-and-forget
    return req.completion; // Caller awaits playback completion
  }
  // -------- Private Implementation -----------------------------------
  final ListQueue<TtsRequest> _queue = ListQueue();
  final AudioPlayerManager _audioPlayerManager;
  void Function(bool isSpeaking)? _onTTSComplete;
  void Function(bool isSpeaking, {int? playbackToken})?
      _voiceServiceUpdateCallback;
  int Function()? _getCurrentGenerationCallback;
  bool Function()? _isSessionValidCallback;
  bool _ttsConfigFetched = false; // True if we've attempted fetch (success or failure)
  Future<void>? _configFetchInProgress; // Deduplication for concurrent speak() calls
  int _pendingStreams = 0; // Monotonic counter for overlapping instances
  LiveTtsAudioSource? _activeLiveAudioSource;
  TwoPhaseCompletion? _activeCompletionTracker;
  late final StreamController<bool> _speakingStateController;
  bool _lastSpeakingState = false;
  _State _state = _State.idle;
  late String _backendUrl;
  bool _disposed = false;
  Completer<void>? _disposeCompleter;
  WebSocketChannel? _prewarmedConnection;
  DateTime? _prewarmedConnectionCreatedAt;
  static const Duration _connectionTtl = Duration(seconds: 30);
  String? _prewarmedConnectionUrl;
  Future<WebSocketChannel> _getConnection(String wsUrl) async {
    if (_prewarmedConnection != null &&
        _prewarmedConnectionUrl == wsUrl &&
        _prewarmedConnectionCreatedAt != null &&
        DateTime.now().difference(_prewarmedConnectionCreatedAt!) < _connectionTtl) {
      final conn = _prewarmedConnection!;
      _prewarmedConnection = null;
      _prewarmedConnectionUrl = null;
      _prewarmedConnectionCreatedAt = null;
      _prewarmNextConnection(wsUrl);
      return conn;
    }
    final conn = WebSocketChannel.connect(Uri.parse(wsUrl));
    _prewarmNextConnection(wsUrl);
    return conn;
  }
  void _prewarmNextConnection(String wsUrl) {
    if (_disposed) return;
    if (_prewarmedConnection != null &&
        _prewarmedConnectionCreatedAt != null &&
        DateTime.now().difference(_prewarmedConnectionCreatedAt!) < _connectionTtl) {
      return;
    }
    Future.microtask(() async {
      if (_disposed) return;
      try {
        try {
          await _prewarmedConnection?.sink.close();
        } catch (_) {}
        _prewarmedConnection = WebSocketChannel.connect(Uri.parse(wsUrl));
        _prewarmedConnectionCreatedAt = DateTime.now();
        _prewarmedConnectionUrl = wsUrl;
      } catch (e) {
        _prewarmedConnection = null;
        _prewarmedConnectionCreatedAt = null;
        _prewarmedConnectionUrl = null;
      }
    });
  }
  Future<void> _cleanupPrewarmedConnection() async {
    if (_prewarmedConnection != null) {
      try {
        await _prewarmedConnection!.sink.close();
      } catch (_) {}
      _prewarmedConnection = null;
      _prewarmedConnectionCreatedAt = null;
      _prewarmedConnectionUrl = null;
    }
  }
  // -------- GOLD STANDARD: Lazy TTS Config Initialization ---------------
  Future<void> _ensureTTSConfig() async {
    if (_ttsConfigFetched) return;
    if (_configFetchInProgress != null) {
      return await _configFetchInProgress!;
    }
    _configFetchInProgress = _fetchConfigWithFallback();
    try {
      await _configFetchInProgress!;
      _ttsConfigFetched = true;
    } finally {
      _configFetchInProgress = null;
    }
  }
  Future<void> _fetchConfigWithFallback() async {
    try {
      final apiClient = DependencyContainer().apiClient;
      final config = await apiClient.fetchTtsConfig()
          .timeout(const Duration(seconds: 5));
      if (config != null && config.provider.isNotEmpty) {
        LLMConfig.applyRemoteTtsConfig(
          provider: config.provider,
          model: config.model,
          voice: config.voice,
          sampleRateHz: config.sampleRateHz,
          audioEncoding: config.audioEncoding,
          responseFormat: config.responseFormat,
          supportsStreaming: config.supportsStreaming,
          mode: config.mode,
          mimeType: config.mimeType,
        );
        AudioFormatNegotiator.updateFromConfig(log: true);
      } else {
      }
    } catch (e) {}
  }
  @override
  void setCachedTTSConfig() {
    _ttsConfigFetched = true;
  }
  SimpleTTSService({
    AudioPlayerManager? audioPlayerManager,
    IAudioSettings? audioSettings,
    void Function(bool isSpeaking)? onTTSComplete,
    void Function(bool isSpeaking, {int? playbackToken})?
        voiceServiceUpdateCallback,
  })  : _audioPlayerManager = audioPlayerManager ??
            AudioPlayerManager(audioSettings: audioSettings),
        _onTTSComplete = onTTSComplete,
        _voiceServiceUpdateCallback = voiceServiceUpdateCallback {
    _backendUrl = AppConfig().backendUrl;
    _speakingStateController = StreamController<bool>.broadcast(sync: true);
    AudioFormatNegotiator.initialize();
  }
  void setCompletionCallback(void Function(bool isSpeaking)? callback) {
    _onTTSComplete = callback;
  }
  void setVoiceServiceUpdateCallback(
      void Function(bool isSpeaking, {int? playbackToken})? callback) {
    _voiceServiceUpdateCallback = callback;
  }
  void setGetCurrentGenerationCallback(int Function()? callback) {
    _getCurrentGenerationCallback = callback;
  }
  @override
  void setSessionValidityCallback(bool Function()? callback) {
    _isSessionValidCallback = callback;
  }
  Future<void> _pumpQueue() async {
    if (_state != _State.idle || _queue.isEmpty || _disposed) return;
    final req = _queue.removeFirst();
    // CRITICAL FIX: Check session validity before processing TTS request
    if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
      _pendingStreams--;
      _updateSpeakingState(false);
      if (_queue.isNotEmpty) {
        _pumpQueue();
      }
      return;
    }
    WebSocketChannel? ws;
    TwoPhaseCompletion? completionTracker;
    try {
      _state = _State.connecting;
      // CRITICAL: Notify that TTS is starting BEFORE WebSocket connection
      _notifyTTSStart();
      final wsUrl = '$_backendUrl/ws/tts'.replaceFirst('http', 'ws');
      ws = await _getConnection(wsUrl);
      _state = _State.streaming;
      _activeCompletionTracker?.dispose();
      _activeCompletionTracker = null;
      completionTracker = TwoPhaseCompletion();
      final tracker = completionTracker;
      _activeCompletionTracker = tracker;
      tracker.initializeWithPlayer(_audioPlayerManager.audioPlayer);
      tracker.setStopPlayerCallback(() async {
        await _audioPlayerManager.stopAudio();
      });
      tracker.setPlaybackFinishedCallback(() {
        _notifyTTSEnd(); // Signal TTS completion
        _fireCompletionSafely(false); // Reset speaking state
      });
      // Note: VAD restart will be handled by VoiceSessionBloc when it receives TTS completion
      await _processResponse(req, ws, tracker);
      req.complete();
    } catch (e, stackTrace) {
      final ttsException = _convertToTtsException(e, 'TTS request processing');
      req.completeError(ttsException, stackTrace);
      _notifyTTSEnd(); // Reset TTS state on ANY error
      _fireCompletionSafely(false);
    } finally {
      // CRITICAL: Always close WebSocket, even on error (prevents resource leaks)
      if (ws != null) {
        try {
          await ws.sink.close();
          await ws.sink.done;
          if (kDebugMode) _ttsTrace('🔍 [TTS] WebSocket closed for ${req.id}');
        } catch (closeError) {
          final ttsException =
              _convertToTtsException(closeError, 'WebSocket cleanup');
        }
      }
      if (completionTracker != null) {
        if (identical(_activeCompletionTracker, completionTracker)) {
          _activeCompletionTracker = null;
        }
        completionTracker.dispose();
      }
      if (_pendingStreams > 0) {
        _pendingStreams--;
      } else {
        _pendingStreams = 0;
      }
      if (_pendingStreams <= 0) {
        _notifyTTSEnd();
        _fireCompletionSafely(false);
      }
      _state = _State.idle;
      _pumpQueue();
    }
  }
  Future<void> _processResponse(TtsRequest req, WebSocketChannel ws,
      TwoPhaseCompletion completionTracker) async {
    final streamingEnabled = TTSStreamingConfig.shouldUseStreaming;
    final requestedFormat = req.format;
    final bufferSize = _getOptimalBufferSize(requestedFormat);
    if (streamingEnabled) {
      await _processResponseStreaming(req, ws, bufferSize, completionTracker);
    } else {
      await _processResponseFullBuffer(req, ws, completionTracker);
    }
  }
  int _getOptimalBufferSize(String format) {
    switch (format.toLowerCase()) {
      case 'opus':
        return 4096; // 4KB - OPUS streams efficiently at smaller chunks
      case 'mp3':
      case 'mpeg':
        return 512; // 512 bytes - Much smaller due to 10x compression (prevents 2s delay)
      case 'wav':
      default:
        return 4096; // 4KB - Faster time-to-first-audio (was 8KB)
    }
  }
  Future<void> _processResponseStreaming(TtsRequest req, WebSocketChannel ws,
      int bufferSize, TwoPhaseCompletion completionTracker) async {
    final startTime = DateTime.now();
    DateTime? firstAudioTime;
    DateTime? playbackStartTime;
    final audioBuffer = <int>[];
    const int progressLogStepBytes = 131072; // 128 KB
    int progressLogCount = 0;
    int lastProgressLogBytes = 0;
    void logProgressIfNeeded() {
      if (!kDebugMode) return;
      final total = audioBuffer.length;
      final delta = total - lastProgressLogBytes;
      final shouldLogEarly = progressLogCount < 2;
      if (!shouldLogEarly && delta < progressLogStepBytes) {
        return;
      }
      _ttsTrace('🎯 [TTS] Streaming progress: $total bytes for ${req.id}');
      progressLogCount++;
      lastProgressLogBytes = total;
    }
    bool gotHello = false;
    bool playbackStarted = false;
    StreamController<Uint8List>? audioStreamController;
    WavHeaderInfo? originalHeaderInfo;
    // CRITICAL: Track LiveTtsAudioSource for proper lifecycle management
    LiveTtsAudioSource? liveAudioSource;
    try {
      final requestedFormat = req.format;
      String currentMimeType =
          AudioFormatNegotiator.getMimeTypeForFormat(requestedFormat);
      final contentType = currentMimeType;
      final handshakeMessage = {
        'text': req.text,
        'voice': req.voice,
        'params': {
          'response_format': requestedFormat,
          'mime_type': currentMimeType,
        }, // Request format directly
        'session_id': req.id,
        'client_version': '1.9.0',
        'format': requestedFormat, // Direct format specification
        'mode': LLMConfig.activeTTSMode,
        'provider': LLMConfig.activeTTSProvider.name,
        'opus_params': requestedFormat == 'opus'
            ? {
                'sample_rate': AudioFormatConfig.opusSampleRate,
                'channels': AudioFormatConfig.opusChannels,
                'bitrate': AudioFormatConfig.opusBitrate,
              }
            : null,
      };
      ws.sink.add(jsonEncode(handshakeMessage));
      // CRITICAL: Must be broadcast to support just_audio's multiple listeners
      audioStreamController = StreamController<Uint8List>.broadcast(sync: true);
      Future<void>? playbackFuture;
      await for (final message in ws.stream) {
        if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
          completionTracker.markWebSocketDone();
          break; // Exit loop early
        }
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'];
          if (type == 'tts-hello') {
            gotHello = true;
          } else if (type == 'tts-done') {
            final totalSize = data['total_size'] as int?;
            final serverMime = data['mime_type'] as String?;
            if (serverMime != null && serverMime.isNotEmpty) {
              currentMimeType = serverMime;
            }
            // CRITICAL: Mark WebSocket phase complete but DON'T close stream yet
            completionTracker.markWebSocketDone();
            // CRITICAL: Mark WebSocket as closed in LiveTtsAudioSource with content size for ExoPlayer completion
            liveAudioSource?.markWebSocketClosed(totalSize);
            // CRITICAL: Don't close the stream immediately - let LiveTtsAudioSource drain data
            _scheduleControllerClosureCheck(
                audioStreamController, liveAudioSource);
            break;
          } else if (type == 'error') {
            final errorDetail = data['detail'] ?? 'TTS error';
            throw TtsNetworkException('TTS service error', errorDetail);
          }
        } else if (message is List<int>) {
          firstAudioTime ??= DateTime.now();
          if (!playbackStarted) {
            audioBuffer.addAll(message);
            if (gotHello &&
                audioBuffer.length >= bufferSize && // Format-aware buffer size
                _isValidAudioHeader(
                    audioBuffer, requestedFormat, currentMimeType)) {
              playbackStarted =
                  true; // CRITICAL: Set flag immediately to prevent multiple starts
              playbackStartTime =
                  DateTime.now(); // Record playback start timing
              // CRITICAL: Hard-gate format processing (MP3/OPUS/WAV)
              Uint8List streamingAudioData;
              if (requestedFormat.toLowerCase() == 'opus') {
                streamingAudioData = Uint8List.fromList(audioBuffer);
              } else if (requestedFormat.toLowerCase() == 'mp3' || requestedFormat.toLowerCase() == 'mpeg') {
                streamingAudioData = Uint8List.fromList(audioBuffer);
              } else {
                final bool alreadyStreamingFriendly =
                    WavHeaderUtils.isStreamingFriendly(audioBuffer);
                if (alreadyStreamingFriendly) {
                  streamingAudioData = Uint8List.fromList(audioBuffer);
                } else {
                  originalHeaderInfo =
                      WavHeaderUtils.parseWavHeader(audioBuffer);
                  if (originalHeaderInfo != null) {
                    final streamingHeader =
                        WavHeaderUtils.createStreamingHeader(
                            originalHeaderInfo);
                    final pcmData = WavHeaderUtils.extractPcmData(
                        audioBuffer, originalHeaderInfo);
                    streamingAudioData = WavHeaderUtils.combineHeaderAndPcm(
                        streamingHeader, pcmData);
                  } else {
                    streamingAudioData = Uint8List.fromList(audioBuffer);
                  }
                }
              }
              // CRITICAL: Create LiveTtsAudioSource BEFORE adding any data to prevent broadcast stream data loss
              liveAudioSource = LiveTtsAudioSource(
                audioStreamController.stream,
                contentType: contentType, // Use negotiated content type
                debugName: 'tts_stream_${req.id}',
              );
              _activeLiveAudioSource = liveAudioSource;
              // CRITICAL FIX: Add initial data BEFORE setAudioSource() call
              if (audioStreamController.isClosed == false) {
                try {
                  audioStreamController.add(streamingAudioData);
                } catch (e) {}
              }
              final genAtStart = _getCurrentGenerationCallback?.call() ?? -1;
              if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
                completionTracker.markWebSocketDone();
                completionTracker.markPlayerDone();
                break; // Exit WebSocket loop early
              }
              playbackFuture = _audioPlayerManager.playLiveTtsStream(
                liveAudioSource, // Pass the LiveTtsAudioSource object for proper lifecycle management
                debugName: 'tts_stream_${req.id}',
                contentType: currentMimeType, // Use negotiated content type
                onPlaybackToken: (playbackToken) {
                  _voiceServiceUpdateCallback?.call(
                    true,
                    playbackToken: playbackToken,
                  );
                },
                onNaturalCompletion: (playbackToken) {
                  if (_isSessionValidCallback != null && !_isSessionValidCallback!()) {
                    return; // Don't trigger listening restart if session ended
                  }
                  final currentGen = _getCurrentGenerationCallback?.call() ?? -1;
                  final genMismatch = currentGen != genAtStart && genAtStart != -1;
                  _voiceServiceUpdateCallback?.call(
                    false,
                    playbackToken: playbackToken,
                  );
                },
              ).then((_) {
                completionTracker.markPlayerDone();
              });
            }
          } else {
            if (audioStreamController.isClosed == false) {
              try {
                audioStreamController.add(Uint8List.fromList(message));
              } catch (e) {}
            }
            audioBuffer.addAll(message);
          }
          logProgressIfNeeded();
        }
      }
      if (!gotHello) {
        throw Exception('Did not receive tts-hello');
      }
      if (audioBuffer.isEmpty) {
        throw Exception('No audio data received');
      }
      if (playbackFuture != null) {
        await completionTracker
            .waitForBothDone(); // Event-driven, no artificial timeout
      } else {
        String fallbackReason = 'Audio too small for streaming';
        if (audioBuffer.length >= bufferSize &&
            !_isValidAudioHeader(
                audioBuffer, requestedFormat, currentMimeType)) {
          fallbackReason = 'Invalid audio header detected';
        } else if (originalHeaderInfo == null &&
            audioBuffer.length >= bufferSize) {
          fallbackReason = 'Audio header parsing failed';
        }
        TTSStreamingMonitor().recordFallbackToFullBuffer(fallbackReason);
        Uint8List fallbackAudioData;
        if (requestedFormat.toLowerCase() == 'opus') {
          fallbackAudioData = Uint8List.fromList(audioBuffer);
        } else if (requestedFormat.toLowerCase() == 'mp3' || requestedFormat.toLowerCase() == 'mpeg') {
          fallbackAudioData = Uint8List.fromList(audioBuffer);
        } else {
          if (originalHeaderInfo != null) {
            final streamingHeader =
                WavHeaderUtils.createStreamingHeader(originalHeaderInfo);
            final pcmData =
                WavHeaderUtils.extractPcmData(audioBuffer, originalHeaderInfo);
            fallbackAudioData =
                WavHeaderUtils.combineHeaderAndPcm(streamingHeader, pcmData);
          } else {
            fallbackAudioData = Uint8List.fromList(audioBuffer);
          }
        }
        await _audioPlayerManager.playAudioBytes(
          fallbackAudioData,
          debugName: 'tts_fallback_${req.id}',
          mimeType: currentMimeType,
        );
      }
    } catch (e) {
      audioStreamController?.close();
      // CRITICAL: Clean up LiveTtsAudioSource on error
      liveAudioSource?.dispose();
      if (_activeLiveAudioSource == liveAudioSource) {
        _activeLiveAudioSource = null;
      }
      completionTracker.dispose();
      final currentFormat = AudioFormatNegotiator.getCurrentFormat();
      if ((currentFormat == AudioFormat.opus ||
              currentFormat == AudioFormat.native) &&
          !playbackStarted &&
          audioBuffer.length < 65536) {
        AudioFormatNegotiator.enableEmergencyFallback(
            'OPUS streaming failed: $e');
        try {
          final wsUrl = '$_backendUrl/ws/tts'.replaceFirst('http', 'ws');
          final retryWs = await _getConnection(wsUrl);
          final retryCompletionTracker = TwoPhaseCompletion();
          retryCompletionTracker.setStopPlayerCallback(() async {
            await _audioPlayerManager.stopAudio();
          });
          await _processResponseFullBuffer(
              req, retryWs, retryCompletionTracker);
          await retryWs.sink.close();
          return; // Success - don't rethrow
        } catch (fallbackError) {
          final ttsException =
              _convertToTtsException(fallbackError, 'WAV fallback');
        }
      }
      final ttsException = _convertToTtsException(e, 'TTS streaming');
      throw ttsException;
    } finally {
      completionTracker.dispose();
      // CRITICAL: Clean up LiveTtsAudioSource resources
      liveAudioSource?.dispose();
      if (_activeLiveAudioSource == liveAudioSource) {
        _activeLiveAudioSource = null;
      }
    }
  }
  bool _isValidAudioHeader(List<int> chunk, String format, String? mimeType) {
    switch (format.toLowerCase()) {
      case 'native':
        return _isValidNativeHeader(chunk, mimeType);
      case 'opus':
      case 'ogg':
      case 'ogg_opus':
        return _isValidOpusHeader(chunk);
      case 'mp3':
      case 'mpeg':
        return _isValidMp3Header(chunk);
      case 'wav':
      default:
        return _isValidWavHeader(chunk);
    }
  }
  bool _isValidNativeHeader(List<int> chunk, String? mimeType) {
    final lowerMime = mimeType?.toLowerCase() ?? '';
    if (lowerMime.contains('ogg') || lowerMime.contains('opus')) {
      return _isValidOpusHeader(chunk);
    }
    if (lowerMime.contains('wav') ||
        lowerMime.contains('pcm') ||
        lowerMime.contains('l16')) {
      return _isValidWavHeader(chunk);
    }
    if (_isValidOpusHeader(chunk)) {
      return true;
    }
    return _isValidWavHeader(chunk);
  }
  bool _isValidOpusHeader(List<int> chunk) {
    if (chunk.length < OpusHeaderUtils.minHeaderBufferSize) {
      return false;
    }
    if (OpusHeaderUtils.isOpusFormat(chunk)) {
      return true;
    }
    final oggSignature = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
    final searchLimit = chunk.length.clamp(0, 64);
    for (int i = 1; i < searchLimit - 3; i++) {
      bool found = true;
      for (int j = 0; j < 4; j++) {
        if (chunk[i + j] != oggSignature[j]) {
          found = false;
          break;
        }
      }
      if (found) {
        return true;
      }
    }
    return false;
  }
  bool _isValidWavHeader(List<int> chunk) {
    if (chunk.length < 12) {
      return false;
    }
    try {
      return chunk[0] == 0x52 && // R
          chunk[1] == 0x49 && // I
          chunk[2] == 0x46 && // F
          chunk[3] == 0x46 && // F
          chunk[8] == 0x57 && // W
          chunk[9] == 0x41 && // A
          chunk[10] == 0x56 && // V
          chunk[11] == 0x45; // E
    } catch (e) {
      return false;
    }
  }
  bool _isValidMp3Header(List<int> chunk) {
    if (chunk.length < 3) {
      return false;
    }
    try {
      if (chunk[0] == 0x49 && chunk[1] == 0x44 && chunk[2] == 0x33) {
        return true; // ID3
      }
      if (chunk[0] == 0xFF && (chunk[1] & 0xE0) == 0xE0) {
        return true; // MPEG sync
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  Future<void> _processResponseFullBuffer(TtsRequest req, WebSocketChannel ws,
      TwoPhaseCompletion completionTracker) async {
    final audioBuffer = <int>[];
    const int progressLogStepBytes = 131072;
    int progressLogCount = 0;
    int lastProgressLogBytes = 0;
    void logProgressIfNeeded() {
      if (!kDebugMode) return;
      final total = audioBuffer.length;
      final delta = total - lastProgressLogBytes;
      final shouldLogEarly = progressLogCount < 2;
      if (!shouldLogEarly && delta < progressLogStepBytes) {
        return;
      }
      _ttsTrace('🎯 [TTS] Streaming progress: $total bytes for ${req.id}');
      progressLogCount++;
      lastProgressLogBytes = total;
    }
    bool gotHello = false;
    final requestedFormat = req.format;
    String currentMimeType =
        AudioFormatNegotiator.getMimeTypeForFormat(requestedFormat);
    final contentType = currentMimeType;
    final handshakeMessage = {
      'text': req.text,
      'voice': req.voice,
      'params': {
        'response_format': requestedFormat,
        'mime_type': currentMimeType,
      }, // Request format directly
      'session_id': req.id,
      'client_version': '1.9.0',
      'format': requestedFormat, // Direct format specification
      'mode': LLMConfig.activeTTSMode,
      'provider': LLMConfig.activeTTSProvider.name,
      'opus_params': requestedFormat == 'opus'
          ? {
              'sample_rate': AudioFormatConfig.opusSampleRate,
              'channels': AudioFormatConfig.opusChannels,
              'bitrate': AudioFormatConfig.opusBitrate,
            }
          : null,
    };
    ws.sink.add(jsonEncode(handshakeMessage));
    await for (final message in ws.stream) {
      if (message is String) {
        final data = jsonDecode(message);
        final type = data['type'];
        if (type == 'tts-hello') {
          gotHello = true;
          if (kDebugMode) _ttsTrace('🔍 [TTS] Got tts-hello for ${req.id}');
        } else if (type == 'tts-done') {
          final serverMime = data['mime_type'] as String?;
          if (serverMime != null && serverMime.isNotEmpty) {
            currentMimeType = serverMime;
          }
          if (kDebugMode) _ttsTrace('🔍 [TTS] Got tts-done for ${req.id}');
          break; // Exit the await for loop
        } else if (type == 'error') {
          final errorDetail = data['detail'] ?? 'TTS error';
          throw TtsNetworkException('TTS service error', errorDetail);
        }
      } else if (message is List<int>) {
        audioBuffer.addAll(message);
        logProgressIfNeeded();
      }
    }
    if (!gotHello) {
      throw Exception('Did not receive tts-hello');
    }
    if (audioBuffer.isEmpty) {
      throw Exception('No audio data received');
    }
    completionTracker.setSafetyWatchdog(audioBuffer.length);
    if (req.makeBackupFile) {
      final audioFile =
          await _saveAudioBuffer(audioBuffer, req.format, currentMimeType);
      try {
        await _audioPlayerManager.playAudio(audioFile.path);
      } catch (audioError) {
        rethrow;
      }
      // Note: Temp file cleanup is now handled by AudioPlayerManager after playback completion
    } else if (kTTSUseInMemoryPlayback && audioBuffer.isNotEmpty) {
      try {
        await _audioPlayerManager.playAudioBytes(
          Uint8List.fromList(audioBuffer),
          debugName: 'tts_${req.id}',
          mimeType: currentMimeType,
        );
      } catch (audioError) {
        final audioFile =
            await _saveAudioBuffer(audioBuffer, req.format, currentMimeType);
        await _audioPlayerManager.playAudio(audioFile.path);
      }
    } else {
    }
  }
  Future<io.File> _saveAudioBuffer(
      List<int> audioBuffer, String format, String mimeType) async {
    final ext = _determineFileExtension(format, mimeType);
    final fileId = AudioPathUtils.generateTimestampId('tts');
    final filePath = PathManager.instance.ttsFile(fileId, ext);
    final file = io.File(filePath);
    await file.writeAsBytes(audioBuffer);
    return file;
  }
  String _determineFileExtension(String format, String mimeType) {
    final lowerMime = mimeType.toLowerCase();
    if (lowerMime.contains('ogg') || lowerMime.contains('opus')) {
      return 'ogg';
    }
    if (lowerMime.contains('mp3')) {
      return 'mp3';
    }
    if (lowerMime.contains('aac')) {
      return 'aac';
    }
    if (lowerMime.contains('wav') ||
        lowerMime.contains('pcm') ||
        lowerMime.contains('l16')) {
      return 'wav';
    }
    switch (format.toLowerCase()) {
      case 'opus':
      case 'native':
        return 'ogg';
      case 'mp3':
      case 'mpeg':
        return 'mp3';
      case 'wav':
      default:
        return 'wav';
    }
  }
  // -------- ITTSService Interface (Minimal Implementation) -----------
  @override
  Future<void> initialize() async {
  }
  @override
  Future<String> generateSpeech(String text, {String? voice}) async {
    throw UnimplementedError('Use speak() method instead');
  }
  @override
  Future<void> streamAndPlayTTS(
    String text, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  }) async {
    try {
      await speak(text);
      onDone?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }
  @override
  Future<void> streamAndPlayTTSChunked(
    Stream<String> textStream, {
    void Function()? onDone,
    void Function(String)? onError,
    void Function(double)? onProgress,
    String? sessionId,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in textStream) {
      buffer.write(chunk);
    }
    try {
      await speak(buffer.toString());
      onDone?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }
  @override
  Future<void> playAudio(String audioPath) async {
    await _audioPlayerManager.playAudio(audioPath);
  }
  @override
  Future<void> stopAudio() async {
    await _audioPlayerManager.stopAudio();
  }
  @override
  Future<void> pauseAudio() async {
    await _audioPlayerManager.stopAudio();
  }
  @override
  Future<void> cancelAllStreams() async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) _ttsTrace('🚨 [TTS] Starting stream cancellation...');
    try {
      await Future.any([
        _actualCancellation(),
        Future.delayed(const Duration(seconds: 3)).then((_) =>
            throw TimeoutException(
                'Cancellation timeout', const Duration(seconds: 3)))
      ]);
      final elapsed = stopwatch.elapsedMilliseconds;
      if (kDebugMode) _ttsTrace('✅ [TTS] Streams cancelled in ${elapsed}ms');
      if (elapsed > 500) {
      }
    } catch (e) {
      final elapsed = stopwatch.elapsedMilliseconds;
      await _emergencyCleanup();
    }
  }
  Future<void> _actualCancellation() async {
    await _audioPlayerManager.stopAudio();
    if (_activeLiveAudioSource != null) {
      _activeLiveAudioSource?.dispose();
      _activeLiveAudioSource = null;
    }
    if (_activeCompletionTracker != null) {
      _activeCompletionTracker?.dispose();
      _activeCompletionTracker = null;
    }
    _queue.clear();
    _pendingStreams = 0;
    _updateSpeakingState(false);
  }
  Future<void> _emergencyCleanup() async {
    try {
      await _audioPlayerManager.stopAudio();
      _activeLiveAudioSource?.dispose();
      _activeLiveAudioSource = null;
      _updateSpeakingState(false);
      _queue.clear();
      _pendingStreams = 0;
      if (kDebugMode) _ttsTrace('✅ [TTS] Emergency cleanup completed');
    } catch (e) {
      final ttsException = _convertToTtsException(e, 'Emergency cleanup');
    }
  }
  @override
  Future<void> resumeAudio() async {
  }
  @override
  bool get isPlaying => _audioPlayerManager.isPlaying;
  @override
  bool get isSpeaking => _state != _State.idle;
  @override
  bool get hasPendingOrActiveTts =>
      _queue.isNotEmpty || _state != _State.idle || _pendingStreams > 0;
  @override
  Stream<bool> get playbackStateStream => _audioPlayerManager.isPlayingStream;
  @override
  Stream<bool> get speakingStateStream => _speakingStateController.stream;
  @override
  void setVoiceSettings(String voice, double speed, double pitch) {
  }
  @override
  void setAudioFormat(String format) {
  }
  @override
  void resetTTSState() {
    if (_queue.isNotEmpty || _state != _State.idle || _pendingStreams > 0) {
      return;
    }
    _activeCompletionTracker?.dispose();
    _activeCompletionTracker = null;
    if (_activeLiveAudioSource != null) {
      _activeLiveAudioSource?.dispose();
      _activeLiveAudioSource = null;
    }
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (!req.done.isCompleted) {
        req.completeError(Exception('TTS reset - request cancelled'));
      }
    }
    _pendingStreams = 0;
    _state = _State.idle;
    _notifyTTSEnd();
    _fireCompletionSafely(false);
    if (!_speakingStateController.isClosed) {
      _speakingStateController.add(false);
    }
  }
  @override
  void setAiSpeaking(bool speaking) {
  }
  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    return null;
  }
  @override
  Future<void> cleanupAudioFiles() async {
  }
  void _updateSpeakingState(bool newState) {
    if (newState != _lastSpeakingState) {
      _lastSpeakingState = newState;
      if (!_speakingStateController.isClosed) {
        _speakingStateController.add(newState);
      }
    }
  }
  void _notifyTTSStart() {
    _updateSpeakingState(true);
    if (_voiceServiceUpdateCallback != null) {
      scheduleMicrotask(() {
        _voiceServiceUpdateCallback!(true);
      });
    }
  }
  void _notifyTTSEnd() {
    _updateSpeakingState(false);
    if (_voiceServiceUpdateCallback != null) {
      scheduleMicrotask(() {
        _voiceServiceUpdateCallback!(false);
      });
    }
  }
  void _fireCompletionSafely(bool isSpeaking) {
    if (_onTTSComplete != null) {
      scheduleMicrotask(() {
        _onTTSComplete!(isSpeaking);
      });
    }
  }
  void _scheduleControllerClosureCheck(
      StreamController<Uint8List>? controller, LiveTtsAudioSource? source) {
    if (controller == null || source == null) return;
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // FIX: Remove circular dependency - close when WebSocket is done
      final shouldClose = controller.isClosed || source.isWebSocketClosed;
      if (shouldClose) {
        timer.cancel();
        if (!controller.isClosed) {
          try {
            controller.close();
          } catch (e) {}
        }
      }
      if (timer.tick > 600) {
        timer.cancel();
        if (!controller.isClosed) {
          try {
            controller.close();
          } catch (e) {}
        }
      }
    });
  }
  TtsException _convertToTtsException(Object error, String context) {
    if (error is TtsException) {
      return error; // Already structured
    }
    return error.toTtsException(context);
  }
  String _getCallerInfo() {
    try {
      final trace = StackTrace.current.toString();
      final lines = trace.split('\n');
      for (final line in lines) {
        if (line.contains('simple_tts_service.dart')) continue;
        if (line.contains('VoiceSessionBloc')) return 'VoiceSessionBloc';
        if (line.contains('AudioGenerator')) return 'AudioGenerator';
        if (line.contains('TherapyService')) return 'TherapyService';
        if (line.contains('VoiceSessionCoordinator')) {
          return 'VoiceSessionCoordinator';
        }
        if (line.contains('DependencyContainer')) {
          return 'DependencyContainer.direct';
        }
        if (line.contains('_onPlayWelcomeMessage')) {
          return 'VoiceSessionBloc.welcomeMessage';
        }
      }
      return 'Unknown';
    } catch (e) {
      return 'Error-getting-caller';
    }
  }
  @override
  void dispose() {
    if (_disposeCompleter != null) {
      return; // Another dispose is already running
    }
    if (_disposed) return;
    _disposed = true;
    _disposeCompleter = Completer<void>();
    try {
      while (_queue.isNotEmpty) {
        final req = _queue.removeFirst();
        req.completeError(Exception('Service disposed'));
      }
      _notifyTTSEnd();
      _fireCompletionSafely(false);
      _activeCompletionTracker?.dispose();
      _activeCompletionTracker = null;
      _cleanupPrewarmedConnection();
      // CRITICAL: Dispose AudioPlayerManager to release audio resources
      try {
        _audioPlayerManager.disposeAsync();
      } catch (e) {}
      if (!_speakingStateController.isClosed) {
        _speakingStateController.close();
      }
      if (kDebugMode) _ttsTrace('🔍 [TTS] Service disposed');
      _disposeCompleter?.complete();
    } catch (e) {
      if (kDebugMode) _ttsTrace('❌ [TTS] Error during dispose: $e');
      _disposeCompleter?.completeError(e);
    }
  }
}
enum _State { idle, connecting, streaming }
