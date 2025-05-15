import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:vad/src/vad_iterator_base.dart';

import 'vad_event.dart';

/// Voice Activity Detection (VAD) iterator for real-time audio processing.
class VadIteratorNonWeb implements VadIteratorBase {
  /// Debug flag to enable/disable logging.
  bool isDebug = false;

  /// Threshold for positive speech detection.
  double positiveSpeechThreshold = 0.5;

  /// Threshold for negative speech detection.
  double negativeSpeechThreshold = 0.35;

  /// Number of frames for redemption after speech detection.
  int redemptionFrames = 8;

  /// Number of samples in a frame.
  /// Default is 1536 samples for 96ms at 16kHz sample rate.
  /// * > WARNING! Silero VAD models were trained using 512, 1024, 1536 samples for 16000 sample rate and 256, 512, 768 samples for 8000 sample rate.
  /// * > Values other than these may affect model perfomance!!
  /// * In this context, audio fed to the VAD model always has sample rate 16000. It is probably a good idea to leave this at 1536.
  int frameSamples = 1536;

  /// Number of frames to pad before speech detection.
  int preSpeechPadFrames = 1;

  /// Minimum number of speech frames to consider as valid speech.
  int minSpeechFrames = 3;

  /// Sample rate of the audio data.
  int sampleRate = 16000;

  /// Flag to submit user speech on pause/stop event.
  bool submitUserSpeechOnPause = false;

  /// Model name
  /// * 'legacy' for Silero VAD Legacy model
  /// * 'v5' for Silero VAD v5 model
  String model;

  // Internal variables
  /// Flag to indicate speech detection state.
  bool speaking = false;

  /// Counter for speech redemption frames.
  int redemptionCounter = 0;

  /// Counter for positive speech frames.
  int speechPositiveFrameCount = 0;
  int _currentSample = 0; // To track position in samples

  /// Buffers for pre-speech and speech data.
  List<Float32List> preSpeechBuffer = [];

  /// Buffer for speech data.
  List<Float32List> speechBuffer = [];

  // Model variables
  OrtSessionOptions? _sessionOptions;
  OrtSession? _session;

  // Model states
  static const int _batch = 1;
  var _hide = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
  var _cell = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
  var _state = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));

  /// Callback for VAD events.
  VadEventCallback? onVadEvent;

  /// Byte buffer for audio data.
  final List<int> _byteBuffer = [];

  /// Size of a frame in bytes.
  int frameByteCount;

  /// Create a new VAD iterator.
  VadIteratorNonWeb({
    required this.isDebug,
    required this.sampleRate,
    required this.frameSamples,
    required this.positiveSpeechThreshold,
    required this.negativeSpeechThreshold,
    required this.redemptionFrames,
    required this.preSpeechPadFrames,
    required this.minSpeechFrames,
    required this.submitUserSpeechOnPause,
    required this.model,
  }) : frameByteCount = frameSamples * 2;

  /// Initialize the VAD model from the given [modelPath].
  @override
  Future<void> initModel(String modelPath) async {
    try {
      _sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      final rawAssetFile = await rootBundle.load(modelPath);
      final bytes = rawAssetFile.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      if (isDebug) debugPrint('VAD model initialized from $modelPath.');
    } catch (e) {
      debugPrint('VAD model initialization failed: $e');
      onVadEvent?.call(VadEvent(
        type: VadEventType.error,
        timestamp: _getCurrentTimestamp(),
        message: 'VAD model initialization failed: $e',
      ));
    }
  }

  /// Reset the VAD iterator.
  @override
  void reset() {
    speaking = false;
    redemptionCounter = 0;
    speechPositiveFrameCount = 0;
    _currentSample = 0;
    preSpeechBuffer.clear();
    speechBuffer.clear();
    _byteBuffer.clear();
    _hide = List.filled(
        2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
    _cell = List.filled(
        2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
    _state = List.filled(
        2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));
  }

  /// Release the VAD iterator resources.
  @override
  void release() {
    _sessionOptions?.release();
    _sessionOptions = null;
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
  }

  /// Set the VAD event callback.
  @override
  void setVadEventCallback(VadEventCallback callback) {
    onVadEvent = callback;
  }

  /// Process audio data.
  @override
  Future<void> processAudioData(List<int> data) async {
    _byteBuffer.addAll(data);

    while (_byteBuffer.length >= frameByteCount) {
      final frameBytes = _byteBuffer.sublist(0, frameByteCount);
      _byteBuffer.removeRange(0, frameByteCount);
      final frameData = _convertBytesToFloat32(Uint8List.fromList(frameBytes));
      await _processFrame(Float32List.fromList(frameData));
    }
  }

  /// Process a single frame of audio data.
  Future<void> _processFrame(Float32List data) async {
    if (_session == null) {
      debugPrint('VAD Iterator: Session not initialized.');
      return;
    }

    final (speechProb, modelOutputs) = await _runModelInference(data);

    // Create a copy of the frame data for the event
    final frameData = data.toList();

    // Emit the frame processed event
    onVadEvent?.call(VadEvent(
      type: VadEventType.frameProcessed,
      timestamp: _getCurrentTimestamp(),
      message:
          'Frame processed at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
      probabilities: SpeechProbabilities(
          isSpeech: speechProb, notSpeech: 1.0 - speechProb),
      frameData: frameData,
    ));

    for (var element in modelOutputs) {
      element?.release();
    }

    _currentSample += frameSamples;
    _handleStateTransitions(speechProb, data);
  }

  /// Run model inference based on the selected model version
  Future<(double, List<OrtValue?>)> _runModelInference(Float32List data) async {
    if (model == 'v5') {
      return _runV5ModelInference(data);
    } else {
      return _runLegacyModelInference(data);
    }
  }

  /// Run inference for Silero VAD v5 model
  Future<(double, List<OrtValue?>)> _runV5ModelInference(
      Float32List data) async {
    final inputOrt =
        OrtValueTensor.createTensorWithDataList(data, [_batch, frameSamples]);
    final srOrt = OrtValueTensor.createTensorWithData(sampleRate);
    final stateOrt = OrtValueTensor.createTensorWithDataList(_state);
    final runOptions = OrtRunOptions();

    final inputs = {'input': inputOrt, 'sr': srOrt, 'state': stateOrt};
    final outputs = _session!.run(runOptions, inputs);

    inputOrt.release();
    srOrt.release();
    stateOrt.release();
    runOptions.release();

    final speechProb = (outputs[0]?.value as List<List<double>>)[0][0];
    _state = (outputs[1]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();

    return (speechProb, outputs);
  }

  /// Run inference for Silero VAD Legacy model
  Future<(double, List<OrtValue?>)> _runLegacyModelInference(
      Float32List data) async {
    final inputOrt =
        OrtValueTensor.createTensorWithDataList(data, [_batch, frameSamples]);
    final srOrt = OrtValueTensor.createTensorWithData(sampleRate);
    final hOrt = OrtValueTensor.createTensorWithDataList(_hide);
    final cOrt = OrtValueTensor.createTensorWithDataList(_cell);
    final runOptions = OrtRunOptions();

    final inputs = {'input': inputOrt, 'sr': srOrt, 'h': hOrt, 'c': cOrt};
    final outputs = _session!.run(runOptions, inputs);

    inputOrt.release();
    srOrt.release();
    hOrt.release();
    cOrt.release();
    runOptions.release();

    final speechProb = (outputs[0]?.value as List<List<double>>)[0][0];
    _hide = (outputs[1]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();
    _cell = (outputs[2]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();

    return (speechProb, outputs);
  }

  /// Handle state transitions based on speech probability
  void _handleStateTransitions(double speechProb, Float32List data) {
    if (speechProb >= positiveSpeechThreshold) {
      // Speech-positive frame
      if (!speaking) {
        speaking = true;
        onVadEvent?.call(VadEvent(
          type: VadEventType.start,
          timestamp: _getCurrentTimestamp(),
          message:
              'Speech started at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        ));
        speechBuffer.addAll(preSpeechBuffer);
        preSpeechBuffer.clear();
      }
      redemptionCounter = 0;
      speechBuffer.add(data);
      speechPositiveFrameCount++;

      // Add validation event when speech frames exceed minimum threshold
      if (speechPositiveFrameCount == minSpeechFrames) {
        onVadEvent?.call(VadEvent(
          type: VadEventType.realStart,
          timestamp: _getCurrentTimestamp(),
          message:
              'Speech validated at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        ));
      }
    } else if (speechProb < negativeSpeechThreshold) {
      // Handle speech-negative frame
      _handleSpeechNegativeFrame(data);
    } else {
      // Probability between thresholds
      _handleIntermediateFrame(data);
    }
  }

  /// Handle speech-negative frame
  void _handleSpeechNegativeFrame(Float32List data) {
    if (speaking) {
      if (++redemptionCounter >= redemptionFrames) {
        // End of speech
        speaking = false;
        redemptionCounter = 0;

        if (speechPositiveFrameCount >= minSpeechFrames) {
          // Valid speech segment
          onVadEvent?.call(VadEvent(
            type: VadEventType.end,
            timestamp: _getCurrentTimestamp(),
            message:
                'Speech ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
            audioData: _combineSpeechBuffer(),
          ));
        } else {
          // Misfire
          onVadEvent?.call(VadEvent(
            type: VadEventType.misfire,
            timestamp: _getCurrentTimestamp(),
            message:
                'Misfire detected at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
          ));
        }
        // Reset counters and buffers
        speechPositiveFrameCount = 0;
        speechBuffer.clear();
      } else {
        speechBuffer.add(data);
      }
    } else {
      // Not speaking, maintain pre-speech buffer
      _addToPreSpeechBuffer(data);
    }
  }

  /// Handle frame with probability between thresholds
  void _handleIntermediateFrame(Float32List data) {
    if (speaking) {
      speechBuffer.add(data);
      redemptionCounter = 0;
    } else {
      _addToPreSpeechBuffer(data);
    }
  }

  /// Forcefully end speech detection on pause/stop event.
  @override
  void forceEndSpeech() {
    if (speaking && speechPositiveFrameCount >= minSpeechFrames) {
      if (isDebug) debugPrint('VAD Iterator: Forcing speech end.');
      onVadEvent?.call(VadEvent(
        type: VadEventType.end,
        timestamp: _getCurrentTimestamp(),
        message:
            'Speech forcefully ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        audioData: _combineSpeechBuffer(),
      ));
      // Reset state
      speaking = false;
      redemptionCounter = 0;
      speechPositiveFrameCount = 0;
      speechBuffer.clear();
      preSpeechBuffer.clear();
    }
  }

  void _addToPreSpeechBuffer(Float32List data) {
    preSpeechBuffer.add(data);
    while (preSpeechBuffer.length > preSpeechPadFrames) {
      preSpeechBuffer.removeAt(0);
    }
  }

  double _getCurrentTimestamp() {
    return _currentSample / sampleRate;
  }

  Uint8List _combineSpeechBuffer() {
    final int totalLength =
        speechBuffer.fold(0, (sum, frame) => sum + frame.length);
    final Float32List combined = Float32List(totalLength);
    int offset = 0;
    for (var frame in speechBuffer) {
      combined.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    final int16Data = Int16List.fromList(
        combined.map((e) => (e * 32767).clamp(-32768, 32767).toInt()).toList());
    final Uint8List audioData = Uint8List.view(int16Data.buffer);
    return audioData;
  }

  List<double> _convertBytesToFloat32(Uint8List data) {
    final buffer = data.buffer;
    final int16List = Int16List.view(buffer);
    return int16List.map((e) => e / 32768.0).toList();
  }
}

/// Create VadHandlerNonWeb instance
VadIteratorBase createVadIterator({
  required bool isDebug,
  required int sampleRate,
  required int frameSamples,
  required double positiveSpeechThreshold,
  required double negativeSpeechThreshold,
  required int redemptionFrames,
  required int preSpeechPadFrames,
  required int minSpeechFrames,
  required bool submitUserSpeechOnPause,
  required String model,
}) {
  return VadIteratorNonWeb(
    isDebug: isDebug,
    sampleRate: sampleRate,
    frameSamples: frameSamples,
    positiveSpeechThreshold: positiveSpeechThreshold,
    negativeSpeechThreshold: negativeSpeechThreshold,
    redemptionFrames: redemptionFrames,
    preSpeechPadFrames: preSpeechPadFrames,
    minSpeechFrames: minSpeechFrames,
    submitUserSpeechOnPause: submitUserSpeechOnPause,
    model: model,
  );
}
