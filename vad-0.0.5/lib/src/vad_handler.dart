// vad_handler.dart

import 'package:vad/src/vad_handler_base.dart';
import 'vad_handler_web.dart' if (dart.library.io) 'vad_handler_non_web.dart'
    as implementation;

/// VadHandler class
class VadHandler {
  /// Create a new instance of VadHandler.
  /// [isDebug] flag
  /// [modelPath] path to the model file (optional and only used for non-web)
  /// For Silero V4, Default model path is 'assets/packages/vad/assets/silero_vad_legacy.onnx'.
  /// For Silero V5, Default model path is 'assets/packages/vad/assets/silero_vad_v5.onnx'.
  /// Leaving the model path empty will use the default model path based on the model parameter in the startListening method.
  /// Available models: 'legacy', 'v5'.
  /// Returns a new instance of VadHandlerBase.
  static VadHandlerBase create({required bool isDebug, String modelPath = ''}) {
    return implementation.createVadHandler(
        isDebug: isDebug, modelPath: modelPath);
  }
}
