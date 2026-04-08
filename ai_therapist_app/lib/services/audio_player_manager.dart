import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../di/interfaces/i_audio_settings.dart';
import 'tts_streaming_monitor.dart';
import '../utils/memory_monitor.dart';
import 'live_tts_audio_source.dart';
import '../utils/disposable.dart';
import '../utils/throttled_debug_print.dart';
class AudioQueueItem {
  final String audioPath;
  final String id;
  final Completer<void> completer;
  final DateTime addedAt;
  AudioQueueItem({
    required this.audioPath,
    required this.id,
    required this.completer,
  }) : addedAt = DateTime.now();
}
class AudioPlayerManager with SessionDisposable implements AsyncDisposable {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final IAudioSettings? _audioSettings;
  double _lastRequestedVolume = 1.0;
  bool _disposed = false;
  double _systemVolume = 1.0;
  bool _isSoftMuted = false;
  Timer? _muteDebounceTimer;
  bool? _forceIsPlayingState;
  int _activePlaybackToken = 0;
  String? _activePlaybackDebugName;
  final StreamController<bool> _playingStateController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final StreamController<int> _queueLengthController =
      StreamController<int>.broadcast();
  final StreamController<String?> _nowPlayingController =
      StreamController<String?>.broadcast();
  final StreamController<bool> _muteStateController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _playbackActiveController =
      StreamController<bool>.broadcast();
  bool? _lastEmittedPlayingState;
  bool _playbackActive = false;
  Timer? _stateDebounceTimer;
  bool? _pendingStateChange;
  static const Duration _stateDebounceInterval = Duration(milliseconds: 100);
  final List<AudioQueueItem> _audioQueue = [];
  AudioQueueItem? _currentlyPlaying;
  bool _isProcessingQueue = false;
  static const int _maxQueueSize = 10;
  static const int _queueWarningThreshold = 5;
  Stream<bool> get isPlayingStream => _playingStateController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  Stream<int> get queueLengthStream => _queueLengthController.stream;
  Stream<String?> get nowPlayingStream => _nowPlayingController.stream;
  Stream<bool> get muteStateStream => _muteStateController.stream;
  Stream<bool> get playbackActiveStream => _playbackActiveController.stream;
  Stream<ProcessingState> get processingStateStream =>
      _audioPlayer.processingStateStream;
  AudioPlayerManager({IAudioSettings? audioSettings})
      : _audioSettings = audioSettings {
    _initAudioPlayer();
    _audioSettings?.addListener(_onMuteChanged);
    // CRITICAL: Apply initial mute state
    _applyEffectiveVolume();
    _setPlaybackActive(false);
  }
  Future<void> prewarmPlayer() async {
    if (_disposed) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await _audioPlayer.setVolume(0.0);
      await _audioPlayer.setVolume(1.0);
    } catch (e) {}
  }
  void _onMuteChanged() {
    if (_disposed) return; // Guard against post-dispose callbacks
    _applyEffectiveVolume();
  }
  double _getEffectiveVolume(double requestedVolume) {
    if (_isSoftMuted) return 0.0;
    final multiplier = _audioSettings?.volumeMultiplier ?? 1.0;
    return requestedVolume * multiplier;
  }
  void _applyEffectiveVolume() {
    if (_disposed) return; // Guard against post-dispose calls
    final effective = _getEffectiveVolume(_lastRequestedVolume);
    try {
      _audioPlayer.setVolume(effective);
    } catch (e) {}
  }
  void _setPlaybackActive(bool active) {
    if (_playbackActive == active) {
      return;
    }
    _playbackActive = active;
    if (!_playbackActiveController.isClosed) {
      _playbackActiveController.add(active);
    }
  }
  int _promotePlaybackToken(String debugName) {
    final token = ++_activePlaybackToken;
    _activePlaybackDebugName = debugName;
    return token;
  }
  Future<void> _setSourceAndApplyVolume(
      Future<void> Function() setSourceFn) async {
    await setSourceFn();
    _applyEffectiveVolume();
  }
  void _emitPlayingState(bool isPlaying) {
    _pendingStateChange = isPlaying;
    _stateDebounceTimer?.cancel();
    _stateDebounceTimer = Timer(_stateDebounceInterval, () {
      if (_lastEmittedPlayingState != _pendingStateChange) {
        _lastEmittedPlayingState = _pendingStateChange;
        _playingStateController.add(_pendingStateChange!);
      }
      _pendingStateChange = null;
    });
  }
  void _emitPlayingStateImmediate(bool isPlaying) {
    _stateDebounceTimer?.cancel();
    _pendingStateChange = null;
    if (_lastEmittedPlayingState != isPlaying) {
      _lastEmittedPlayingState = isPlaying;
      _playingStateController.add(isPlaying);
    }
  }
  Future<void> _initAudioPlayer() async {
    try {
      // CRITICAL: Explicitly disable loop mode to prevent infinite TTS replay
      await _audioPlayer.setLoopMode(LoopMode.off);
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      _audioPlayer.playerStateStream.listen((playerState) {
        final isPlaying = playerState.playing;
        _emitPlayingState(isPlaying);
        if (isPlaying &&
            _audioPlayer.processingState == ProcessingState.ready) {
          _setPlaybackActive(true);
        }
        if (!isPlaying) {
          _setPlaybackActive(false);
        }
      });
      _audioPlayer.processingStateStream.listen((state) {
        switch (state) {
          case ProcessingState.idle:
            _setPlaybackActive(false);
            break;
          case ProcessingState.loading:
            break;
          case ProcessingState.buffering:
            break;
          case ProcessingState.ready:
            if (_audioPlayer.playing) {
              _setPlaybackActive(true);
            }
            break;
          case ProcessingState.completed:
            _setPlaybackActive(false);
            _emitPlayingState(false);
            if (_isSoftMuted) {
              _isSoftMuted = false;
              _muteStateController.add(false);
            }
            Future.delayed(const Duration(milliseconds: 100), () {
              if (!_audioPlayer.playing) {
                _emitPlayingState(false);
              }
              _processNextInQueue();
            });
            break;
        }
      });
      _audioPlayer.positionStream.listen((position) {
      });
    } catch (e) {
      _errorController.add('Error initializing audio player: $e');
    }
  }
  Future<void> playAudio(String audioPath) async {
    if (audioPath.isEmpty) {
      _errorController.add('Empty audio path provided for playback');
      throw ArgumentError('Empty audio path provided for playback');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_${audioPath.hashCode}';
    final completer = Completer<void>();
    final queueItem = AudioQueueItem(
      audioPath: audioPath,
      id: id,
      completer: completer,
    );
    if (_audioQueue.length >= _maxQueueSize) {
      const error = 'Audio queue full (max: $_maxQueueSize items)';
      _errorController.add(error);
      completer.completeError(Exception(error));
      return completer.future;
    }
    _audioQueue.add(queueItem);
    _queueLengthController.add(_audioQueue.length);
    if (_audioQueue.length > _queueWarningThreshold) {
    }
    if (!_isProcessingQueue) {
      _processQueue();
    }
    return completer.future;
  }
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _audioQueue.isEmpty) {
      return;
    }
    _isProcessingQueue = true;
    while (_audioQueue.isNotEmpty) {
      final item = _audioQueue.removeAt(0);
      _currentlyPlaying = item;
      _queueLengthController.add(_audioQueue.length);
      _nowPlayingController.add(item.audioPath);
      try {
        await _playAudioItem(item);
      } catch (e) {
        _errorController.add('Error playing queued audio: $e');
        if (!item.completer.isCompleted) {
          item.completer.completeError(e);
        }
      }
      _currentlyPlaying = null;
      _nowPlayingController.add(null);
    }
    _isProcessingQueue = false;
  }
  void _processNextInQueue() {
    if (!_isProcessingQueue && _audioQueue.isNotEmpty) {
      _processQueue();
    }
  }
  Future<void> _playAudioItem(AudioQueueItem item) async {
    try {
      final file = File(item.audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file does not exist: ${item.audioPath}');
      }
      await _audioPlayer.stop();
      _forceIsPlayingState = null;
      await _setSourceAndApplyVolume(
          () => _audioPlayer.setFilePath(item.audioPath));
      final playbackCompleter = Completer<void>();
      StreamSubscription? subscription;
      subscription = _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed ||
            state == ProcessingState.idle ||
            (state == ProcessingState.ready && !_audioPlayer.playing)) {
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
          subscription?.cancel();
        }
      });
      StreamSubscription? errorSubscription;
      errorSubscription = _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (error) {
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.completeError(error);
          }
          errorSubscription?.cancel();
        },
      );
      if (!_audioPlayer.playing) {
        await _audioPlayer.play();
      }
      await playbackCompleter.future;
      _safeDeleteTempFile(item.audioPath);
      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
    } catch (e) {
      _errorController.add('Error playing audio: $e');
      if (!item.completer.isCompleted) {
        item.completer.completeError(e);
      }
      rethrow;
    }
  }
  Future<void> stopAudio({bool clearQueue = true}) async {
    try {
      await _audioPlayer.stop();
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
      if (clearQueue) {
        for (final item in _audioQueue) {
          if (!item.completer.isCompleted) {
            item.completer.completeError(Exception('Playback cancelled'));
          }
        }
        _audioQueue.clear();
        _queueLengthController.add(0);
      }
      _isProcessingQueue = false;
      _currentlyPlaying = null;
      _nowPlayingController.add(null);
    } catch (e) {
      _errorController.add('Error stopping audio: $e');
    }
  }
  Future<void> lightweightReset() async {
    try {
      await _audioPlayer.stop();
      _setPlaybackActive(false);
      await _audioPlayer.seek(Duration.zero);
      // Note: JustAudio doesn't support setAudioSource(null), but stop() + seek() already flushes callbacks
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
      for (final item in _audioQueue) {
        if (!item.completer.isCompleted) {
          item.completer
              .completeError(Exception('Audio reset - playback cancelled'));
        }
      }
      _audioQueue.clear();
      _queueLengthController.add(0);
      _isProcessingQueue = false;
      _currentlyPlaying = null;
      _nowPlayingController.add(null);
    } catch (e) {
      _errorController.add('Error during lightweight reset: $e');
      rethrow; // Let caller handle the error
    }
  }
  void forceStopState() {
    _forceIsPlayingState = false;
    _emitPlayingStateImmediate(false);
  }
  bool get isPlaying {
    if (_forceIsPlayingState != null) {
      return _forceIsPlayingState!;
    }
    final actualState = _audioPlayer.playing;
    return actualState;
  }
  bool get isPlaybackActive => _playbackActive;
  AudioPlayer get audioPlayer => _audioPlayer;
  int get queueLength => _audioQueue.length;
  String? get currentlyPlayingPath => _currentlyPlaying?.audioPath;
  Map<String, dynamic> get queueStatus => {
        'queueLength': _audioQueue.length,
        'isProcessing': _isProcessingQueue,
        'currentlyPlaying': _currentlyPlaying?.audioPath,
        'currentId': _currentlyPlaying?.id,
        'queueItems': _audioQueue
            .map((item) => {
                  'path': item.audioPath,
                  'id': item.id,
                  'waitTime':
                      DateTime.now().difference(item.addedAt).inMilliseconds,
                })
            .toList(),
      };
  Future<void> skipCurrent() async {
    if (_currentlyPlaying != null) {
      if (!_currentlyPlaying!.completer.isCompleted) {
        _currentlyPlaying!.completer.completeError(Exception('Audio skipped'));
      }
      await _audioPlayer.stop();
    }
  }
  void clearQueue() {
    for (final item in _audioQueue) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(Exception('Queue cleared'));
      }
    }
    _audioQueue.clear();
    _queueLengthController.add(0);
  }
  Future<void> sessionEndCleanup() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _audioPlayer.stop();
      _setPlaybackActive(false);
      await _audioPlayer.dispose();
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
      _setPlaybackActive(false);
      _stateDebounceTimer?.cancel();
      _stateDebounceTimer = null;
      stopwatch.stop();
    } catch (e) {
      stopwatch.stop();
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
    }
  }
  @override
  Future<void> performAsyncDisposal() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _audioPlayer.stop();
      _setPlaybackActive(false);
      clearQueue();
      _isProcessingQueue = false;
      _currentlyPlaying = null;
      _stateDebounceTimer?.cancel();
      _stateDebounceTimer = null;
      _audioSettings?.removeListener(_onMuteChanged);
      await Future.any([
        Future(() async {
          await _audioPlayer.dispose(); // This calls release() internally
        }),
        Future.delayed(const Duration(seconds: 3), () {
        }),
      ]);
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (sessionError) {}
      await Future.wait([
        _playingStateController.close(),
        _errorController.close(),
        _queueLengthController.close(),
        _nowPlayingController.close(),
        _muteStateController.close(),
        _playbackActiveController.close(),
      ]);
      stopwatch.stop();
    } catch (e) {
      stopwatch.stop();
      try {
        _stateDebounceTimer?.cancel();
        _audioSettings?.removeListener(_onMuteChanged);
        clearQueue();
      } catch (cleanupError) {}
      rethrow;
    }
  }
  @override
  void performDisposal() {
    _audioSettings?.removeListener(_onMuteChanged);
    clearQueue();
    _stateDebounceTimer?.cancel();
    _muteDebounceTimer?.cancel();
    _forceIsPlayingState = false;
    _emitPlayingStateImmediate(false);
    _setPlaybackActive(false);
    // Note: We don't dispose the player here to avoid MediaCodec issues
  }
  Future<void> setVolume(double volume) async {
    _lastRequestedVolume = volume;
    _applyEffectiveVolume();
  }
  void mute(bool muted) {
    _muteDebounceTimer?.cancel();
    _muteDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      _isSoftMuted = muted;
      if (muted) {
        _systemVolume = _lastRequestedVolume;
        _audioPlayer.setVolume(0.0);
      } else {
        final restoreVolume = math.min(_lastRequestedVolume, _systemVolume);
        _applyEffectiveVolume(); // This will use the restored volume
      }
      _muteStateController.add(muted);
    });
  }
  bool get isSoftMuted => _isSoftMuted;
  Future<void> _cleanupPreviousSubscriptions() async {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  Future<void> playLiveTtsStream(
    dynamic audioSourceOrStream, {
    String? debugName,
    String contentType = 'audio/wav',
    void Function(int playbackToken)? onPlaybackToken,
    void Function(int playbackToken)?
        onNaturalCompletion, // Callback for natural ExoPlayer completion
  }) async {
    final displayName = debugName ?? 'live-tts-audio';
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_live_${audioSourceOrStream.hashCode}';
    final startTime = DateTime.now();
    TTSStreamingMonitor().recordStreamingStart();
    MemoryMonitor.setBaseline();
    final playbackToken = _promotePlaybackToken(displayName);
    onPlaybackToken?.call(playbackToken);
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.stop(); // Kill the old clip first
      }
      await _cleanupPreviousSubscriptions();
      _forceIsPlayingState = null;
      final LiveTtsAudioSource liveSource;
      if (audioSourceOrStream is LiveTtsAudioSource) {
        liveSource = audioSourceOrStream;
      } else if (audioSourceOrStream is Stream<Uint8List>) {
        liveSource = LiveTtsAudioSource(
          audioSourceOrStream,
          contentType: contentType,
          debugName: displayName,
        );
      } else {
        throw ArgumentError(
            'audioSourceOrStream must be either Stream<Uint8List> or LiveTtsAudioSource');
      }
      liveSource.attachPlaybackToken(playbackToken);
      try {
        await _setSourceAndApplyVolume(
            () => _audioPlayer.setAudioSource(liveSource, preload: false));
        await _audioPlayer.play();
      } catch (sourceError) {
        // CRITICAL: Clean up on source error to prevent VAD/recording pipeline hanging
        try {
          await _audioPlayer.stop();
        } catch (stopError) {}
        _forceIsPlayingState = false;
        _emitPlayingStateImmediate(false);
        TTSStreamingMonitor()
            .recordStreamingFailure('Source setup error: $sourceError');
        rethrow;
      }
      final playbackCompleter = Completer<void>();
      StreamSubscription? subscription;
      subscription = _audioPlayer.processingStateStream.listen((state) {
        if (playbackToken != _activePlaybackToken) {
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
          subscription?.cancel();
          return;
        }
        if (state == ProcessingState.completed) {
          subscription?.cancel();
          // CRITICAL: Clear the source to prevent any possibility of replay
          _audioPlayer.stop().catchError((e) {
          });
          final latency = DateTime.now().difference(startTime).inMilliseconds;
          TTSStreamingMonitor().recordStreamingSuccess(latencyMs: latency);
          _forceIsPlayingState = false;
          _emitPlayingState(false);
          onNaturalCompletion?.call(playbackToken);
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        } else if (state == ProcessingState.ready && _audioPlayer.playing) {
        }
      });
      StreamSubscription? errorSubscription;
      errorSubscription = _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (error) {
          if (playbackToken != _activePlaybackToken) {
            if (!playbackCompleter.isCompleted) {
              playbackCompleter.complete();
            }
            errorSubscription?.cancel();
            return;
          }
          TTSStreamingMonitor()
              .recordStreamingFailure('Live playback error: $error');
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.completeError(error);
          }
          errorSubscription?.cancel();
        },
      );
      await playbackCompleter.future;
      if (playbackToken != _activePlaybackToken) {
        return;
      }
    } catch (e) {
      TTSStreamingMonitor().recordStreamingFailure('Live TTS exception: $e');
      _errorController.add('Live TTS audio playback error: $e');
      rethrow;
    }
  }
  Future<void> playAudioBytes(Uint8List audioBytes,
      {String? debugName, String? mimeType}) async {
    if (audioBytes.isEmpty) {
      _errorController.add('Empty audio bytes provided for playback');
      throw ArgumentError('Empty audio bytes provided for playback');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_memory_${audioBytes.hashCode}';
    final displayName = debugName ?? 'in-memory-audio';
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.stop(); // Kill the old clip first
      }
      _forceIsPlayingState = null;
      final base64Audio = base64Encode(audioBytes);
      final sanitizedMime = (mimeType ?? 'audio/wav').replaceAll('; ', ';');
      final dataUri = 'data:$sanitizedMime;base64,$base64Audio';
      await _setSourceAndApplyVolume(() =>
          _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(dataUri))));
      final playbackCompleter = Completer<void>();
      StreamSubscription? subscription;
      subscription = _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed ||
            state == ProcessingState.idle ||
            (state == ProcessingState.ready && !_audioPlayer.playing)) {
          subscription?.cancel();
          // CRITICAL: Clear the source to prevent any possibility of replay
          _audioPlayer.stop().catchError((e) {
          });
          _forceIsPlayingState = false;
          _emitPlayingState(false);
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        }
      });
      await _audioPlayer.play();
      await playbackCompleter.future;
    } catch (e) {
      _errorController.add('Audio playback error: $e');
      rethrow;
    }
  }
  bool _isTempTTSFile(String path) {
    return path.contains('/tts_') &&
        (path.endsWith('.wav') ||
            path.endsWith('.mp3') ||
            path.endsWith('.ogg'));
  }
  void _safeDeleteTempFile(String path) {
    if (!_isTempTTSFile(path)) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {}
  }
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    try {
      _muteDebounceTimer?.cancel();
      _muteDebounceTimer = null;
      _stateDebounceTimer?.cancel();
      _audioSettings?.removeListener(_onMuteChanged);
      clearQueue();
      await stopAudio();
      await _playingStateController.close();
      await _errorController.close();
      await _queueLengthController.close();
      await _nowPlayingController.close();
      await _muteStateController.close();
      // CRITICAL: End AudioSession before disposing player (Android requirement)
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (sessionError) {}
      await _audioPlayer.dispose();
    } catch (e) {}
  }
}
