import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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
class AudioPlayerManager {
  // Audio player instance
  final AudioPlayer _audioPlayer = AudioPlayer();

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
  AudioPlayerManager() {
    _initAudioPlayer();
  }

  // Helper method to emit playing state only if it changed
  void _emitPlayingState(bool isPlaying) {
    if (_lastEmittedPlayingState != isPlaying) {
      _lastEmittedPlayingState = isPlaying;
      _playingStateController.add(isPlaying);
      if (kDebugMode) {
        print('🎧 AudioPlayerManager: Playing state changed to $isPlaying');
      }
    }
  }

  // Initialize the audio player
  Future<void> _initAudioPlayer() async {
    try {
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
          print('🎧 Audio playback started');
        } else if (kDebugMode && !isPlaying) {
          print('🎧 Audio playback paused/stopped');
        }
      });

      _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          // Ensure we broadcast playback stopped when audio completes
          _emitPlayingState(false);
          if (kDebugMode) {
            print('🎧 Audio playback completed');
          }

          // Add a short delay to ensure all state changes are processed
          Future.delayed(const Duration(milliseconds: 100), () {
            // Double-check that we're actually stopped
            if (!_audioPlayer.playing) {
              _emitPlayingState(false);
              if (kDebugMode) {
                print('🎧 Audio playback completion confirmed');
              }
            }
            
            // Process next item in queue after current completes
            _processNextInQueue();
          });
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
        print('🎧 AudioPlayerManager: $error');
      }
      _errorController.add(error);
      completer.completeError(Exception(error));
      return completer.future;
    }

    // Add to queue
    _audioQueue.add(queueItem);
    _queueLengthController.add(_audioQueue.length);
    
    if (kDebugMode) {
      print('🎧 AudioPlayerManager: Added to queue: $audioPath (ID: $id, Queue length: ${_audioQueue.length})');
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
        print('🎧 AudioPlayerManager: Processing queue item: ${item.audioPath} (ID: ${item.id}, Remaining in queue: ${_audioQueue.length})');
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
      print('🎧 AudioPlayerManager: Queue processing completed');
    }
  }

  /// Process next item in queue (called after current playback completes)
  void _processNextInQueue() {
    if (!_isProcessingQueue && _audioQueue.isNotEmpty) {
      if (kDebugMode) {
        print('🎧 AudioPlayerManager: Auto-processing next in queue');
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
        print('🎧 Playing audio from: ${item.audioPath} (size: $fileSize bytes, waited: ${waitTime}ms)');
      }

      // Stop any current playback
      await _audioPlayer.stop();

      // Clear force override when starting new playback
      _forceIsPlayingState = null;

      // Load and play the audio
      await _audioPlayer.setFilePath(item.audioPath);
      
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
          print('🎧 AudioPlayerManager: Started playback for ${item.audioPath} (ID: ${item.id})');
        }
      }

      // Wait for playback to complete
      await playbackCompleter.future;
      
      // Complete the item's completer
      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
      
      if (kDebugMode) {
        print('🎧 AudioPlayerManager: Completed playback for ${item.audioPath} (ID: ${item.id})');
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
      _emitPlayingState(false);

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
        print('🎧 AudioPlayerManager: Audio playback stopped - isPlaying forced to false, queue cleared: $clearQueue');
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
    _emitPlayingState(false);
    if (kDebugMode) {
      print('🎧 AudioPlayerManager: Playing state forced to false');
    }
  }

  // Check if audio is currently playing
  bool get isPlaying {
    // If we have a force override, use that
    if (_forceIsPlayingState != null) {
      if (kDebugMode) {
        print('🎧 AudioPlayerManager.isPlaying: Using force override = $_forceIsPlayingState');
      }
      return _forceIsPlayingState!;
    }
    // Otherwise use the actual player state
    final actualState = _audioPlayer.playing;
    if (kDebugMode) {
      print('🎧 AudioPlayerManager.isPlaying: Using actual player state = $actualState');
    }
    return actualState;
  }

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
        print('🎧 AudioPlayerManager: Skipping current audio: ${_currentlyPlaying!.audioPath}');
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
      print('🎧 AudioPlayerManager: Clearing queue (${_audioQueue.length} items)');
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

  // Clean up resources
  Future<void> dispose() async {
    // Clear queue and complete all pending items
    clearQueue();
    
    await _audioPlayer.dispose();
    await _playingStateController.close();
    await _errorController.close();
    await _queueLengthController.close();
    await _nowPlayingController.close();
  }

  /// Set the playback volume (0.0 = mute, 1.0 = full volume)
  Future<void> setVolume(double volume) async {
    try {
      await _audioPlayer.setVolume(volume);
      if (kDebugMode) {
        print('🎧 AudioPlayerManager: Volume set to $volume');
      }
    } catch (e) {
      _errorController.add('Error setting volume: $e');
      if (kDebugMode) {
        print('❌ Error setting volume: $e');
      }
    }
  }
}