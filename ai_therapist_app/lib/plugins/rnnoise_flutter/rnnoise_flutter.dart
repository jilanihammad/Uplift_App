import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
class RNNoiseFlutter {
  static const MethodChannel _channel = MethodChannel('rnnoise_flutter');
  static final RNNoiseFlutter _instance = RNNoiseFlutter._internal();
  static RNNoiseFlutter get instance => _instance;
  RNNoiseFlutter._internal();
  Future<bool> initialize() async {
    try {
      final bool result = await _channel.invokeMethod('initialize');
      return result;
    } catch (e) {
      return false;
    }
  }
  Future<Int16List?> processAudio(Int16List audioData) async {
    try {
      final Uint8List result = await _channel.invokeMethod(
        'processAudio',
        {'audioData': audioData},
      );
      final ByteData byteData = ByteData.sublistView(result);
      final Int16List processedAudio = Int16List(result.length ~/ 2);
      for (int i = 0; i < processedAudio.length; i++) {
        processedAudio[i] = byteData.getInt16(i * 2, Endian.little);
      }
      return processedAudio;
    } catch (e) {
      return null;
    }
  }
  Stream<Int16List> processAudioStream(Stream<Int16List> inputStream) async* {
    await for (final audioFrame in inputStream) {
      final processedFrame = await processAudio(audioFrame);
      if (processedFrame != null) {
        yield processedFrame;
      }
    }
  }
  Future<double> getVadProbability() async {
    try {
      final double probability =
          await _channel.invokeMethod('getVadProbability');
      return probability.clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }
  Future<void> reset() async {
    try {
      await _channel.invokeMethod('reset');
    } catch (e) {}
  }
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } catch (e) {}
  }
  Future<bool> isInitialized() async {
    try {
      final bool initialized = await _channel.invokeMethod('isInitialized');
      return initialized;
    } catch (e) {
      return false;
    }
  }
}
class RNNoiseAudioUtils {
  static Int16List upsample16to48(Int16List input16k) {
    final int outputLength = input16k.length * 3;
    final Int16List output48k = Int16List(outputLength);
    for (int i = 0; i < input16k.length; i++) {
      final int baseIndex = i * 3;
      final int currentSample = input16k[i];
      final int nextSample =
          (i + 1 < input16k.length) ? input16k[i + 1] : currentSample;
      output48k[baseIndex] = currentSample;
      output48k[baseIndex + 1] = ((currentSample * 2 + nextSample) / 3).round();
      output48k[baseIndex + 2] = ((currentSample + nextSample * 2) / 3).round();
    }
    return output48k;
  }
  static Int16List downsample48to16(Int16List input48k) {
    final int outputLength = input48k.length ~/ 3;
    final Int16List output16k = Int16List(outputLength);
    for (int i = 0; i < outputLength; i++) {
      final int baseIndex = i * 3;
      final int sum = input48k[baseIndex] +
          input48k[baseIndex + 1] +
          input48k[baseIndex + 2];
      output16k[i] = (sum / 3).round();
    }
    return output16k;
  }
  static List<Int16List> splitIntoFrames(Int16List audioData,
      {int frameSize = 480}) {
    final List<Int16List> frames = [];
    for (int i = 0; i < audioData.length; i += frameSize) {
      final int endIndex =
          (i + frameSize < audioData.length) ? i + frameSize : audioData.length;
      final Int16List frame = Int16List(frameSize);
      final int actualFrameSize = endIndex - i;
      for (int j = 0; j < actualFrameSize; j++) {
        frame[j] = audioData[i + j];
      }
      for (int j = actualFrameSize; j < frameSize; j++) {
        frame[j] = 0;
      }
      frames.add(frame);
    }
    return frames;
  }
  static Int16List combineFrames(List<Int16List> frames) {
    if (frames.isEmpty) return Int16List(0);
    final int totalLength = frames.length * frames.first.length;
    final Int16List combined = Int16List(totalLength);
    for (int i = 0; i < frames.length; i++) {
      final int baseIndex = i * frames[i].length;
      for (int j = 0; j < frames[i].length; j++) {
        combined[baseIndex + j] = frames[i][j];
      }
    }
    return combined;
  }
}
