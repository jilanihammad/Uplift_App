import 'package:vad/src/vad_iterator_base.dart';

/// VadIteratorWeb class
/// DO NOT USE
/// Not implemented for web, since Web uses JavaScript library for VAD
/// Only added for compatibility with non-web platforms
class VadIteratorWeb implements VadIteratorBase {
  @override
  void forceEndSpeech() {
    throw UnimplementedError();
  }

  @override
  Future<void> initModel(String modelPath) {
    throw UnimplementedError();
  }

  @override
  Future<void> processAudioData(List<int> data) {
    throw UnimplementedError();
  }

  @override
  void release() {
    throw UnimplementedError();
  }

  @override
  void reset() {
    throw UnimplementedError();
  }

  @override
  void setVadEventCallback(VadEventCallback callback) {
    throw UnimplementedError();
  }
}

/// Create VadHandlerNonWeb instance
VadIteratorBase createVadIterator(
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
  return VadIteratorWeb();
}
