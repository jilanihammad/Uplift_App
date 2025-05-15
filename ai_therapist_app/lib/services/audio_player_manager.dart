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

  // Stream controllers
  final StreamController<bool> _playingStateController =
      StreamController<bool>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

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
        _playingStateController.add(isPlaying);

        if (kDebugMode && isPlaying) {
          print('🎧 Audio playback started');
        } else if (kDebugMode && !isPlaying) {
          print('🎧 Audio playback paused/stopped');
        }
      });

      _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          // Ensure we broadcast playback stopped when audio completes
          _playingStateController.add(false);
          if (kDebugMode) {
            print('🎧 Audio playback completed');
          }

          // Add a short delay to ensure all state changes are processed
          Future.delayed(const Duration(milliseconds: 100), () {
            // Double-check that we're actually stopped
            if (!_audioPlayer.playing) {
              _playingStateController.add(false);
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

  // Play audio from a file path
  Future<void> playAudio(String audioPath) async {
    if (audioPath.isEmpty) {
      _errorController.add('Empty audio path provided for playback');
      return;
    }

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

      // Load and play the audio
      await _audioPlayer.setFilePath(audioPath);
      await _audioPlayer.play();
    } catch (e) {
      _errorController.add('Error playing audio: $e');
      if (kDebugMode) {
        print('❌ Audio playback error: $e');
      }
    }
  }

  // Stop playing audio
  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stop();
      _playingStateController.add(false);

      if (kDebugMode) {
        print('🎧 Audio playback stopped');
      }
    } catch (e) {
      _errorController.add('Error stopping audio: $e');
      if (kDebugMode) {
        print('❌ Error stopping audio: $e');
      }
    }
  }

  // Check if audio is currently playing
  bool get isPlaying => _audioPlayer.playing;

  // Clean up resources
  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _playingStateController.close();
    await _errorController.close();
  }
}
