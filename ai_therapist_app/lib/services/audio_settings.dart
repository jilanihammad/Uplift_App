// lib/services/audio_settings.dart

import 'package:flutter/foundation.dart';
import '../di/interfaces/i_audio_settings.dart';

/// Global audio settings that all audio players respect
/// This enables app-wide mute functionality without coupling
///
/// TODO: If we move to background isolates, this needs to migrate
/// to an isolate-safe stream/broadcast mechanism
class AudioSettings extends ChangeNotifier implements IAudioSettings {
  bool _isMuted = false;

  @override
  bool get isMuted => _isMuted;

  @override
  void setMuted(bool muted) {
    if (_isMuted != muted) {
      _isMuted = muted;
      if (kDebugMode) {
        debugPrint('🔇 AudioSettings: Global mute changed to $muted');
      }
      notifyListeners();
    }
  }

  /// Get the volume multiplier (0.0 when muted, 1.0 otherwise)
  @override
  double get volumeMultiplier => _isMuted ? 0.0 : 1.0;
}
