import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../di/interfaces/i_audio_settings.dart';
import 'tts_streaming_monitor.dart';
import '../utils/memory_monitor.dart';
import 'live_tts_audio_source.dart';
import '../utils/disposable.dart';
import '../utils/throttled_debug_print.dart';
import '../utils/app_logger.dart';

/// Audio queue item containing all necessary information for queued playback
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

/// Manages audio playback functionality with comprehensive queue support
///
/// Responsible for playing audio files, managing playback state, and handling
/// audio queue for concurrent playback requests
class AudioPlayerManager with SessionDisposable implements AsyncDisposable {
  // Audio player instance
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Audio settings for global mute functionality
  final IAudioSettings? _audioSettings;
  double _lastRequestedVolume = 1.0;
  bool _disposed = false;

  // Force override for isPlaying state
  bool? _forceIsPlayingState;

  // Stream controllers
  final StreamController<bool> _playingStateController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final StreamController<int> _queueLengthController =
      StreamController<int>.broadcast();
  final StreamController<String?> _nowPlayingController =
      StreamController<String?>.broadcast();

  // Track last emitted playing state to prevent duplicate broadcasts
  bool? _lastEmittedPlayingState;
  
  // DEBOUNCE FIX: Prevent rapid-fire identical state changes
  Timer? _stateDebounceTimer;
  bool? _pendingStateChange;
  static const Duration _stateDebounceInterval = Duration(milliseconds: 100);
  
  // Audio queue management
  final List<AudioQueueItem> _audioQueue = [];
  AudioQueueItem? _currentlyPlaying;
  bool _isProcessingQueue = false;
  
  // Queue configuration
  static const int _maxQueueSize = 10;
  static const int _queueWarningThreshold = 5;

  // Streams for external components to listen to
  Stream<bool> get isPlayingStream => _playingStateController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  Stream<int> get queueLengthStream => _queueLengthController.stream;
  Stream<String?> get nowPlayingStream => _nowPlayingController.stream;

  // Expose the audio player's processing state stream
  Stream<ProcessingState> get processingStateStream =>
      _audioPlayer.processingStateStream;

  // Constructor
  AudioPlayerManager({IAudioSettings? audioSettings}) 
    : _audioSettings = audioSettings {
    _initAudioPlayer();
    
    // Listen for mute changes if settings provided
    _audioSettings?.addListener(_onMuteChanged);
    
    // CRITICAL: Apply initial mute state
    _applyEffectiveVolume();
  }
  
  void _onMuteChanged() {
    if (_disposed) return; // Guard against post-dispose callbacks
    _applyEffectiveVolume();
  }
  
  double _getEffectiveVolume(double requestedVolume) {
    final multiplier = _audioSettings?.volumeMultiplier ?? 1.0;
    return requestedVolume * multiplier;
  }
  
  void _applyEffectiveVolume() {
    if (_disposed) return; // Guard against post-dispose calls
    
    final effective = _getEffectiveVolume(_lastRequestedVolume);
    try {
      _audioPlayer.setVolume(effective);
      if (kDebugMode) {
        print('🔊 AudioPlayerManager: Volume applied - '
              'requested=$_lastRequestedVolume, '
              'muted=${_audioSettings?.isMuted ?? false}, '
              'effective=$effective');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioPlayerManager: Failed to set volume: $e');
      }
    }
  }
  
  // Wrapper to ensure volume is applied after source changes
  Future<void> _setSourceAndApplyVolume(Future<void> Function() setSourceFn) async {
    await setSourceFn();
    // Re-apply volume after source change in case player reset it
    _applyEffectiveVolume();
  }

  // Helper method to emit playing state with debouncing to prevent rapid duplicates
  void _emitPlayingState(bool isPlaying) {
    // DEBOUNCE FIX: Store pending state and debounce rapid changes
    _pendingStateChange = isPlaying;
    
    // Cancel any existing timer
    _stateDebounceTimer?.cancel();
    
    // Set new timer to emit state after debounce interval
    _stateDebounceTimer = Timer(_stateDebounceInterval, () {
      // Only emit if state actually changed from last emitted value
      if (_lastEmittedPlayingState != _pendingStateChange) {
        _lastEmittedPlayingState = _pendingStateChange;
        _playingStateController.add(_pendingStateChange!);
        if (kDebugMode) {
          debugPrintThrottledCustom('AudioPlayerManager: Playing state changed to $_pendingStateChange (debounced)',
                          key: 'audio_state_debounced');
        }
      } else if (kDebugMode) {
        AppLogger.v('AudioPlayerManager: Duplicate state change to $_pendingStateChange ignored (debounced)');
      }
      _pendingStateChange = null;
    });
  }

  // DEBOUNCE FIX: Immediate state emission for critical changes (bypasses debouncing)
  void _emitPlayingStateImmediate(bool isPlaying) {
    // Cancel any pending debounced emission
    _stateDebounceTimer?.cancel();
    _pendingStateChange = null;
    
    // Emit immediately if state actually changed
    if (_lastEmittedPlayingState != isPlaying) {
      _lastEmittedPlayingState = isPlaying;
      _playingStateController.add(isPlaying);
      if (kDebugMode) {
        debugPrintThrottledCustom('AudioPlayerManager: Playing state changed to $isPlaying (immediate)',
                          key: 'audio_state_immediate');
      }
    }
  }

  // Initialize the audio player
  Future<void> _initAudioPlayer() async {
    try {
      // CRITICAL: Explicitly disable loop mode to prevent infinite TTS replay
      await _audioPlayer.setLoopMode(LoopMode.off);
      if (kDebugMode) {
        AppLogger.d('AudioPlayerManager: Loop mode explicitly set to OFF');
      }
      
      // Set up audio session
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

      // Set up player listeners
      _audioPlayer.playerStateStream.listen((playerState) {
        final isPlaying = playerState.playing;
        _emitPlayingState(isPlaying);

        if (kDebugMode && isPlaying) {
          AppLogger.d('Audio playback started');
        } else if (kDebugMode && !isPlaying) {
          AppLogger.d('Audio playback paused/stopped');
        }
      });

      _audioPlayer.processingStateStream.listen((state) {
        if (kDebugMode) {
          debugPrintThrottledCustom('🔄 AudioPlayerManager: ProcessingState changed to $state (playing: ${_audioPlayer.playing})',
                            key: 'audio_processing_state');
        }
        
        switch (state) {
          case ProcessingState.idle:
            if (kDebugMode) {
              print('🟡 ProcessingState.idle - Player is idle/stopped');
            }
            break;
          case ProcessingState.loading:
            if (kDebugMode) {
              print('🟠 ProcessingState.loading - Loading audio data');
            }
            break;
          case ProcessingState.buffering:
            if (kDebugMode) {
              print('🔵 ProcessingState.buffering - Buffering audio data');
            }
            break;
          case ProcessingState.ready:
            if (kDebugMode) {
              print('🟢 ProcessingState.ready - Ready to play (playing: ${_audioPlayer.playing})');
            }
            break;
          case ProcessingState.completed:
            if (kDebugMode) {
              print('✅ ProcessingState.completed - Audio playback naturally completed');
            }
            // Ensure we broadcast playback stopped when audio completes
            _emitPlayingState(false);

            // Add a short delay to ensure all state changes are processed
            Future.delayed(const Duration(milliseconds: 100), () {
              // Double-check that we're actually stopped
              if (!_audioPlayer.playing) {
                _emitPlayingState(false);
                if (kDebugMode) {
                  AppLogger.d('Audio playback completion confirmed');
                }
              }
              
              // Process next item in queue after current completes
              _processNextInQueue();
            });
            break;
        }
      });

      // Add position stream listener for additional robustness
      _audioPlayer.positionStream.listen((position) {
        // No direct action needed, just keeping the stream active
      });
    } catch (e) {
      _errorController.add('Error initializing audio player: $e');
      if (kDebugMode) {
        print('❌ Audio player initialization error: $e');
      }
    }
  }

  /// Play audio with queue support - adds to queue if player is busy
  /// Returns a Future that completes when the audio finishes playing
  Future<void> playAudio(String audioPath) async {
    if (audioPath.isEmpty) {
      _errorController.add('Empty audio path provided for playback');
      throw ArgumentError('Empty audio path provided for playback');
    }

    // Generate unique ID for this audio request
    final id = '${DateTime.now().microsecondsSinceEpoch}_${audioPath.hashCode}';
    
    // Create completer for this specific audio playback
    final completer = Completer<void>();
    
    // Create queue item
    final queueItem = AudioQueueItem(
      audioPath: audioPath,
      id: id,
      completer: completer,
    );

    // Check queue size limit
    if (_audioQueue.length >= _maxQueueSize) {
      final error = 'Audio queue full (max: $_maxQueueSize items)';
      if (kDebugMode) {
        AppLogger.e('AudioPlayerManager', error);
      }
      _errorController.add(error);
      completer.completeError(Exception(error));
      return completer.future;
    }

    // Add to queue
    _audioQueue.add(queueItem);
    _queueLengthController.add(_audioQueue.length);
    
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Added to queue: $audioPath (ID: $id, Queue length: ${_audioQueue.length})');
    }

    // Emit warning if queue is getting long
    if (_audioQueue.length > _queueWarningThreshold) {
      if (kDebugMode) {
        print('⚠️ AudioPlayerManager: Queue length (${_audioQueue.length}) exceeds warning threshold ($_queueWarningThreshold)');
      }
    }

    // Start processing queue if not already processing
    if (!_isProcessingQueue) {
      _processQueue();
    }

    return completer.future;
  }

  /// Process the audio queue
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

      if (kDebugMode) {
        AppLogger.d('AudioPlayerManager: Processing queue item: ${item.audioPath} (ID: ${item.id}, Remaining in queue: ${_audioQueue.length})');
      }

      try {
        await _playAudioItem(item);
      } catch (e) {
        if (kDebugMode) {
          print('❌ AudioPlayerManager: Error playing queued audio: $e');
        }
        _errorController.add('Error playing queued audio: $e');
        if (!item.completer.isCompleted) {
          item.completer.completeError(e);
        }
      }

      _currentlyPlaying = null;
      _nowPlayingController.add(null);
    }

    _isProcessingQueue = false;
    
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Queue processing completed');
    }
  }

  /// Process next item in queue (called after current playback completes)
  void _processNextInQueue() {
    if (!_isProcessingQueue && _audioQueue.isNotEmpty) {
      if (kDebugMode) {
        AppLogger.v('AudioPlayerManager: Auto-processing next in queue');
      }
      _processQueue();
    }
  }

  /// Play a specific audio item
  Future<void> _playAudioItem(AudioQueueItem item) async {
    try {
      final file = File(item.audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file does not exist: ${item.audioPath}');
      }

      if (kDebugMode) {
        final fileSize = await file.length();
        final waitTime = DateTime.now().difference(item.addedAt).inMilliseconds;
        debugPrintThrottledCustom('Playing audio from: ${item.audioPath} (size: $fileSize bytes, waited: ${waitTime}ms)',
                          key: 'audio_file_playback');
      }

      // Stop any current playback
      await _audioPlayer.stop();

      // Clear force override when starting new playback
      _forceIsPlayingState = null;

      // Load and play the audio with volume protection
      await _setSourceAndApplyVolume(
        () => _audioPlayer.setFilePath(item.audioPath)
      );
      
      // Create a completer for playback completion
      final playbackCompleter = Completer<void>();
      
      // Listen for completion
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

      // Error handling subscription
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

      // Start playback
      if (!_audioPlayer.playing) {
        await _audioPlayer.play();
        if (kDebugMode) {
          AppLogger.d('AudioPlayerManager: Started playback for ${item.audioPath} (ID: ${item.id})');
        }
      }

      // Wait for playback to complete
      await playbackCompleter.future;
      
      // Clean up temporary TTS file after playback completion
      _safeDeleteTempFile(item.audioPath);
      
      // Complete the item's completer
      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
      
      if (kDebugMode) {
        AppLogger.d('AudioPlayerManager: Completed playback for ${item.audioPath} (ID: ${item.id})');
      }
    } catch (e) {
      _errorController.add('Error playing audio: $e');
      if (kDebugMode) {
        print('❌ Audio playback error: $e');
      }
      if (!item.completer.isCompleted) {
        item.completer.completeError(e);
      }
      rethrow;
    }
  }

  // Stop playing audio and clear queue
  Future<void> stopAudio({bool clearQueue = true}) async {
    try {
      await _audioPlayer.stop();

      // Force the state to false immediately
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);

      if (clearQueue) {
        // Complete all pending items with cancellation
        for (final item in _audioQueue) {
          if (!item.completer.isCompleted) {
            item.completer.completeError(Exception('Playback cancelled'));
          }
        }
        _audioQueue.clear();
        _queueLengthController.add(0);
      }

      // Reset processing flag
      _isProcessingQueue = false;
      _currentlyPlaying = null;
      _nowPlayingController.add(null);

      if (kDebugMode) {
        AppLogger.d('AudioPlayerManager: Audio playback stopped - isPlaying forced to false, queue cleared: $clearQueue');
      }
    } catch (e) {
      _errorController.add('Error stopping audio: $e');
      if (kDebugMode) {
        print('❌ Error stopping audio: $e');
      }
    }
  }

  // Force reset the playing state
  void forceStopState() {
    _forceIsPlayingState = false;
    _emitPlayingStateImmediate(false);
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Playing state forced to false');
    }
  }

  // Check if audio is currently playing
  bool get isPlaying {
    // If we have a force override, use that
    if (_forceIsPlayingState != null) {
      if (kDebugMode) {
        AppLogger.v('AudioPlayerManager.isPlaying: Using force override = $_forceIsPlayingState');
      }
      return _forceIsPlayingState!;
    }
    // Otherwise use the actual player state
    final actualState = _audioPlayer.playing;
    if (kDebugMode) {
      AppLogger.v('AudioPlayerManager.isPlaying: Using actual player state = $actualState');
    }
    return actualState;
  }

  /// Get the raw AudioPlayer instance for force completion operations
  /// Used by LiveTtsAudioSource to trigger immediate completion events
  AudioPlayer get audioPlayer => _audioPlayer;

  /// Get current queue length
  int get queueLength => _audioQueue.length;

  /// Get currently playing audio path
  String? get currentlyPlayingPath => _currentlyPlaying?.audioPath;

  /// Get queue status information
  Map<String, dynamic> get queueStatus => {
    'queueLength': _audioQueue.length,
    'isProcessing': _isProcessingQueue,
    'currentlyPlaying': _currentlyPlaying?.audioPath,
    'currentId': _currentlyPlaying?.id,
    'queueItems': _audioQueue.map((item) => {
      'path': item.audioPath,
      'id': item.id,
      'waitTime': DateTime.now().difference(item.addedAt).inMilliseconds,
    }).toList(),
  };

  /// Skip current audio and move to next in queue
  Future<void> skipCurrent() async {
    if (_currentlyPlaying != null) {
      if (kDebugMode) {
        AppLogger.d('AudioPlayerManager: Skipping current audio: ${_currentlyPlaying!.audioPath}');
      }
      
      // Complete current item with skip error
      if (!_currentlyPlaying!.completer.isCompleted) {
        _currentlyPlaying!.completer.completeError(Exception('Audio skipped'));
      }
      
      // Stop current playback
      await _audioPlayer.stop();
      
      // Process next will be triggered by the stop event
    }
  }

  /// Clear the audio queue without stopping current playback
  void clearQueue() {
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Clearing queue (${_audioQueue.length} items)');
    }
    
    // Complete all pending items with cancellation
    for (final item in _audioQueue) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(Exception('Queue cleared'));
      }
    }
    
    _audioQueue.clear();
    _queueLengthController.add(0);
  }
  
  /// Session end cleanup following exact specification
  /// Call this when therapy session ends or user navigates away
  Future<void> sessionEndCleanup() async {
    if (kDebugMode) {
      print('🧹 AudioPlayerManager: Session end cleanup starting');
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Step 1: Stop player immediately
      await _audioPlayer.stop();
      if (kDebugMode) {
        print('🧹 Step 1: Player stopped');
      }
      
      // Step 2: Dispose player (frees decoder, closes sockets)
      await _audioPlayer.dispose();
      if (kDebugMode) {
        print('🧹 Step 2: Player disposed');
      }
      
      // Step 3: Signal TTS completion and cancel all watchdogs
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
      
      // Cancel all timers and subscriptions
      _stateDebounceTimer?.cancel();
      _stateDebounceTimer = null;
      
      stopwatch.stop();
      
      if (kDebugMode) {
        print('✅ AudioPlayerManager: Session cleanup completed in ${stopwatch.elapsedMilliseconds}ms');
      }
      
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        print('❌ AudioPlayerManager: Session cleanup error (${stopwatch.elapsedMilliseconds}ms): $e');
      }
      
      // Force state reset even on error
      _forceIsPlayingState = false;
      _emitPlayingStateImmediate(false);
    }
  }

  // Clean up resources - ASYNC VERSION
  @override
  Future<void> performAsyncDisposal() async {
    if (kDebugMode) {
      debugPrint('🧹 AudioPlayerManager: Starting comprehensive async disposal');
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // Step 1: Stop all playback immediately to prevent MediaCodec race
      if (kDebugMode) {
        debugPrint('🧹 Step 1: Stopping playback and clearing queue');
      }
      await _audioPlayer.stop();
      
      // Step 2: Clear queue and complete all pending items
      clearQueue();
      _isProcessingQueue = false;
      _currentlyPlaying = null;
      
      // Step 3: Cancel all timers to prevent post-disposal callbacks
      if (kDebugMode) {
        debugPrint('🧹 Step 2: Canceling timers and removing listeners');
      }
      _stateDebounceTimer?.cancel();
      _stateDebounceTimer = null;
      
      // Step 4: Remove audio settings listener before disposing
      _audioSettings?.removeListener(_onMuteChanged);
      
      // Step 5: Release player resources - frees decoder, closes sockets
      if (kDebugMode) {
        debugPrint('🧹 Step 3: Releasing AudioPlayer (frees decoder, closes sockets)');
      }
      
      await Future.any([
        Future(() async {
          await _audioPlayer.dispose(); // This calls release() internally
          if (kDebugMode) {
            debugPrint('🧹 AudioPlayer release completed successfully');
          }
        }),
        Future.delayed(const Duration(seconds: 3), () {
          if (kDebugMode) {
            debugPrint('⚠️ AudioPlayer release timed out after 3 seconds');
          }
          // Don't throw - just log the timeout
        }),
      ]);
      
      // Step 6: Abandon audio focus to fully release audio session
      if (kDebugMode) {
        debugPrint('🧹 Step 4: Abandoning audio focus');
      }
      
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
        if (kDebugMode) {
          debugPrint('🧹 Audio session deactivated successfully');
        }
      } catch (sessionError) {
        if (kDebugMode) {
          debugPrint('⚠️ Error deactivating audio session: $sessionError');
        }
        // Don't rethrow - session cleanup is best effort
      }
      
      // Step 7: Close all stream controllers
      if (kDebugMode) {
        debugPrint('🧹 Step 5: Closing stream controllers');
      }
      await Future.wait([
        _playingStateController.close(),
        _errorController.close(),
        _queueLengthController.close(),
        _nowPlayingController.close(),
      ]);
      
      stopwatch.stop();
      
      if (kDebugMode) {
        debugPrint('✅ AudioPlayerManager: Async disposal completed in ${stopwatch.elapsedMilliseconds}ms');
      }
      
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('❌ AudioPlayerManager: Error during async disposal (${stopwatch.elapsedMilliseconds}ms): $e');
      }
      
      // Force cleanup even on error to prevent stuck states
      try {
        _stateDebounceTimer?.cancel();
        _audioSettings?.removeListener(_onMuteChanged);
        clearQueue();
      } catch (cleanupError) {
        if (kDebugMode) {
          debugPrint('⚠️ AudioPlayerManager: Error during force cleanup: $cleanupError');
        }
      }
      
      rethrow;
    }
  }
  
  // Legacy sync disposal - still needed for backward compatibility
  @override
  void performDisposal() {
    if (kDebugMode) {
      debugPrint('⚠️ AudioPlayerManager: Sync disposal called - use disposeAsync() for proper cleanup');
    }
    
    // Basic cleanup for sync disposal
    _audioSettings?.removeListener(_onMuteChanged);
    clearQueue();
    _stateDebounceTimer?.cancel();
    
    // Note: We don't dispose the player here to avoid MediaCodec issues
    // The async version should be used for proper cleanup
  }

  /// Set the playback volume (0.0 = mute, 1.0 = full volume)
  Future<void> setVolume(double volume) async {
    _lastRequestedVolume = volume;
    _applyEffectiveVolume();
  }

  /// Wait for true audio completion with robust detection
  /// Ensures we've seen playing==true before waiting for completion
  /// Prevents false positive from rapid idle→completed transitions
  Future<void> _waitForTrueCompletion() async {
    if (kDebugMode) {
      print('🎵 AudioPlayerManager: Waiting for robust completion detection');
    }
    
    try {
      // Step 1: Wait for playback to actually start (playing==true)
      final playbackStarted = _audioPlayer.playingStream
        .where((playing) => playing)
        .first
        .timeout(const Duration(seconds: 10), onTimeout: () {
          throw TimeoutException('Playback never started', const Duration(seconds: 10));
        });
      
      await playbackStarted;
      
      if (kDebugMode) {
        print('🎵 AudioPlayerManager: Playback confirmed started, waiting for completion');
      }
      
      // Step 2: Now wait for true completion
      final playbackCompleted = _audioPlayer.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .first
        .timeout(const Duration(minutes: 2), onTimeout: () {
          throw TimeoutException('Playback never completed', const Duration(minutes: 2));
        });
      
      await playbackCompleted;
      
      if (kDebugMode) {
        print('🎵 AudioPlayerManager: True completion detected');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioPlayerManager: Robust completion detection failed: $e');
      }
      rethrow;
    }
  }

  /// Enhanced error detection for just_audio streams
  /// Detects idle+not playing+has duration = stream error
  StreamSubscription<ProcessingState>? _listenForStreamErrors(Completer<void> errorCompleter) {
    return _audioPlayer.processingStateStream.listen((state) {
      // Standard completion
      if (state == ProcessingState.completed) {
        if (!errorCompleter.isCompleted) {
          errorCompleter.complete();
        }
      }
      // Error detection: idle + not playing + has duration = stream error
      else if (state == ProcessingState.idle && 
               !_audioPlayer.playing && 
               _audioPlayer.duration != null) {
        if (kDebugMode) {
          print('❌ AudioPlayerManager: Stream error detected - idle with duration but not playing');
        }
        TTSStreamingMonitor().recordStreamingFailure('Player stream error: idle state with duration');
        
        if (!errorCompleter.isCompleted) {
          errorCompleter.complete(); // Treat as completion to prevent hang
        }
      }
    });
  }

  /// Clean up previous subscriptions to prevent leaks
  Future<void> _cleanupPreviousSubscriptions() async {
    // Brief delay to ensure any previous subscriptions can cleanup
    await Future.delayed(const Duration(milliseconds: 50));
    
    if (kDebugMode) {
      print('🧹 AudioPlayerManager: Cleaned up previous subscriptions');
    }
  }

  /// Play live TTS audio stream (TRUE STREAMING implementation)
  /// 
  /// This uses a custom LiveTtsAudioSource for true progressive streaming
  /// where audio starts quickly and continues as chunks arrive.
  /// 
  /// CRITICAL: This method maintains the same completion semantics as playAudioBytes()
  /// with robust completion detection that waits for playing==true first
  /// 
  /// NOTE: Now accepts either a stream or a pre-created LiveTtsAudioSource for better lifecycle management
  Future<void> playLiveTtsStream(
    dynamic audioSourceOrStream, {
    String? debugName,
    String contentType = 'audio/wav',
    VoidCallback? onNaturalCompletion, // Callback for natural ExoPlayer completion
  }) async {
    final displayName = debugName ?? 'live-tts-audio';
    final id = '${DateTime.now().microsecondsSinceEpoch}_live_${audioSourceOrStream.hashCode}';
    final startTime = DateTime.now();
    
    // Start monitoring
    TTSStreamingMonitor().recordStreamingStart();
    MemoryMonitor.setBaseline();
    
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Starting live TTS stream: $displayName (ID: $id)');
      AppLogger.d('Content-Type: $contentType');
    }

    try {
      // OVERLAP PREVENTION: Never let two TTS clips overlap
      if (_audioPlayer.playing) {
        if (kDebugMode) {
          debugPrintThrottledCustom('🔄 AudioPlayerManager: Stopping previous TTS clip to prevent overlap',
                            key: 'tts_overlap_prevention');
        }
        await _audioPlayer.stop(); // Kill the old clip first
      }
      
      // Clean up any previous subscriptions
      await _cleanupPreviousSubscriptions();
      
      // Clear force override when starting new playback
      _forceIsPlayingState = null;
      
      // Determine if we have a stream or an existing LiveTtsAudioSource
      final LiveTtsAudioSource liveSource;
      if (audioSourceOrStream is LiveTtsAudioSource) {
        // Use existing LiveTtsAudioSource (preferred for proper lifecycle management)
        liveSource = audioSourceOrStream;
        if (kDebugMode) {
          print('🎯 AudioPlayerManager: Using existing LiveTtsAudioSource for $displayName');
        }
      } else if (audioSourceOrStream is Stream<Uint8List>) {
        // Create new LiveTtsAudioSource from stream (legacy compatibility)
        liveSource = LiveTtsAudioSource(
          audioSourceOrStream,
          contentType: contentType,
          debugName: displayName,
        );
        if (kDebugMode) {
          print('🎯 AudioPlayerManager: Created new LiveTtsAudioSource for $displayName');
        }
      } else {
        throw ArgumentError('audioSourceOrStream must be either Stream<Uint8List> or LiveTtsAudioSource');
      }
      
      // Set up the live audio source with error recovery
      try {
        await _setSourceAndApplyVolume(
          () => _audioPlayer.setAudioSource(liveSource, preload: false)
        );
        
        // Start playback immediately
        await _audioPlayer.play();
        
        if (kDebugMode) {
          print('🚀 AudioPlayerManager: Started live TTS playback for $displayName');
        }
      } catch (sourceError) {
        // CRITICAL: Clean up on source error to prevent VAD/recording pipeline hanging
        if (kDebugMode) {
          print('❌ AudioPlayerManager: Live TTS source error - cleaning up: $sourceError');
        }
        
        // Reset player state
        try {
          await _audioPlayer.stop();
        } catch (stopError) {
          if (kDebugMode) {
            print('⚠️ AudioPlayerManager: Error stopping player during cleanup: $stopError');
          }
        }
        
        // Force playing state to false so VAD can restart
        _forceIsPlayingState = false;
        _emitPlayingStateImmediate(false);
        
        // Record failure for monitoring
        TTSStreamingMonitor().recordStreamingFailure('Source setup error: $sourceError');
        
        // Re-throw after cleanup
        rethrow;
      }
      
      // Create completion tracking
      final playbackCompleter = Completer<void>();
      
      // Listen for completion using natural ExoPlayer events
      StreamSubscription? subscription;
      
      subscription = _audioPlayer.processingStateStream.listen((state) {
        if (kDebugMode) {
          debugPrintThrottledCustom('🔄 Live TTS ProcessingState: $state for $displayName (playing: ${_audioPlayer.playing})',
                            key: 'live_tts_processing_state');
        }
        
        if (state == ProcessingState.completed) {
          subscription?.cancel();
          
          if (kDebugMode) {
            print('✅ Live TTS audio playback completed naturally: $displayName');
            print('🎯 Natural ExoPlayer completion - triggering VAD state transition');
            print('🕰️ Natural completion time: ${DateTime.now().difference(startTime).inMilliseconds}ms after start');
          }
          
          // CRITICAL: Clear the source to prevent any possibility of replay
          _audioPlayer.stop().catchError((e) {
            if (kDebugMode) {
              print('⚠️ AudioPlayerManager: Error stopping player after completion: $e');
            }
          });
          
          // Record successful streaming
          final latency = DateTime.now().difference(startTime).inMilliseconds;
          TTSStreamingMonitor().recordStreamingSuccess(latencyMs: latency);
          
          // Force playing state to false when completed
          _forceIsPlayingState = false;
          _emitPlayingState(false);
          
          // Notify callback that natural completion occurred
          if (kDebugMode) {
            print('🎯 Calling onNaturalCompletion callback for immediate VAD transition');
          }
          onNaturalCompletion?.call();
          
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        } else if (state == ProcessingState.ready && _audioPlayer.playing) {
          if (kDebugMode) {
            AppLogger.d('Live TTS playback started: $displayName');
          }
        }
      });

      // Error handling subscription
      StreamSubscription? errorSubscription;
      errorSubscription = _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (error) {
          // Record playback failure
          TTSStreamingMonitor().recordStreamingFailure('Live playback error: $error');
          
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.completeError(error);
          }
          errorSubscription?.cancel();
        },
      );
      
      // Wait for playback to complete
      await playbackCompleter.future;
      
      if (kDebugMode) {
        print('✅ Live TTS audio playback finished: $displayName');
      }
      
    } catch (e) {
      // Record streaming failure
      TTSStreamingMonitor().recordStreamingFailure('Live TTS exception: $e');
      
      if (kDebugMode) {
        print('❌ Error playing live TTS audio: $e');
      }
      _errorController.add('Live TTS audio playback error: $e');
      rethrow;
    }
  }


  /// Play audio directly from memory bytes (eliminates file I/O)
  /// This is the optimized path for TTS that avoids unnecessary disk writes
  Future<void> playAudioBytes(Uint8List audioBytes, {String? debugName}) async {
    if (audioBytes.isEmpty) {
      _errorController.add('Empty audio bytes provided for playback');
      throw ArgumentError('Empty audio bytes provided for playback');
    }

    // Generate unique ID for this audio request  
    final id = '${DateTime.now().microsecondsSinceEpoch}_memory_${audioBytes.hashCode}';
    final displayName = debugName ?? 'in-memory-audio';
    
    if (kDebugMode) {
      AppLogger.d('AudioPlayerManager: Playing ${audioBytes.length} bytes in-memory: $displayName (ID: $id)');
    }

    try {
      // OVERLAP PREVENTION: Never let two TTS clips overlap  
      if (_audioPlayer.playing) {
        if (kDebugMode) {
          debugPrintThrottledCustom('🔄 AudioPlayerManager: Stopping previous TTS clip to prevent overlap',
                            key: 'tts_overlap_prevention');
        }
        await _audioPlayer.stop(); // Kill the old clip first
      }
      
      // Clear force override when starting new playback
      _forceIsPlayingState = null;
      
      // Load audio from memory bytes - this is the key optimization!
      // Create a data URI from bytes for just_audio
      final base64Audio = base64Encode(audioBytes);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      await _setSourceAndApplyVolume(
        () => _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(dataUri)))
      );
      
      // Create a completer for playback completion
      final playbackCompleter = Completer<void>();
      
      // Listen for completion
      StreamSubscription? subscription;
      subscription = _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed ||
            state == ProcessingState.idle ||
            (state == ProcessingState.ready && !_audioPlayer.playing)) {
          subscription?.cancel();
          
          if (kDebugMode) {
            AppLogger.d('In-memory audio playback completed: $displayName');
          }
          
          // CRITICAL: Clear the source to prevent any possibility of replay
          _audioPlayer.stop().catchError((e) {
            if (kDebugMode) {
              print('⚠️ AudioPlayerManager: Error stopping player after completion: $e');
            }
          });
          
          // Force playing state to false when completed
          _forceIsPlayingState = false;
          _emitPlayingState(false);
          
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        }
      });
      
      // Start playback
      await _audioPlayer.play();
      
      // Wait for playback to complete
      await playbackCompleter.future;
      
      if (kDebugMode) {
        print('✅ In-memory audio playback finished: $displayName');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error playing in-memory audio: $e');
      }
      _errorController.add('Audio playback error: $e');
      rethrow;
    }
  }

  /// Check if a file path is a temporary TTS file that should be auto-cleaned
  bool _isTempTTSFile(String path) {
    return path.contains('/tts_') && 
           (path.endsWith('.wav') || path.endsWith('.mp3') || path.endsWith('.ogg'));
  }

  /// Safely delete temporary TTS files after playback
  void _safeDeleteTempFile(String path) {
    if (!_isTempTTSFile(path)) return;
    
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        if (kDebugMode) {
          print('🗑️ AudioPlayerManager: Deleted temp TTS file: $path');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ AudioPlayerManager: Failed to delete temp TTS file: $e');
      }
    }
  }
}