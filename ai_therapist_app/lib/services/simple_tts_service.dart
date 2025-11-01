// lib/services/simple_tts_service.dart

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/tts_request.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_audio_settings.dart';
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

/// Feature flag to enable in-memory TTS playback (eliminates temp WAV files)
/// Set to true to avoid writing ~1 MiB temp files per TTS response
const bool kTTSUseInMemoryPlayback = true;

/// Single-owner TTS service following best-in-class production patterns
///
/// This service exclusively owns:
/// - The WebSocket connection to TTS backend (one per request)
/// - The AudioPlayerManager for playback
/// - The request queue for serialization
///
/// All callers simply await ttsService.speak(text) without thinking about sockets.
class SimpleTTSService implements ITTSService {
  // -------- Log Suppression Flags ------------------------------------

  /// Static flag to suppress repeated format mismatch logging
  static bool _formatMismatchLogged = false;

  // -------- Public API -----------------------------------------------

  /// Speak text and return when playback is complete
  /// This is the ONLY public method callers need
  @override
  Future<void> speak(
    String text, {
    String? voice,
    String format = 'auto', // Let negotiator determine optimal format
    bool makeBackupFile = true,
  }) async {
    if (text.trim().isEmpty) {
      if (kDebugMode) debugPrint('❌ [TTS] Empty text, skipping');
      return;
    }

    // 🔍 TTS DUPLICATION TRACKING
    final caller = _getCallerInfo();
    final selectedVoice = voice ?? LLMConfig.activeTTSVoice;

    if (kDebugMode) {
      // Log pending as the value after this request is added (prevents negative display)
      final pendingDisplay = (_pendingStreams < 0 ? 0 : _pendingStreams) + 1;
      debugPrint('🎯 [TTS-TRACK] speak() called by: $caller');
      debugPrint(
          '🎯 [TTS-TRACK] Text: "${text.substring(0, text.length.clamp(0, 50))}${text.length > 50 ? "..." : ""}"');
      debugPrint('🎯 [TTS-TRACK] Voice: $selectedVoice, Format: $format');
      debugPrint(
          '🎯 [TTS-TRACK] Current queue size: ${_queue.length}, Pending: $pendingDisplay');
    }

    // Refresh negotiator with latest backend overrides (supports live/native toggles)
    AudioFormatNegotiator.updateFromConfig();

    if (kDebugMode) {
      debugPrint(
          '🎯 [TTS] Active provider=${LLMConfig.activeTTSProvider.name}, mode=${LLMConfig.activeTTSMode}, formatPref=${AudioFormatNegotiator.getPreferredFormat().name}');
    }

    // Determine optimal format - prefer backend negotiated option
    final optimalFormat =
        format == 'auto' ? AudioFormatNegotiator.getBackendFormat() : format;

    final req = TtsRequest(
      text: text.trim(),
      voice: selectedVoice,
      format: optimalFormat,
      makeBackupFile: makeBackupFile,
    );
    _queue.add(req);
    _pendingStreams++; // Track this TTS request

    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] Queued request: ${req.id} (queue length: ${_queue.length}, pending: $_pendingStreams, backup: ${req.makeBackupFile})');
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

  // TIMING FIX: Callback to get current generation for completion checks
  int Function()? _getCurrentGenerationCallback;

  // Production-grade completion tracking
  int _pendingStreams = 0; // Monotonic counter for overlapping instances

  // Active LiveTtsAudioSource for emergency cleanup
  LiveTtsAudioSource? _activeLiveAudioSource;

  // Phase 1: Event-driven speaking state stream
  late final StreamController<bool> _speakingStateController;
  bool _lastSpeakingState = false;

  _State _state = _State.idle;
  late String _backendUrl;
  bool _disposed = false;

  // Dispose chain mutex to prevent overlapping dispose operations
  Completer<void>? _disposeCompleter;

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
    // Verify AudioPlayerManager has AudioSettings for mute functionality
    if (kDebugMode && audioSettings != null && audioPlayerManager != null) {
      debugPrint(
          '🔊 SimpleTTSService: Using provided AudioPlayerManager with global mute support');
    } else if (kDebugMode && audioSettings != null) {
      debugPrint(
          '🔊 SimpleTTSService: Created AudioPlayerManager with AudioSettings for mute support');
    }
    _backendUrl = AppConfig().backendUrl;
    // Phase 1: Initialize broadcast stream controller for speaking state
    _speakingStateController = StreamController<bool>.broadcast(sync: true);

    // Initialize audio format negotiation
    AudioFormatNegotiator.initialize();
  }

  /// Set the TTS completion callback (for wiring to AudioGenerator)
  void setCompletionCallback(void Function(bool isSpeaking)? callback) {
    _onTTSComplete = callback;
    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] Completion callback ${callback != null ? 'set' : 'cleared'}');
    }
  }

  /// Set the VoiceService update callback (for TTS-VAD coordination)
  void setVoiceServiceUpdateCallback(
      void Function(bool isSpeaking, {int? playbackToken})? callback) {
    _voiceServiceUpdateCallback = callback;
    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] VoiceService update callback ${callback != null ? 'set' : 'cleared'}');
    }
  }

  /// Set the generation callback (for TTS completion timing checks)
  void setGetCurrentGenerationCallback(int Function()? callback) {
    _getCurrentGenerationCallback = callback;
    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] Generation callback ${callback != null ? 'set' : 'cleared'}');
    }
  }

  Future<void> _pumpQueue() async {
    if (_state != _State.idle || _queue.isEmpty || _disposed) return;

    final req = _queue.removeFirst();
    if (kDebugMode) {
      debugPrint('🔍 [TTS] Processing request: ${req.id}');
    }

    WebSocketChannel? ws;
    try {
      _state = _State.connecting;

      // CRITICAL: Notify that TTS is starting BEFORE WebSocket connection
      // This prevents Maya from listening to herself during TTS
      _notifyTTSStart();

      // Create fresh WebSocket for this request (simple pattern)
      final wsUrl = '$_backendUrl/ws/tts'.replaceFirst('http', 'ws');
      if (kDebugMode) {
        debugPrint('🔍 [TTS] Creating WebSocket connection to: $wsUrl');
      }

      ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _state = _State.streaming;

      // Create event-driven completion tracker for this request
      final completionTracker = TwoPhaseCompletion();

      // Initialize with audio player for event-driven completion
      completionTracker.initializeWithPlayer(_audioPlayerManager.audioPlayer);

      // Set up callbacks
      completionTracker.setStopPlayerCallback(() async {
        await _audioPlayerManager.stopAudio();
      });

      completionTracker.setPlaybackFinishedCallback(() {
        _notifyTTSEnd(); // Signal TTS completion
        _fireCompletionSafely(false); // Reset speaking state
      });

      // Note: VAD restart will be handled by VoiceSessionBloc when it receives TTS completion

      // Process TTS request with fresh connection
      await _processResponse(req, ws, completionTracker);

      req.complete();
      if (kDebugMode) {
        debugPrint('✅ [TTS] Completed request: ${req.id}');
      }
    } catch (e, stackTrace) {
      final ttsException = _convertToTtsException(e, 'TTS request processing');
      if (kDebugMode) {
        debugPrint(
            '❌ [TTS] Request failed: ${req.id} - ${ttsException.message}');
      }
      req.completeError(ttsException, stackTrace);
      _notifyTTSEnd(); // Reset TTS state on ANY error
      _fireCompletionSafely(false);
    } finally {
      // CRITICAL: Always close WebSocket, even on error (prevents resource leaks)
      if (ws != null) {
        try {
          await ws.sink.close();
          // Wait for the TCP FIN to be observed (robust cleanup)
          await ws.sink.done;
          if (kDebugMode) debugPrint('🔍 [TTS] WebSocket closed for ${req.id}');
        } catch (closeError) {
          // Guard against close() throwing on already-closed channels
          final ttsException =
              _convertToTtsException(closeError, 'WebSocket cleanup');
          if (kDebugMode) {
            debugPrint(
                '⚠️ [TTS] WebSocket close error (already closed?): ${ttsException.message}');
          }
        }
      }

      // Decrement when done (success or error) and clamp to zero
      if (_pendingStreams > 0) {
        _pendingStreams--;
      } else {
        _pendingStreams = 0;
      }
      if (kDebugMode) {
        debugPrint('🔍 [TTS] Pending streams decremented to: $_pendingStreams');
      }

      // Only fire completion when ALL streams are done
      if (_pendingStreams <= 0) {
        _notifyTTSEnd();
        _fireCompletionSafely(false);
      }

      _state = _State.idle;
      // Tail-recursion: pump next job
      _pumpQueue();
    }
  }

  Future<void> _processResponse(TtsRequest req, WebSocketChannel ws,
      TwoPhaseCompletion completionTracker) async {
    // Check if streaming is enabled and buffer size allows for streaming
    final streamingEnabled = TTSStreamingConfig.shouldUseStreaming;
    final requestedFormat = req.format;
    if (kDebugMode) {
      debugPrint(
          '🎯 [TTS] Request ${req.id} -> provider=${LLMConfig.activeTTSProvider.name}, mode=${LLMConfig.activeTTSMode}, requestedFormat=$requestedFormat');
    }

    // Use format-aware buffer size for optimal latency
    final bufferSize = _getOptimalBufferSize(requestedFormat);

    if (kDebugMode) {
      debugPrint(
          '🎯 [TTS] Processing ${req.id}: streaming=${streamingEnabled ? "enabled" : "disabled"}, format=$requestedFormat, bufferSize=$bufferSize');
      debugPrint('🎯 Format-aware Config:');
      debugPrint('  Requested Format: $requestedFormat');
      debugPrint(
          '  Buffer Size: $bufferSize bytes (${(bufferSize / 1024).toStringAsFixed(1)} KB)');
      debugPrint(
          '  Buffer Description: ${requestedFormat.toLowerCase() == "opus" ? "Low-latency OPUS (8KB)" : "Conservative WAV (32KB)"}');
      if (requestedFormat.toLowerCase() == "opus") {
        debugPrint(
            '  🚀 OPUS STREAMING ACTIVE - Will start playback after ${(bufferSize / 1024).toStringAsFixed(1)}KB');
      } else {
        debugPrint(
            '  🔄 WAV STREAMING ACTIVE - Will start playback after ${(bufferSize / 1024).toStringAsFixed(1)}KB');
      }
    }

    // ZERO RISK IMPLEMENTATION: Choose path based on configuration
    if (streamingEnabled) {
      // NEW STREAMING PATH: Progressive streaming with buffer threshold
      await _processResponseStreaming(req, ws, bufferSize, completionTracker);
    } else {
      // EXISTING FULL-BUFFER PATH: Unchanged for safety
      await _processResponseFullBuffer(req, ws, completionTracker);
    }
  }

  /// Get optimal buffer size based on audio format
  /// Both OPUS and WAV: 8KB for aggressive low-latency streaming
  int _getOptimalBufferSize(String format) {
    switch (format.toLowerCase()) {
      case 'opus':
        return 8192; // 8KB - OPUS is designed for low-latency streaming
      case 'wav':
      default:
        return 8192; // 8KB - Aggressive threshold for faster time-to-first-audio
    }
  }

  /// NEW: Streaming response processing with progressive playback
  Future<void> _processResponseStreaming(TtsRequest req, WebSocketChannel ws,
      int bufferSize, TwoPhaseCompletion completionTracker) async {
    final startTime = DateTime.now();
    DateTime? firstAudioTime;
    DateTime? playbackStartTime;

    if (kDebugMode) {
      debugPrint(
          '🚀 [TTS] Using STREAMING path for ${req.id} (threshold: $bufferSize bytes)');
    }

    final audioBuffer = <int>[];
    bool gotHello = false;
    bool playbackStarted = false;
    StreamController<Uint8List>? audioStreamController;
    WavHeaderInfo? originalHeaderInfo;
    // CRITICAL: Track LiveTtsAudioSource for proper lifecycle management
    LiveTtsAudioSource? liveAudioSource;

    try {
      // Use the requested format directly (no negotiation needed)
      final requestedFormat = req.format;
      String currentMimeType =
          AudioFormatNegotiator.getMimeTypeForFormat(requestedFormat);
      final contentType = currentMimeType;

      if (kDebugMode) {
        debugPrint(
            '🎯 [TTS] Direct format request: ${req.format}, contentType=$contentType');
        AudioFormatNegotiator.logCurrentConfiguration();
      }

      // Build handshake message - request specific format directly
      final handshakeMessage = {
        'text': req.text,
        'voice': req.voice,
        'params': {
          'response_format': requestedFormat,
          'mime_type': currentMimeType,
        }, // Request format directly
        'session_id': req.id,
        // Direct format request (no negotiation)
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

      // Create broadcast stream controller for live TTS streaming
      // CRITICAL: Must be broadcast to support just_audio's multiple listeners
      audioStreamController = StreamController<Uint8List>.broadcast(sync: true);

      // Start live streaming immediately (no buffer required)
      Future<void>? playbackFuture;

      // Listen for response (streaming pattern)
      await for (final message in ws.stream) {
        if (message is String) {
          final data = jsonDecode(message);
          final type = data['type'];

          if (type == 'tts-hello') {
            gotHello = true;
            if (kDebugMode) {
              debugPrint('🎯 [TTS] Got tts-hello for ${req.id} (streaming)');
            }
          } else if (type == 'tts-done') {
            final totalSize = data['total_size'] as int?;
            final serverMime = data['mime_type'] as String?;
            if (serverMime != null && serverMime.isNotEmpty) {
              currentMimeType = serverMime;
            }
            if (kDebugMode) {
              debugPrint(
                  '🎯 [TTS] Got tts-done for ${req.id} (streaming) with total_size: $totalSize');
            }
            // CRITICAL: Mark WebSocket phase complete but DON'T close stream yet
            completionTracker.markWebSocketDone();
            // CRITICAL: Mark WebSocket as closed in LiveTtsAudioSource with content size for ExoPlayer completion
            liveAudioSource?.markWebSocketClosed(totalSize);

            // CRITICAL: Don't close the stream immediately - let LiveTtsAudioSource drain data
            // The controller will be closed when both conditions are met:
            // 1. WebSocket is closed (already marked above)
            // 2. LiveTtsAudioSource has processed all data
            if (kDebugMode) {
              debugPrint(
                  '🔌 [TTS] WebSocket done, stream controller will close when LiveTtsAudioSource finishes draining');
            }

            // Schedule a state-based check to close the controller when conditions are right
            _scheduleControllerClosureCheck(
                audioStreamController, liveAudioSource);
            break;
          } else if (type == 'error') {
            final errorDetail = data['detail'] ?? 'TTS error';
            throw TtsNetworkException('TTS service error', errorDetail);
          }
        } else if (message is List<int>) {
          // Record first audio chunk timing
          firstAudioTime ??= DateTime.now();

          // PHASE 1: Accumulate chunks until we have enough for streaming setup
          if (!playbackStarted) {
            audioBuffer.addAll(message);

            // Check if we have enough data to start streaming
            if (gotHello &&
                audioBuffer.length >= bufferSize && // Format-aware buffer size
                _isValidAudioHeader(
                    audioBuffer, requestedFormat, currentMimeType)) {
              // Validate headers based on format

              playbackStarted =
                  true; // CRITICAL: Set flag immediately to prevent multiple starts
              playbackStartTime =
                  DateTime.now(); // Record playback start timing

              if (kDebugMode) {
                debugPrint(
                    '🚀 [TTS] Starting live TTS streaming for ${req.id} (${audioBuffer.length} bytes accumulated)');
              }

              // CRITICAL: Hard-gate WAV vs OPUS processing
              Uint8List streamingAudioData;

              if (requestedFormat.toLowerCase() == 'opus') {
                // OPUS: Push bytes straight through without any header modification
                streamingAudioData = Uint8List.fromList(audioBuffer);
                if (kDebugMode) {
                  debugPrint(
                      '🎵 [TTS] OPUS: Using original data directly (${streamingAudioData.length} bytes)');
                }
              } else {
                // WAV: Apply header modification logic
                final bool alreadyStreamingFriendly =
                    WavHeaderUtils.isStreamingFriendly(audioBuffer);

                if (alreadyStreamingFriendly) {
                  // Keep original streaming-friendly headers untouched
                  streamingAudioData = Uint8List.fromList(audioBuffer);
                } else {
                  // Headers need modification for streaming compatibility
                  originalHeaderInfo =
                      WavHeaderUtils.parseWavHeader(audioBuffer);

                  if (originalHeaderInfo != null) {
                    if (kDebugMode) {
                      debugPrint(
                          '🔧 [TTS] Modifying finite-size headers for unlimited streaming: $originalHeaderInfo');
                    }

                    // Create streaming header with placeholder size
                    final streamingHeader =
                        WavHeaderUtils.createStreamingHeader(
                            originalHeaderInfo);

                    // Extract PCM data from original audio
                    final pcmData = WavHeaderUtils.extractPcmData(
                        audioBuffer, originalHeaderInfo);

                    // Combine streaming header with PCM data
                    streamingAudioData = WavHeaderUtils.combineHeaderAndPcm(
                        streamingHeader, pcmData);

                    if (kDebugMode) {
                      debugPrint(
                          '✅ [TTS] Created streaming audio: header=${streamingHeader.length}B, PCM=${pcmData.length}B, total=${streamingAudioData.length}B');
                    }
                  } else {
                    // Fallback: use original data if header parsing fails
                    if (kDebugMode) {
                      debugPrint(
                          '⚠️ [TTS] Could not parse WAV header, using original data as fallback');
                    }
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

              // Track active source for emergency cleanup
              _activeLiveAudioSource = liveAudioSource;

              // CRITICAL FIX: Add initial data BEFORE setAudioSource() call
              // ExoPlayer calls request() synchronously inside setAudioSource(), so data must be ready!
              if (audioStreamController.isClosed == false) {
                try {
                  audioStreamController.add(streamingAudioData);
                  if (kDebugMode) {
                    debugPrint(
                        '📊 [TTS] Added initial streaming data BEFORE player setup: ${streamingAudioData.length} bytes');
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint(
                        '⚠️ [TTS] Error adding initial streaming data: $e');
                  }
                }
              }

              // TIMING FIX: Capture generation when TTS starts (not when it completes)
              final genAtStart = _getCurrentGenerationCallback?.call() ?? -1;

              // NOW start live TTS streaming setup (ExoPlayer will find data ready)
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
                  // TIMING FIX: Check if mode changed since TTS started
                  if (_getCurrentGenerationCallback?.call() != genAtStart) {
                    // Allow welcome messages (generation -1) to complete regardless
                    if (genAtStart != -1) {
                      if (kDebugMode) {
                        debugPrint(
                            '[TTS] Generation mismatch – ignoring completion (was $genAtStart, now ${_getCurrentGenerationCallback?.call()})');
                      }
                      return; // ⛔ don't re-arm VAD
                    }
                    // Welcome messages (genAtStart == -1) are allowed through
                    if (kDebugMode) {
                      debugPrint(
                          '[TTS] Welcome message completion allowed despite generation change (was $genAtStart, now ${_getCurrentGenerationCallback?.call()})');
                    }
                  }

                  // Natural ExoPlayer completion - trigger VAD state transition immediately
                  if (kDebugMode) {
                    debugPrint(
                        '🎯 [TTS] Natural completion callback fired for ${req.id} - notifying VoiceService');
                  }
                  // ONLY notify VoiceService (VoiceSessionCoordinator or legacy VoiceService)
                  // This triggers VAD state transition - _onTTSComplete is for AudioGenerator, not VAD
                  _voiceServiceUpdateCallback?.call(
                    false,
                    playbackToken: playbackToken,
                  ); // Update VoiceService state for VAD coordination
                },
              ).then((_) {
                // Mark player phase complete when playback finishes
                completionTracker.markPlayerDone();
                if (kDebugMode) {
                  debugPrint('🎵 [TTS] Player phase completed for ${req.id}');
                }
              });
            }
          } else {
            // PHASE 2: Stream subsequent chunks directly (no header validation, no processing)
            // These are pure PCM chunks - feed them directly to the stream
            if (audioStreamController.isClosed == false) {
              try {
                audioStreamController.add(Uint8List.fromList(message));
                if (kDebugMode && message.isNotEmpty) {
                  debugPrintThrottledCustom(
                      '📊 [TTS] Streamed chunk: ${message.length} bytes (total buffered: ${audioBuffer.length})',
                      key: 'tts_chunk_streaming');
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('⚠️ [TTS] Error adding streaming chunk: $e');
                }
              }
            }
            // Continue accumulating for progress tracking (but don't use for streaming decisions)
            audioBuffer.addAll(message);
          }

          // Log progress at meaningful intervals
          if (kDebugMode && audioBuffer.length % 65536 == 0) {
            debugPrint(
                '🎯 [TTS] Streaming progress: ${audioBuffer.length} bytes for ${req.id}');
          }
        }
      }

      if (!gotHello) {
        throw Exception('Did not receive tts-hello');
      }

      if (audioBuffer.isEmpty) {
        throw Exception('No audio data received');
      }

      // Wait for BOTH phases to complete before returning
      if (playbackFuture != null) {
        // Wait for both WebSocket done AND player completion
        await completionTracker
            .waitForBothDone(); // Event-driven, no artificial timeout

        if (kDebugMode) {
          debugPrint(
              '✅ [TTS] Both phases completed for ${req.id} (${audioBuffer.length} total bytes)');
          _logLatencyMetrics(req.id, requestedFormat, startTime, firstAudioTime,
              playbackStartTime);
        }
      } else {
        // Fallback: if playback didn't start (small audio or header issues), use full buffer
        if (kDebugMode) {
          debugPrint(
              '🔄 [TTS] Streaming fallback to full buffer for ${req.id} (${audioBuffer.length} bytes)');
        }

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

        // Hard-gate WAV processing in fallback mode too
        Uint8List fallbackAudioData;
        if (requestedFormat.toLowerCase() == 'opus') {
          // OPUS: Use original data directly
          fallbackAudioData = Uint8List.fromList(audioBuffer);
          if (kDebugMode) {
            debugPrint(
                '🎵 [TTS] OPUS fallback: Using original data directly (${fallbackAudioData.length} bytes)');
          }
        } else {
          // WAV: Try to use modified headers for consistency
          if (originalHeaderInfo != null) {
            final streamingHeader =
                WavHeaderUtils.createStreamingHeader(originalHeaderInfo);
            final pcmData =
                WavHeaderUtils.extractPcmData(audioBuffer, originalHeaderInfo);
            fallbackAudioData =
                WavHeaderUtils.combineHeaderAndPcm(streamingHeader, pcmData);

            if (kDebugMode) {
              debugPrint(
                  '🔧 [TTS] Using modified headers in fallback mode: ${fallbackAudioData.length} bytes');
            }
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
      // Clean up stream controller on error
      audioStreamController?.close();
      // CRITICAL: Clean up LiveTtsAudioSource on error
      liveAudioSource?.dispose();
      // Clear active reference
      if (_activeLiveAudioSource == liveAudioSource) {
        _activeLiveAudioSource = null;
      }
      // Dispose completion tracker to prevent hanging
      completionTracker.dispose();

      // Graceful fallback for OPUS failures
      final currentFormat = AudioFormatNegotiator.getCurrentFormat();
      if ((currentFormat == AudioFormat.opus ||
              currentFormat == AudioFormat.native) &&
          !playbackStarted &&
          audioBuffer.length < 65536) {
        // Less than 64KB suggests early failure

        if (kDebugMode) {
          debugPrint(
              '🔄 [TTS] OPUS streaming failed early, attempting WAV fallback for ${req.id}: $e');
        }

        // Enable emergency WAV fallback
        AudioFormatNegotiator.enableEmergencyFallback(
            'OPUS streaming failed: $e');

        // Try again with WAV format (same WebSocket if still connected)
        try {
          if (kDebugMode) {
            debugPrint('🔄 [TTS] Retrying ${req.id} with WAV format');
          }

          // Create new WebSocket for retry
          final wsUrl = '$_backendUrl/ws/tts'.replaceFirst('http', 'ws');
          final retryWs = WebSocketChannel.connect(Uri.parse(wsUrl));

          // Use full buffer mode for WAV fallback (safer)
          // Create new completion tracker for retry
          final retryCompletionTracker = TwoPhaseCompletion();
          retryCompletionTracker.setStopPlayerCallback(() async {
            await _audioPlayerManager.stopAudio();
          });
          await _processResponseFullBuffer(
              req, retryWs, retryCompletionTracker);
          await retryWs.sink.close();

          if (kDebugMode) {
            debugPrint('✅ [TTS] WAV fallback succeeded for ${req.id}');
          }
          return; // Success - don't rethrow
        } catch (fallbackError) {
          final ttsException =
              _convertToTtsException(fallbackError, 'WAV fallback');
          if (kDebugMode) {
            debugPrint(
                '❌ [TTS] WAV fallback also failed for ${req.id}: ${ttsException.message}');
          }
          // Fall through to rethrow original error
        }
      }

      final ttsException = _convertToTtsException(e, 'TTS streaming');
      if (kDebugMode) {
        debugPrint(
            '❌ [TTS] Streaming error for ${req.id}: ${ttsException.message}');
      }
      throw ttsException;
    } finally {
      // Ensure cleanup
      completionTracker.dispose();
      // CRITICAL: Clean up LiveTtsAudioSource resources
      liveAudioSource?.dispose();
      // Clear active reference
      if (_activeLiveAudioSource == liveAudioSource) {
        _activeLiveAudioSource = null;
      }
    }
  }

  /// Validate audio header based on format
  /// Returns true if the chunk contains valid headers for the specified format
  bool _isValidAudioHeader(List<int> chunk, String format, String? mimeType) {
    switch (format.toLowerCase()) {
      case 'native':
        return _isValidNativeHeader(chunk, mimeType);
      case 'opus':
      case 'ogg':
      case 'ogg_opus':
        return _isValidOpusHeader(chunk);
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

    // Unknown native mime type: attempt OPUS first, then WAV as a fallback
    if (_isValidOpusHeader(chunk)) {
      return true;
    }

    return _isValidWavHeader(chunk);
  }

  /// Validate OPUS/OGG header for proper format detection
  /// Returns true if the chunk contains valid OGG/OPUS headers
  bool _isValidOpusHeader(List<int> chunk) {
    if (chunk.length < OpusHeaderUtils.minHeaderBufferSize) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ [TTS] Chunk too small for OPUS headers: ${chunk.length} bytes (need ${OpusHeaderUtils.minHeaderBufferSize})');
      }
      return false;
    }

    if (!OpusHeaderUtils.isOpusFormat(chunk)) {
      if (kDebugMode && !_formatMismatchLogged) {
        debugPrint(
            '⚠️ [TTS] Invalid OPUS/OGG format detected, fallback to full buffer');
        _formatMismatchLogged = true; // Suppress further format mismatch logs
      }
      return false;
    }

    // For streaming, we don't need complete headers immediately
    // Just verify it's valid OPUS format
    if (kDebugMode) {
      debugPrint('✅ [TTS] Valid OPUS format detected');
    }
    return true;
  }

  /// Validate WAV header for proper format detection
  /// Returns true if the chunk contains a valid RIFF/WAVE header
  /// Handles OpenAI streaming format where file size is unknown (0xFF bytes)
  bool _isValidWavHeader(List<int> chunk) {
    if (chunk.length < 12) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ [TTS] Chunk too small for WAV header: ${chunk.length} bytes');
      }
      return false;
    }

    try {
      // Check RIFF signature (bytes 0-3) and WAVE format (bytes 8-11)
      // Skip file size validation (bytes 4-7) as OpenAI streams use 0xFF for unknown size
      return chunk[0] == 0x52 && // R
          chunk[1] == 0x49 && // I
          chunk[2] == 0x46 && // F
          chunk[3] == 0x46 && // F
          chunk[8] == 0x57 && // W
          chunk[9] == 0x41 && // A
          chunk[10] == 0x56 && // V
          chunk[11] == 0x45; // E
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TTS] Error validating WAV header: $e');
      }
      return false;
    }
  }

  /// EXISTING: Full buffer response processing (unchanged for safety)
  Future<void> _processResponseFullBuffer(TtsRequest req, WebSocketChannel ws,
      TwoPhaseCompletion completionTracker) async {
    if (kDebugMode) {
      debugPrint('🔄 [TTS] Using FULL-BUFFER path for ${req.id} (safe mode)');
    }

    final audioBuffer = <int>[];
    bool gotHello = false;

    // Use the requested format directly (consistent with streaming path)
    final requestedFormat = req.format;
    String currentMimeType =
        AudioFormatNegotiator.getMimeTypeForFormat(requestedFormat);
    final contentType = currentMimeType;

    if (kDebugMode) {
      debugPrint(
          '🔄 [TTS] Full-buffer direct format request: ${req.format}, contentType=$contentType');
    }

    // Build handshake message - request specific format directly
    final handshakeMessage = {
      'text': req.text,
      'voice': req.voice,
      'params': {
        'response_format': requestedFormat,
        'mime_type': currentMimeType,
      }, // Request format directly
      'session_id': req.id,
      // Direct format request (no negotiation)
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

    // Listen for response (single subscription pattern)
    await for (final message in ws.stream) {
      if (message is String) {
        final data = jsonDecode(message);
        final type = data['type'];

        if (type == 'tts-hello') {
          gotHello = true;
          if (kDebugMode) debugPrint('🔍 [TTS] Got tts-hello for ${req.id}');
        } else if (type == 'tts-done') {
          final serverMime = data['mime_type'] as String?;
          if (serverMime != null && serverMime.isNotEmpty) {
            currentMimeType = serverMime;
          }
          if (kDebugMode) debugPrint('🔍 [TTS] Got tts-done for ${req.id}');
          break; // Exit the await for loop
        } else if (type == 'error') {
          final errorDetail = data['detail'] ?? 'TTS error';
          throw TtsNetworkException('TTS service error', errorDetail);
        }
      } else if (message is List<int>) {
        audioBuffer.addAll(message);
        // LOG SPAM FIX: Only log at meaningful milestones (64KB intervals) instead of every 4KB
        if (kDebugMode && audioBuffer.length % 65536 == 0) {
          debugPrint(
              '🔍 [TTS] Buffered ${audioBuffer.length} bytes for ${req.id}');
        }
      }
    }

    if (!gotHello) {
      throw Exception('Did not receive tts-hello');
    }

    if (audioBuffer.isEmpty) {
      throw Exception('No audio data received');
    }

    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] Buffering complete: ${audioBuffer.length} total bytes for ${req.id}');
    }

    // Set minimal safety watchdog based on actual audio length (2x estimated duration)
    completionTracker.setSafetyWatchdog(audioBuffer.length);

    // Choose playback method based on backup file preference and feature flag
    if (req.makeBackupFile) {
      // Traditional file-based playback (fallback mode)
      final audioFile =
          await _saveAudioBuffer(audioBuffer, req.format, currentMimeType);

      try {
        if (kDebugMode) {
          debugPrint('🔍 [TTS] Starting backup file playback for ${req.id}');
        }

        // Wait for audio playback to completely finish
        await _audioPlayerManager.playAudio(audioFile.path);

        if (kDebugMode) {
          debugPrint('✅ [TTS] Backup file playback completed for ${req.id}');
        }
      } catch (audioError) {
        if (kDebugMode) {
          debugPrint('❌ [TTS] Backup file playback failed: $audioError');
        }
        rethrow;
      }
      // Note: Temp file cleanup is now handled by AudioPlayerManager after playback completion
    } else if (kTTSUseInMemoryPlayback && audioBuffer.isNotEmpty) {
      // 🚀 OPTIMIZED PATH: In-memory playback (eliminates file I/O)
      try {
        if (kDebugMode) {
          debugPrint(
              '🚀 [TTS] Starting in-memory playback for ${req.id} (${audioBuffer.length} bytes)');
        }

        // Play audio directly from memory - no disk I/O!
        await _audioPlayerManager.playAudioBytes(
          Uint8List.fromList(audioBuffer),
          debugName: 'tts_${req.id}',
          mimeType: currentMimeType,
        );

        if (kDebugMode) {
          debugPrint('✅ [TTS] In-memory playback completed for ${req.id}');
        }
      } catch (audioError) {
        if (kDebugMode) {
          debugPrint(
              '❌ [TTS] In-memory playback failed, falling back to file: $audioError');
        }

        // Fallback to file-based playback if in-memory fails
        final audioFile =
            await _saveAudioBuffer(audioBuffer, req.format, currentMimeType);
        await _audioPlayerManager.playAudio(audioFile.path);
      }
    } else {
      if (kDebugMode) {
        debugPrint(
            '🔍 [TTS] Stream-only mode, no playback needed for ${req.id}');
      }
      // For cases where streaming already played the audio and no backup is needed
    }
  }

  Future<io.File> _saveAudioBuffer(
      List<int> audioBuffer, String format, String mimeType) async {
    final ext = _determineFileExtension(format, mimeType);

    // Generate clean ID without extension using utility - prevents double extensions
    final fileId = AudioPathUtils.generateTimestampId('tts');
    final filePath = PathManager.instance.ttsFile(fileId, ext);

    final file = io.File(filePath);
    await file.writeAsBytes(audioBuffer);

    if (kDebugMode) {
      debugPrint(
          '🔍 [TTS] Saved ${audioBuffer.length} bytes to: $filePath (format: $format, mime: $mimeType)');
    }

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
      case 'wav':
      default:
        return 'wav';
    }
  }

  // -------- ITTSService Interface (Minimal Implementation) -----------

  @override
  Future<void> initialize() async {
    // Pre-warm AudioPlayerManager if needed
  }

  @override
  Future<String> generateSpeech(String text, {String? voice}) async {
    // Not used in new architecture - everything goes through speak()
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
    // Legacy method - delegate to new speak() API
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
    // Collect all text first, then speak it
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

  /// Cancel all active TTS streams immediately (for mode switches)
  /// Enhanced with 3-second watchdog and performance metrics
  @override
  Future<void> cancelAllStreams() async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) debugPrint('🚨 [TTS] Starting stream cancellation...');

    try {
      await Future.any([
        _actualCancellation(),
        Future.delayed(const Duration(seconds: 3)).then((_) =>
            throw TimeoutException(
                'Cancellation timeout', const Duration(seconds: 3)))
      ]);

      final elapsed = stopwatch.elapsedMilliseconds;
      if (kDebugMode) debugPrint('✅ [TTS] Streams cancelled in ${elapsed}ms');

      // Log performance metrics for slow cancellations
      if (elapsed > 500) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ [TTS] Slow cancellation detected: ${elapsed}ms (>500ms threshold)');
        }
      }
    } catch (e) {
      final elapsed = stopwatch.elapsedMilliseconds;
      if (kDebugMode) {
        debugPrint('🛑 [TTS] Cancellation failed after ${elapsed}ms: $e');
      }

      // Emergency cleanup: detach player from LiveTtsAudioSource
      await _emergencyCleanup();
    }
  }

  /// Perform the actual cancellation logic
  Future<void> _actualCancellation() async {
    // Stop audio playback immediately
    await _audioPlayerManager.stopAudio();

    // Clear the request queue to prevent new TTS requests
    _queue.clear();
    _pendingStreams = 0;

    // Notify that TTS is no longer speaking
    _updateSpeakingState(false);
  }

  /// Emergency cleanup when cancellation times out
  /// Detaches player from LiveTtsAudioSource to release orphaned extractor threads
  Future<void> _emergencyCleanup() async {
    if (kDebugMode) {
      debugPrint(
          '🚨 [TTS] Emergency cleanup - detaching player from LiveTtsAudioSource');
    }

    try {
      // Force stop the audio player to release any held resources
      await _audioPlayerManager.stopAudio();

      // Dispose the active LiveTtsAudioSource to release orphaned threads
      _activeLiveAudioSource?.dispose();
      _activeLiveAudioSource = null;

      // Force reset state
      _updateSpeakingState(false);
      _queue.clear();
      _pendingStreams = 0;

      if (kDebugMode) debugPrint('✅ [TTS] Emergency cleanup completed');
    } catch (e) {
      final ttsException = _convertToTtsException(e, 'Emergency cleanup');
      if (kDebugMode) {
        debugPrint(
            '❌ [TTS] Error during emergency cleanup: ${ttsException.message}');
      }
    }
  }

  @override
  Future<void> resumeAudio() async {
    // Not supported
  }

  @override
  bool get isPlaying => _audioPlayerManager.isPlaying;

  @override
  bool get isSpeaking => _state != _State.idle;

  @override
  Stream<bool> get playbackStateStream => _audioPlayerManager.isPlayingStream;

  @override
  Stream<bool> get speakingStateStream => _speakingStateController.stream;

  @override
  void setVoiceSettings(String voice, double speed, double pitch) {
    // Settings stored but not used in this simplified version
  }

  @override
  void setAudioFormat(String format) {
    // Settings stored but not used in this simplified version
  }

  @override
  void resetTTSState() {
    if (kDebugMode) {
      debugPrint(
          '🔄 [TTS] Starting TTS state reset - cleaning WebSocket, timers, and resources');
    }

    // Cancel any active LiveTtsAudioSource and clear reference
    if (_activeLiveAudioSource != null) {
      _activeLiveAudioSource?.dispose();
      _activeLiveAudioSource = null;
      if (kDebugMode) {
        debugPrint('🔄 [TTS] Active LiveTtsAudioSource disposed');
      }
    }

    // Complete all pending requests with cancellation error
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (!req.done.isCompleted) {
        req.completeError(Exception('TTS reset - request cancelled'));
      }
    }

    // Reset pending streams counter
    _pendingStreams = 0;
    _state = _State.idle;

    // Reset TTS speaking state
    _notifyTTSEnd();
    _fireCompletionSafely(false);

    // Clear any stale speaking state but keep controller alive (unlike dispose)
    if (!_speakingStateController.isClosed) {
      _speakingStateController.add(false);
    }

    if (kDebugMode) {
      debugPrint(
          '🔄 [TTS] Reset complete - queue cleared, WebSocket resources cleaned, state reset to idle');
    }
  }

  @override
  void setAiSpeaking(bool speaking) {
    // State is automatically managed
  }

  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    // Not used in new architecture
    return null;
  }

  @override
  Future<void> cleanupAudioFiles() async {
    // AudioPlayerManager handles cleanup
  }

  /// Update speaking state with deduplication
  void _updateSpeakingState(bool newState) {
    if (newState != _lastSpeakingState) {
      _lastSpeakingState = newState;
      if (!_speakingStateController.isClosed) {
        _speakingStateController.add(newState);
        if (kDebugMode) {
          debugPrint('🎯 [TTS-TRACK] TTS state: $newState');
        }
      }
    }
  }

  /// Notify VoiceService that TTS is starting (Maya stops listening)
  void _notifyTTSStart() {
    // Phase 1: Update speaking state stream
    _updateSpeakingState(true);

    if (_voiceServiceUpdateCallback != null) {
      scheduleMicrotask(() {
        _voiceServiceUpdateCallback!(true);
        if (kDebugMode) {
          debugPrint(
              '🔍 [TTS] Notified VoiceService: TTS started (Maya stops listening)');
        }
      });
    }
  }

  /// Notify VoiceService that TTS has ended (Maya can listen again)
  void _notifyTTSEnd() {
    // Phase 1: Update speaking state stream
    _updateSpeakingState(false);

    if (_voiceServiceUpdateCallback != null) {
      scheduleMicrotask(() {
        _voiceServiceUpdateCallback!(false);
        if (kDebugMode) {
          debugPrint(
              '🔍 [TTS] Notified VoiceService: TTS ended (Maya can listen again)');
        }
      });
    }
  }

  /// Safely fire completion callback on main thread (handles background isolate events)
  void _fireCompletionSafely(bool isSpeaking) {
    if (_onTTSComplete != null) {
      // Handle background thread events from just_audio using scheduleMicrotask
      scheduleMicrotask(() {
        _onTTSComplete!(isSpeaking);
        if (kDebugMode) {
          debugPrint(
              '🔍 [TTS] Fired completion callback: isSpeaking=$isSpeaking (pending: $_pendingStreams)');
        }
      });
    }
  }

  /// Log latency metrics for performance monitoring
  void _logLatencyMetrics(String requestId, String format, DateTime startTime,
      DateTime? firstAudioTime, DateTime? playbackStartTime) {
    final endTime = DateTime.now();
    final totalDuration = endTime.difference(startTime).inMilliseconds;

    final timeToFirstAudio =
        firstAudioTime?.difference(startTime).inMilliseconds;

    final timeToPlayback =
        playbackStartTime?.difference(startTime).inMilliseconds;

    if (kDebugMode) {
      debugPrint('📊 [TTS-METRICS] $requestId ($format):');
      debugPrint('  Total duration: ${totalDuration}ms');
      if (timeToFirstAudio != null) {
        debugPrint('  Time to first audio: ${timeToFirstAudio}ms');
      }
      if (timeToPlayback != null) {
        debugPrint('  Time to playback start: ${timeToPlayback}ms');
      }

      // Log format-specific performance comparison
      if (format.toLowerCase() == 'opus') {
        debugPrint('  🎯 OPUS performance: Low-latency streaming optimized');
      } else {
        debugPrint(
            '  🎯 WAV performance: Legacy format with header processing');
      }
    }
  }

  /// Schedule state-based controller closure check
  /// Closes the stream controller only when LiveTtsAudioSource is ready
  void _scheduleControllerClosureCheck(
      StreamController<Uint8List>? controller, LiveTtsAudioSource? source) {
    if (controller == null || source == null) return;

    // Check every 50ms until conditions are met
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // Add diagnostic logging every 5 seconds
      if (kDebugMode && timer.tick % 100 == 0) {
        debugPrint(
            '📊 [TTS] Controller check: tick=${timer.tick}, closed=${controller.isClosed}, '
            'wsClose=${source.isWebSocketClosed}, streamComplete=${source.isStreamCompleted}, '
            'bufferSize=${source.bufferSize}');
      }

      // Check if we should close the controller
      // FIX: Remove circular dependency - close when WebSocket is done
      final shouldClose = controller.isClosed || source.isWebSocketClosed;

      if (shouldClose) {
        timer.cancel();

        if (!controller.isClosed) {
          try {
            controller.close();
            if (kDebugMode) {
              debugPrint(
                  '🔌 [TTS] Stream controller closed after WebSocket completion');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ [TTS] Error closing stream controller: $e');
            }
          }
        }
      }

      // Extended safety timeout for long messages (was 200ms, now 30 seconds)
      // With content-length support, ExoPlayer should complete naturally
      if (timer.tick > 600) {
        // 600 * 50ms = 30 seconds
        timer.cancel();
        if (!controller.isClosed) {
          try {
            controller.close();
            if (kDebugMode) {
              debugPrint(
                  '⏰ [TTS] Stream controller closed due to extended safety timeout (30s) - this should rarely happen with content-length');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '⚠️ [TTS] Error closing stream controller on timeout: $e');
            }
          }
        }
      }
    });
  }

  /// Convert generic exceptions to structured TtsException
  TtsException _convertToTtsException(Object error, String context) {
    if (error is TtsException) {
      return error; // Already structured
    }

    // Use extension method for automatic conversion
    return error.toTtsException(context);
  }

  /// Get caller information for TTS duplication tracking
  String _getCallerInfo() {
    try {
      final trace = StackTrace.current.toString();
      final lines = trace.split('\n');
      // Find the first line that's not in SimpleTTSService
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
    // Prevent overlapping dispose operations using mutex
    if (_disposeCompleter != null) {
      if (kDebugMode) {
        debugPrint('🔄 [TTS] Dispose already in progress, waiting...');
      }
      return; // Another dispose is already running
    }

    if (_disposed) return;
    _disposed = true;

    // Set dispose mutex
    _disposeCompleter = Completer<void>();

    try {
      // Complete all pending requests with error
      while (_queue.isNotEmpty) {
        final req = _queue.removeFirst();
        req.completeError(Exception('Service disposed'));
      }

      // Reset TTS state on disposal
      _notifyTTSEnd();
      _fireCompletionSafely(false);

      // CRITICAL: Dispose AudioPlayerManager to release audio resources
      try {
        _audioPlayerManager.disposeAsync();
        if (kDebugMode) {
          debugPrint('🧹 [TTS] AudioPlayerManager disposal initiated');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [TTS] AudioPlayerManager disposal error: $e');
        }
      }

      // Phase 1: Close the speaking state stream controller
      if (!_speakingStateController.isClosed) {
        _speakingStateController.close();
      }

      if (kDebugMode) debugPrint('🔍 [TTS] Service disposed');

      // Complete the dispose operation
      _disposeCompleter?.complete();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TTS] Error during dispose: $e');
      _disposeCompleter?.completeError(e);
    }
  }
}

enum _State { idle, connecting, streaming }
