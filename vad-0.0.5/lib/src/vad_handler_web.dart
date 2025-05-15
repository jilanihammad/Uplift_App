// vad_handler_web.dart

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'vad_handler_base.dart';

/// Start listening for voice activity detection (JS-binding)
@JS('startListeningImpl')
external void startListeningImpl(
    double positiveSpeechThreshold,
    double negativeSpeechThreshold,
    int preSpeechPadFrames,
    int redemptionFrames,
    int frameSamples,
    int minSpeechFrames,
    bool submitUserSpeechOnPause,
    String model,
    String baseAssetPath,
    String onnxWASMBasePath);

/// Stop listening for voice activity detection (JS-binding)
@JS('stopListeningImpl')
external void stopListeningImpl();

/// Check if the VAD is currently listening (JS-binding)
@JS('isListeningNow')
external bool isListeningNow();

/// Log a message to the console (JS-binding)
@JS('logMessage')
external void logMessage(String message);

/// Execute a Dart handler (JS-binding)
@JS('callDartFunction')
external void executeDartHandler();

/// VadHandlerWeb class
class VadHandlerWeb implements VadHandlerBase {
  final StreamController<List<double>> _onSpeechEndController =
      StreamController<List<double>>.broadcast();
  final StreamController<
          ({double isSpeech, double notSpeech, List<double> frame})>
      _onFrameProcessedController = StreamController<
          ({
            double isSpeech,
            double notSpeech,
            List<double> frame
          })>.broadcast();
  final StreamController<void> _onSpeechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _onRealSpeechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _onVADMisfireController =
      StreamController<void>.broadcast();
  final StreamController<String> _onErrorController =
      StreamController<String>.broadcast();

  /// Whether to print debug messages
  bool isDebug = false;

  /// Constructor
  VadHandlerWeb({required bool isDebug}) {
    globalContext['executeDartHandler'] = handleEvent.toJS;
    isDebug = isDebug;
  }

  @override
  Stream<List<double>> get onSpeechEnd => _onSpeechEndController.stream;

  @override
  Stream<({double isSpeech, double notSpeech, List<double> frame})>
      get onFrameProcessed => _onFrameProcessedController.stream;

  @override
  Stream<void> get onSpeechStart => _onSpeechStartController.stream;

  @override
  Stream<void> get onRealSpeechStart => _onRealSpeechStartController.stream;

  @override
  Stream<void> get onVADMisfire => _onVADMisfireController.stream;

  @override
  Stream<String> get onError => _onErrorController.stream;

  @override
  void startListening(
      {double positiveSpeechThreshold = 0.5,
      double negativeSpeechThreshold = 0.35,
      int preSpeechPadFrames = 1,
      int redemptionFrames = 8,
      int frameSamples = 1536,
      int minSpeechFrames = 3,
      bool submitUserSpeechOnPause = false,
      String model = 'legacy',
      String baseAssetPath = 'assets/packages/vad/assets/',
      String onnxWASMBasePath = 'assets/packages/vad/assets/'}) {
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: startListening: Calling startListeningImpl with parameters: '
          'positiveSpeechThreshold: $positiveSpeechThreshold, '
          'negativeSpeechThreshold: $negativeSpeechThreshold, '
          'preSpeechPadFrames: $preSpeechPadFrames, '
          'redemptionFrames: $redemptionFrames, '
          'frameSamples: $frameSamples, '
          'minSpeechFrames: $minSpeechFrames, '
          'submitUserSpeechOnPause: $submitUserSpeechOnPause'
          'model: $model'
          'baseAssetPath: $baseAssetPath'
          'onnxWASMBasePath: $onnxWASMBasePath');
    }
    startListeningImpl(
        positiveSpeechThreshold,
        negativeSpeechThreshold,
        preSpeechPadFrames,
        redemptionFrames,
        frameSamples,
        minSpeechFrames,
        submitUserSpeechOnPause,
        model,
        baseAssetPath,
        onnxWASMBasePath);
  }

  /// Handle an event from the JS side
  void handleEvent(String eventType, String payload) {
    try {
      Map<String, dynamic> eventData =
          payload.isNotEmpty ? json.decode(payload) : {};

      switch (eventType) {
        case 'onError':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onError: ${eventData['error']}');
          }
          _onErrorController.add(payload);
          break;
        case 'onSpeechEnd':
          if (eventData.containsKey('audioData')) {
            final List<double> audioData = (eventData['audioData'] as List)
                .map((e) => (e as num).toDouble())
                .toList();
            if (isDebug) {
              debugPrint(
                  'VadHandlerWeb: onSpeechEnd: first 5 samples: ${audioData.sublist(0, 5)}');
            }
            _onSpeechEndController.add(audioData);
          } else {
            if (isDebug) {
              debugPrint('Invalid VAD Data received: $eventData');
            }
          }
          break;
        case 'onFrameProcessed':
          if (eventData.containsKey('probabilities') &&
              eventData.containsKey('frame')) {
            final double isSpeech =
                (eventData['probabilities']['isSpeech'] as num).toDouble();
            final double notSpeech =
                (eventData['probabilities']['notSpeech'] as num).toDouble();
            final List<double> frame = (eventData['frame'] as List)
                .map((e) => (e as num).toDouble())
                .toList();

            if (isDebug) {
              debugPrint(
                  'VadHandlerWeb: onFrameProcessed: isSpeech: $isSpeech, notSpeech: $notSpeech');
            }

            _onFrameProcessedController
                .add((isSpeech: isSpeech, notSpeech: notSpeech, frame: frame));
          } else {
            if (isDebug) {
              debugPrint('Invalid frame data received: $eventData');
            }
          }
          break;
        case 'onSpeechStart':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onSpeechStart');
          }
          _onSpeechStartController.add(null);
          break;
        case 'onRealSpeechStart':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onRealSpeechStart');
          }
          _onRealSpeechStartController.add(null);
          break;
        case 'onVADMisfire':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onVADMisfire');
          }
          _onVADMisfireController.add(null);
          break;
        default:
          debugPrint("Unknown event: $eventType");
      }
    } catch (e, st) {
      debugPrint('Error handling event: $e');
      debugPrint('Stack Trace: $st');
    }
  }

  @override
  void dispose() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: dispose');
    }
    _onSpeechEndController.close();
    _onFrameProcessedController.close();
    _onSpeechStartController.close();
    _onRealSpeechStartController.close();
    _onVADMisfireController.close();
    _onErrorController.close();
  }

  @override
  void stopListening() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: stopListening');
    }
    stopListeningImpl();
  }
}

/// Create a VAD handler for the web
/// isDebug is used to print debug messages
/// modelPath is not used in the web implementation, adding it will not have any effect
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerWeb(isDebug: isDebug);
