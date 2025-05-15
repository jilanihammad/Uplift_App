// vad_iterator_base.dart
import 'vad_event.dart';

/// Base class for Voice Activity Detection (VAD) iterator.
/// Only used for non-web platforms.
/// It is internally used by the [VadHandlerNonWeb] class.
/// But it can be used directly for more control over the VAD process. For example, to process non-streaming audio data.

abstract class VadIteratorBase {
  /// Initialize the VAD model from the given [modelPath].
  Future<void> initModel(String modelPath);

  /// Reset the VAD iterator.
  void reset();

  /// Release the VAD iterator resources.
  void release();

  /// Set the VAD event callback.
  void setVadEventCallback(VadEventCallback callback);

  /// Process audio data.
  Future<void> processAudioData(List<int> data);

  /// Forcefully end speech detection on pause/stop event.
  void forceEndSpeech();
}

/// Callback for VAD events.
typedef VadEventCallback = void Function(VadEvent event);
