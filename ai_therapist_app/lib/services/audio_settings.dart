// lib/services/audio_settings.dart
import 'package:flutter/foundation.dart';
import '../di/interfaces/i_audio_settings.dart';
class AudioSettings extends ChangeNotifier implements IAudioSettings {
  bool _isMuted = false;
  @override
  bool get isMuted => _isMuted;
  @override
  void setMuted(bool muted) {
    if (_isMuted != muted) {
      _isMuted = muted;
      notifyListeners();
    }
  }
  @override
  double get volumeMultiplier => _isMuted ? 0.0 : 1.0;
}
