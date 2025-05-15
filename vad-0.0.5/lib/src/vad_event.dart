// vad_event.dart
import 'dart:typed_data';

/// VadEventType enum used by non-web VAD handler
enum VadEventType {
  /// Speech start event
  start,

  /// Real speech start event
  realStart,

  /// Speech end event
  end,

  /// Frame processed event
  frameProcessed,

  /// VAD misfire event
  misfire,

  /// Error event
  error,
}

/// VadProbabilities class
class SpeechProbabilities {
  /// Probability of speech
  final double isSpeech;

  /// Probability of not speech
  final double notSpeech;

  /// Constructor
  SpeechProbabilities({required this.isSpeech, required this.notSpeech});
}

/// VadEvent class
class VadEvent {
  /// VadEventType
  final VadEventType type;

  /// Timestamp
  final double timestamp;

  /// Message
  final String message;

  /// Audio data
  final Uint8List? audioData;

  /// Speech probabilities
  final SpeechProbabilities? probabilities;

  /// Frame data
  final List<double>? frameData;

  /// Constructor
  VadEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.audioData,
    this.probabilities,
    this.frameData,
  });
}
