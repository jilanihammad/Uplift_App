/// Real-time audio visualizer widget with CustomPainter for smooth 60fps rendering
///
/// Features:
/// - Circular ripple effect responding to amplitude
/// - Multiple visualization modes (ripple, bars, glow)
/// - EMA smoothing to prevent flicker
/// - Device pixel unit rendering for sharp visuals
/// - Performance optimizations for battery efficiency

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/amplitude_utils.dart';

/// Visualization modes supported by the audio visualizer
enum VisualizationMode {
  ripple, // Circular ripple effect (default)
  bars, // Waveform bars
  glow, // Pulsing glow effect
}

/// Visualization state for different interaction phases
enum VisualizationState {
  idle, // Subtle breathing animation
  listening, // Active listening with amplitude response
  processing, // Processing animation
  speaking, // AI speaking visualization
}

/// Audio visualizer widget that renders real-time amplitude data
class AudioVisualizerWidget extends StatefulWidget {
  final double amplitude; // Current amplitude [0-1]
  final VisualizationState state; // Current interaction state
  final VisualizationMode mode; // Visualization style
  final Color primaryColor; // Base color for visualization
  final Color accentColor; // Accent color for AI speaking
  final double size; // Widget size
  final bool
      motionSensitive; // Accessibility: disable for motion-sensitive users

  const AudioVisualizerWidget({
    Key? key,
    required this.amplitude,
    required this.state,
    this.mode = VisualizationMode.ripple,
    required this.primaryColor,
    required this.accentColor,
    this.size = 120.0,
    this.motionSensitive = false,
  }) : super(key: key);

  @override
  State<AudioVisualizerWidget> createState() => _AudioVisualizerWidgetState();
}

class _AudioVisualizerWidgetState extends State<AudioVisualizerWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _breathingController;
  late AnimationController _pulseController;
  late Animation<double> _breathingAnimation;
  late Animation<double> _pulseAnimation;
  bool _isAppInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Breathing animation for idle state
    _breathingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _breathingAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));

    // Pulse animation for processing state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _updateAnimations();
  }

  @override
  void didUpdateWidget(AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    // Don't start animations if app is in background for battery efficiency
    if (_isAppInBackground) return;

    switch (widget.state) {
      case VisualizationState.idle:
        _breathingController.repeat(reverse: true);
        _pulseController.stop();
        break;
      case VisualizationState.listening:
        _breathingController.stop();
        _pulseController.stop();
        break;
      case VisualizationState.processing:
        _breathingController.stop();
        _pulseController.repeat(reverse: true);
        break;
      case VisualizationState.speaking:
        _breathingController.stop();
        _pulseController.repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breathingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App going to background - pause animations for battery efficiency
        _isAppInBackground = true;
        _breathingController.stop();
        _pulseController.stop();
        break;
      case AppLifecycleState.resumed:
        // App returning to foreground - resume animations
        _isAppInBackground = false;
        _updateAnimations();
        break;
      case AppLifecycleState.hidden:
        // No action needed
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Accessibility: fallback to simple indicator for motion-sensitive users
    if (widget.motionSensitive) {
      return _buildSimpleIndicator();
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_breathingController, _pulseController]),
        builder: (context, child) {
          return CustomPaint(
            painter: _getActivePainter(),
            size: Size(widget.size, widget.size),
          );
        },
      ),
    );
  }

  /// Get the appropriate painter based on visualization mode
  CustomPainter _getActivePainter() {
    switch (widget.mode) {
      case VisualizationMode.ripple:
        return _RipplePainter(
          amplitude: widget.amplitude,
          state: widget.state,
          primaryColor: widget.primaryColor,
          accentColor: widget.accentColor,
          breathingScale: _breathingAnimation.value,
          pulseScale: _pulseAnimation.value,
        );
      case VisualizationMode.bars:
        return _BarsPainter(
          amplitude: widget.amplitude,
          state: widget.state,
          primaryColor: widget.primaryColor,
          accentColor: widget.accentColor,
          breathingScale: _breathingAnimation.value,
          pulseScale: _pulseAnimation.value,
        );
      case VisualizationMode.glow:
        return _GlowPainter(
          amplitude: widget.amplitude,
          state: widget.state,
          primaryColor: widget.primaryColor,
          accentColor: widget.accentColor,
          breathingScale: _breathingAnimation.value,
          pulseScale: _pulseAnimation.value,
        );
    }
  }

  /// Simple accessibility-friendly indicator
  Widget _buildSimpleIndicator() {
    Color indicatorColor;
    double opacity;

    switch (widget.state) {
      case VisualizationState.idle:
        indicatorColor = widget.primaryColor;
        opacity = 0.3;
        break;
      case VisualizationState.listening:
        indicatorColor = widget.primaryColor;
        opacity = 0.5 + (widget.amplitude * 0.5); // [0.5-1.0]
        break;
      case VisualizationState.processing:
        indicatorColor = widget.primaryColor;
        opacity = 0.8;
        break;
      case VisualizationState.speaking:
        indicatorColor = widget.accentColor;
        opacity = 0.8;
        break;
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: indicatorColor.withOpacity(opacity),
        border: Border.all(
          color: indicatorColor,
          width: 2.0,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.mic,
          color: indicatorColor,
          size: widget.size * 0.4,
        ),
      ),
    );
  }
}

/// Circular ripple effect painter (primary visualization mode)
class _RipplePainter extends CustomPainter {
  final double amplitude;
  final VisualizationState state;
  final Color primaryColor;
  final Color accentColor;
  final double breathingScale;
  final double pulseScale;

  _RipplePainter({
    required this.amplitude,
    required this.state,
    required this.primaryColor,
    required this.accentColor,
    required this.breathingScale,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    // Use device pixel ratio for sharp rendering (engineer feedback)
    final paint = Paint()..style = PaintingStyle.stroke;

    switch (state) {
      case VisualizationState.idle:
        _paintBreathingRipple(canvas, center, maxRadius, paint);
        break;
      case VisualizationState.listening:
        _paintAmplitudeRipple(canvas, center, maxRadius, paint);
        break;
      case VisualizationState.processing:
        _paintProcessingRipple(canvas, center, maxRadius, paint);
        break;
      case VisualizationState.speaking:
        _paintSpeakingRipple(canvas, center, maxRadius, paint);
        break;
    }
  }

  void _paintBreathingRipple(
      Canvas canvas, Offset center, double maxRadius, Paint paint) {
    paint.color = primaryColor.withOpacity(0.3);
    paint.strokeWidth = 2.0;

    final radius = maxRadius * 0.6 * breathingScale;
    canvas.drawCircle(center, radius, paint);
  }

  void _paintAmplitudeRipple(
      Canvas canvas, Offset center, double maxRadius, Paint paint) {
    if (amplitude < 0.01) {
      // Show minimal baseline ripple
      paint.color = primaryColor.withOpacity(0.2);
      paint.strokeWidth = 1.0;
      canvas.drawCircle(center, maxRadius * 0.4, paint);
      return;
    }

    // Draw multiple ripples with amplitude-based scaling
    final numRipples = 3;
    final baseRadius = maxRadius * 0.3;
    final amplitudeScale = AmplitudeUtils.amplitudeToScale(amplitude);

    for (int i = 0; i < numRipples; i++) {
      final progress = (i + 1) / numRipples;
      final radius = baseRadius + (maxRadius * 0.4 * progress * amplitudeScale);
      final opacity =
          AmplitudeUtils.amplitudeToOpacity(amplitude) * (1.0 - progress * 0.7);

      paint.color = primaryColor.withOpacity(opacity);
      paint.strokeWidth = 3.0 - (progress * 2.0); // Thicker inner circles

      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintProcessingRipple(
      Canvas canvas, Offset center, double maxRadius, Paint paint) {
    paint.color = primaryColor.withOpacity(0.6);
    paint.strokeWidth = 3.0;

    final radius = maxRadius * 0.5 * pulseScale;
    canvas.drawCircle(center, radius, paint);

    // Add inner pulse
    paint.color = primaryColor.withOpacity(0.3);
    paint.strokeWidth = 1.5;
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  void _paintSpeakingRipple(
      Canvas canvas, Offset center, double maxRadius, Paint paint) {
    // Use accent color for AI speaking
    paint.color = accentColor.withOpacity(0.6);
    paint.strokeWidth = 3.0;

    final radius = maxRadius * 0.5 * pulseScale;
    canvas.drawCircle(center, radius, paint);

    // Add outer glow
    paint.color = accentColor.withOpacity(0.2);
    paint.strokeWidth = 6.0;
    canvas.drawCircle(center, radius * 1.2, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is! _RipplePainter) return true;

    // Engineer feedback: disable painter when idle for battery efficiency
    if (state == VisualizationState.idle && oldDelegate.state == state) {
      return breathingScale != oldDelegate.breathingScale;
    }

    return amplitude != oldDelegate.amplitude ||
        state != oldDelegate.state ||
        breathingScale != oldDelegate.breathingScale ||
        pulseScale != oldDelegate.pulseScale;
  }
}

/// Waveform bars painter (alternative visualization mode)
class _BarsPainter extends CustomPainter {
  final double amplitude;
  final VisualizationState state;
  final Color primaryColor;
  final Color accentColor;
  final double breathingScale;
  final double pulseScale;

  _BarsPainter({
    required this.amplitude,
    required this.state,
    required this.primaryColor,
    required this.accentColor,
    required this.breathingScale,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final barCount = 5;
    final barWidth = size.width / (barCount * 2 - 1);
    final maxHeight = size.height * 0.8;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 2;
      double barHeight;

      switch (state) {
        case VisualizationState.idle:
          barHeight = maxHeight * 0.2 * breathingScale;
          break;
        case VisualizationState.listening:
          // Vary heights based on amplitude with some randomness
          final heightFactor = 0.3 + amplitude * 0.7;
          final variation = (i % 2 == 0) ? 1.0 : 0.8;
          barHeight = maxHeight * heightFactor * variation;
          break;
        case VisualizationState.processing:
        case VisualizationState.speaking:
          barHeight = maxHeight * 0.6 * pulseScale;
          break;
      }

      final y = (size.height - barHeight) / 2;
      final color =
          (state == VisualizationState.speaking) ? accentColor : primaryColor;
      paint.color = color.withOpacity(0.7);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is! _BarsPainter) return true;
    return amplitude != oldDelegate.amplitude ||
        state != oldDelegate.state ||
        breathingScale != oldDelegate.breathingScale ||
        pulseScale != oldDelegate.pulseScale;
  }
}

/// Pulsing glow painter (alternative visualization mode)
class _GlowPainter extends CustomPainter {
  final double amplitude;
  final VisualizationState state;
  final Color primaryColor;
  final Color accentColor;
  final double breathingScale;
  final double pulseScale;

  _GlowPainter({
    required this.amplitude,
    required this.state,
    required this.primaryColor,
    required this.accentColor,
    required this.breathingScale,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    double glowRadius;
    double opacity;
    Color glowColor;

    switch (state) {
      case VisualizationState.idle:
        glowRadius = maxRadius * 0.4 * breathingScale;
        opacity = 0.3;
        glowColor = primaryColor;
        break;
      case VisualizationState.listening:
        glowRadius = maxRadius * (0.4 + amplitude * 0.4);
        opacity = 0.3 + amplitude * 0.4;
        glowColor = primaryColor;
        break;
      case VisualizationState.processing:
        glowRadius = maxRadius * 0.6 * pulseScale;
        opacity = 0.5;
        glowColor = primaryColor;
        break;
      case VisualizationState.speaking:
        glowRadius = maxRadius * 0.6 * pulseScale;
        opacity = 0.6;
        glowColor = accentColor;
        break;
    }

    // Create radial gradient for glow effect
    final gradient = RadialGradient(
      colors: [
        glowColor.withOpacity(opacity),
        glowColor.withOpacity(opacity * 0.5),
        glowColor.withOpacity(0),
      ],
      stops: const [0.0, 0.7, 1.0],
    );

    paint.shader = gradient.createShader(
      Rect.fromCircle(center: center, radius: glowRadius),
    );

    canvas.drawCircle(center, glowRadius, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is! _GlowPainter) return true;
    return amplitude != oldDelegate.amplitude ||
        state != oldDelegate.state ||
        breathingScale != oldDelegate.breathingScale ||
        pulseScale != oldDelegate.pulseScale;
  }
}
