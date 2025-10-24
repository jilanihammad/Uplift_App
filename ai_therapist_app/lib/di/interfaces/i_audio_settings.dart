// lib/di/interfaces/i_audio_settings.dart

import 'package:flutter/foundation.dart';

/// Interface for audio settings that extends Listenable
/// This avoids duplicating addListener/removeListener
abstract class IAudioSettings extends Listenable {
  bool get isMuted;
  double get volumeMultiplier;
  void setMuted(bool muted);
}
