import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
class RNNoiseService {
  static const MethodChannel _channel = MethodChannel('rnnoise_flutter');
  static RNNoiseService? _instance;
  static RNNoiseService get instance {
    _instance ??= RNNoiseService._internal();
    return _instance!;
  }
  RNNoiseService._internal();
  bool _isInitialized = false;
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final bool result = await _channel.invokeMethod('initialize');
      _isInitialized = result;
      return result;
    } catch (e) {
      return false;
    }
  }
  Future<Int16List?> processAudioFrame(Int16List audioData) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }
    if (audioData.length != 480) {
      return null;
    }
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
  Future<Int16List?> processAudio16k(Int16List input16k) async {
    try {
      final Int16List input48k = _upsample16to48(input16k);
      final List<Int16List> frames = _splitIntoFrames(input48k, frameSize: 480);
      final List<Int16List> processedFrames = [];
      for (final frame in frames) {
        final processed = await processAudioFrame(frame);
        if (processed != null) {
          processedFrames.add(processed);
        } else {
          processedFrames.add(frame);
        }
      }
      final Int16List combined48k = _combineFrames(processedFrames);
      final Int16List output16k = _downsample48to16(combined48k);
      return output16k;
    } catch (e) {
      return null;
    }
  }
  Future<double> getVadProbability() async {
    if (!_isInitialized) return 0.0;
    try {
      final double probability =
          await _channel.invokeMethod('getVadProbability');
      return probability.clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }
  Future<void> reset() async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('reset');
    } catch (e) {}
  }
  Future<void> dispose() async {
    if (!_isInitialized) return;
    try {
      await _channel.invokeMethod('dispose');
      _isInitialized = false;
    } catch (e) {}
  }
  bool get isInitialized => _isInitialized;
  Int16List _upsample16to48(Int16List input16k) {
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
  Int16List _downsample48to16(Int16List input48k) {
    final int outputLength = input48k.length ~/ 3;
    final Int16List output16k = Int16List(outputLength);
    for (int i = 0; i < outputLength; i++) {
      final int baseIndex = i * 3;
      if (baseIndex + 2 < input48k.length) {
        final int sum = input48k[baseIndex] +
            input48k[baseIndex + 1] +
            input48k[baseIndex + 2];
        output16k[i] = (sum / 3).round();
      } else {
        output16k[i] = input48k[baseIndex];
      }
    }
    return output16k;
  }
  List<Int16List> _splitIntoFrames(Int16List audioData, {int frameSize = 480}) {
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
  Int16List _combineFrames(List<Int16List> frames) {
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
