// vad_iterator.dart
import 'package:vad/src/vad_iterator_base.dart';
import 'vad_iterator_web.dart' if (dart.library.io) 'vad_iterator_non_web.dart'
    as implementation;

/// VadIterator class
class VadIterator {
  /// Create a new instance of VadIterator
  static VadIteratorBase create(
      {required bool isDebug,
      required int sampleRate,
      required int frameSamples,
      required double positiveSpeechThreshold,
      required double negativeSpeechThreshold,
      required int redemptionFrames,
      required int preSpeechPadFrames,
      required int minSpeechFrames,
      required bool submitUserSpeechOnPause,
      required String model}) {
    return implementation.createVadIterator(
        isDebug: isDebug,
        sampleRate: sampleRate,
        frameSamples: frameSamples,
        positiveSpeechThreshold: positiveSpeechThreshold,
        negativeSpeechThreshold: negativeSpeechThreshold,
        redemptionFrames: redemptionFrames,
        preSpeechPadFrames: preSpeechPadFrames,
        minSpeechFrames: minSpeechFrames,
        submitUserSpeechOnPause: submitUserSpeechOnPause,
        model: model);
  }
}
