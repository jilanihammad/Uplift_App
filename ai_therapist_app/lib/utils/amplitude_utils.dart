/// Utility functions for audio amplitude processing and visualization
/// 
/// Converts raw dB values from VAD to normalized [0-1] linear scale suitable for UI
import 'dart:math' as math;

class AmplitudeUtils {
  // Constants for amplitude processing
  static const double _minDb = -60.0;  // Floor for noise gate
  static const double _maxDb = -10.0;  // Ceiling for clipping
  static const double _noiseGateDb = -45.0;  // Noise gate threshold
  
  /// Convert dB amplitude to linear [0-1] scale with noise gate
  /// 
  /// - Input: dB value (typically -120 to 0)
  /// - Output: Linear amplitude [0-1] for UI visualization
  /// - Applies noise gate to eliminate background noise
  static double dbToLinear(double db) {
    // Apply noise gate - values below threshold become 0
    if (db < _noiseGateDb) {
      return 0.0;
    }
    
    // Clamp to our working range
    final clampedDb = db.clamp(_minDb, _maxDb);
    
    // Convert to linear [0-1] scale
    final normalized = (clampedDb - _minDb) / (_maxDb - _minDb);
    
    // Apply slight curve for better visual response
    return math.pow(normalized, 0.7).toDouble().clamp(0.0, 1.0);
  }
  
  /// Apply exponential moving average smoothing to reduce flicker
  /// 
  /// - currentValue: New amplitude value
  /// - previousValue: Previous smoothed value
  /// - alpha: Smoothing factor (0.4 recommended by engineer)
  static double applySmoothing(double currentValue, double previousValue, {double alpha = 0.4}) {
    return alpha * currentValue + (1 - alpha) * previousValue;
  }
  
  /// Check if amplitude is above speech threshold for visualization
  static bool isSpeechLevel(double linearAmplitude) {
    return linearAmplitude > 0.1; // 10% threshold for visual feedback
  }
  
  /// Convert linear amplitude to opacity for ripple effects
  /// Maps [0-1] input to [0.1-1.0] output for visibility
  static double amplitudeToOpacity(double linearAmplitude) {
    return (0.1 + linearAmplitude * 0.9).clamp(0.1, 1.0);
  }
  
  /// Convert linear amplitude to scale factor for ripple radius
  /// Maps [0-1] input to [1.0-2.5] output for dynamic sizing
  static double amplitudeToScale(double linearAmplitude) {
    return (1.0 + linearAmplitude * 1.5).clamp(1.0, 2.5);
  }
}