library;
import 'dart:math' as math;
class AmplitudeUtils {
  static const double _minDb = -60.0; // Floor for noise gate
  static const double _maxDb = -10.0; // Ceiling for clipping
  static const double _noiseGateDb = -45.0; // Noise gate threshold
  static double dbToLinear(double db) {
    if (db < _noiseGateDb) {
      return 0.0;
    }
    final clampedDb = db.clamp(_minDb, _maxDb);
    final normalized = (clampedDb - _minDb) / (_maxDb - _minDb);
    return math.pow(normalized, 0.7).toDouble().clamp(0.0, 1.0);
  }
  static double applySmoothing(double currentValue, double previousValue,
      {double alpha = 0.4}) {
    return alpha * currentValue + (1 - alpha) * previousValue;
  }
  static bool isSpeechLevel(double linearAmplitude) {
    return linearAmplitude > 0.1; // 10% threshold for visual feedback
  }
  static double amplitudeToOpacity(double linearAmplitude) {
    return (0.1 + linearAmplitude * 0.9).clamp(0.1, 1.0);
  }
  static double amplitudeToScale(double linearAmplitude) {
    return (1.0 + linearAmplitude * 1.5).clamp(1.0, 2.5);
  }
}
