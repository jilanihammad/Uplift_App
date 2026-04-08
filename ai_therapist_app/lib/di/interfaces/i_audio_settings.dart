// lib/di/interfaces/i_audio_settings.dart
import 'package:flutter/foundation.dart';
abstract class IAudioSettings extends Listenable {
  bool get isMuted;
  double get volumeMultiplier;
  void setMuted(bool muted);
}
