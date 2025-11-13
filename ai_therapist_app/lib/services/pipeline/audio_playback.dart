// Audio playback abstraction for the voice pipeline controller.

import '../audio_player_manager.dart';

abstract class AudioPlayback {
  Stream<bool> get isPlayingStream;
  Future<void> playFile(String audioPath);
  Future<void> stop({bool clearQueue});
}

class AudioPlayerManagerPlayback implements AudioPlayback {
  final AudioPlayerManager audioPlayerManager;

  AudioPlayerManagerPlayback(this.audioPlayerManager);

  @override
  Stream<bool> get isPlayingStream => audioPlayerManager.isPlayingStream;

  @override
  Future<void> playFile(String audioPath) =>
      audioPlayerManager.playAudio(audioPath);

  @override
  Future<void> stop({bool clearQueue = true}) =>
      audioPlayerManager.stopAudio(clearQueue: clearQueue);
}
