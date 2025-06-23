import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Manages audio playback functionality
///
/// Responsible for playing audio files and managing playback state
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

  // Track last emitted playing state to prevent duplicate broadcasts
  bool? _lastEmittedPlayingState;
  
  // CRITICAL FIX: Mutex to prevent concurrent playAudio calls
  bool _isPlayingAudio = false;

  // Streams for external components to listen to
  Stream<bool> get isPlayingStream => _playingStateController.stream;
  Stream<String?> get errorStream => _errorController.stream;

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

  // CRITICAL FIX: Play audio with mutex to prevent concurrent calls
  Future<void> playAudio(String audioPath) async {
    if (audioPath.isEmpty) {
      _errorController.add('Empty audio path provided for playback');
      return;
    }

    // MUTEX: Prevent concurrent playAudio calls 
    if (_isPlayingAudio) {
      if (kDebugMode) {
        print('🎧 AudioPlayerManager: BLOCKED concurrent playAudio call for: $audioPath');
      }
      return;
    }
    
    _isPlayingAudio = true;

    final Completer<void> completer = Completer<void>();

    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        _errorController.add('Audio file does not exist: $audioPath');
        return;
      }

      if (kDebugMode) {
        final fileSize = await file.length();
        print('🎧 Playing audio from: $audioPath (size: $fileSize bytes)');
        // Optionally, try to get duration if possible (requires just_audio or similar)
      }

      // Stop any current playback
      await _audioPlayer.stop();

      // Clear force override when starting new playback
      _forceIsPlayingState = null;

      // Load and play the audio
      await _audioPlayer.setFilePath(audioPath);
      if (!_audioPlayer.playing) {
        await _audioPlayer.play();
        if (kDebugMode) {
          print('🎧 AudioPlayerManager: Started playback for $audioPath');
        }
      } else {
        if (kDebugMode) {
          print('🎧 AudioPlayerManager: Skipped redundant play() call - already playing');
        }
      }

      // Listen for completion and all terminal states
      StreamSubscription? subscription;
      subscription = _audioPlayer.processingStateStream.listen((state) {
        // Release mutex on any terminal state
        if (state == ProcessingState.completed ||
            state == ProcessingState.idle ||  // playback aborted
            (state == ProcessingState.ready && !_audioPlayer.playing)) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          subscription?.cancel();
          // CRITICAL: Release mutex on any terminal outcome
          _isPlayingAudio = false;
        }
      });
    } catch (e) {
      _errorController.add('Error playing audio: $e');
      if (kDebugMode) {
        print('❌ Audio playback error: $e');
      }
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      // Release mutex on error
      _isPlayingAudio = false;
    }
    return completer.future;
  }

  // Stop playing audio
  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();

      // Force the state to false immediately
      _forceIsPlayingState = false;
      _emitPlayingState(false);

      if (kDebugMode) {
        print(
            '�� AudioPlayerManager: Audio playback stopped - isPlaying forced to false');
      }
    } catch (e) {
      _errorController.add('Error stopping audio: $e');
      if (kDebugMode) {
        print('❌ Error stopping audio: $e');
      }
    } finally {
      // CRITICAL: Clear mutex when manually stopping audio
      _isPlayingAudio = false;
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
        print(
            '🎧 AudioPlayerManager.isPlaying: Using force override = $_forceIsPlayingState');
      }
      return _forceIsPlayingState!;
    }
    // Otherwise use the actual player state
    final actualState = _audioPlayer.playing;
    if (kDebugMode) {
      print(
          '🎧 AudioPlayerManager.isPlaying: Using actual player state = $actualState');
    }
    return actualState;
  }

  // Clean up resources
  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _playingStateController.close();
    await _errorController.close();
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
