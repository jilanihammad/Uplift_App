import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../blocs/voice_session_bloc.dart';
import '../services/audio_player_manager.dart';
import '../services/voice_service.dart';

/// Listens for app lifecycle changes and pauses voice capture/tts when backgrounded.
class ForegroundAudioGuard with WidgetsBindingObserver {
  ForegroundAudioGuard() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _pauseVoiceFeatures();
    }
  }

  void _pauseVoiceFeatures() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<VoiceSessionBloc>()) {
      getIt<VoiceSessionBloc>().add(const StopListening(reason: 'background'));
    }
    if (getIt.isRegistered<VoiceService>()) {
      getIt<VoiceService>().stopAudio();
    }
    if (getIt.isRegistered<AudioPlayerManager>()) {
      getIt<AudioPlayerManager>().pause();
    }
  }
}
