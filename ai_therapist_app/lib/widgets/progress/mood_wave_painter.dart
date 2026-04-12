import 'dart:ui' as ui;

import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:flutter/material.dart';

/// CustomPainter for the mood-history wave chart.
///
/// Y-axis is emotional valence, not raw mood index — Happy plots high,
/// Neutral mid, Sad/Anxious/Angry/Stressed low. See CLAUDE.md
/// "Mood Wave Visualization" for the full mapping rationale.
class MoodWavePainter extends CustomPainter {
  final List<MapEntry<DateTime, int>> moodData;

  MoodWavePainter(this.moodData);

  @override
  void paint(Canvas canvas, Size size) {
    if (moodData.isEmpty) return;
    const double padding = 40.0;
    const double topPadding = 20.0;
    const double bottomPadding = 30.0;
    final double chartHeight = size.height - topPadding - bottomPadding;
    final double chartWidth = size.width - padding * 2;
    _drawYAxisLabels(canvas, padding, topPadding, chartHeight);
    final points = _calculatePoints(
      chartWidth,
      chartHeight,
      padding,
      topPadding,
    );
    _drawGradientFill(canvas, points, size, topPadding, chartHeight);
    _drawWaveLine(canvas, points);
    _drawMoodEmojis(canvas, points);
    _drawXAxisLabels(canvas, points, size.height - 15);
  }

  List<Offset> _calculatePoints(
    double chartWidth,
    double chartHeight,
    double padding,
    double topPadding,
  ) {
    final points = <Offset>[];
    final displayData = moodData.length > 30
        ? moodData.sublist(moodData.length - 30)
        : moodData;
    final int displayCount = displayData.length;
    for (int i = 0; i < displayCount; i++) {
      final x = padding + (i / (displayCount - 1)) * chartWidth;
      final moodIndex = displayData[i].value;
      double normalizedY;
      if (moodIndex == 0) {
        normalizedY = 0.1;
      } else if (moodIndex == 1) {
        normalizedY = 0.5;
      } else {
        normalizedY = 0.7 + ((moodIndex - 2) / 3.0) * 0.3;
      }
      final y = topPadding + normalizedY * chartHeight;
      points.add(Offset(x, y));
    }
    return points;
  }

  void _drawYAxisLabels(
    Canvas canvas,
    double padding,
    double topPadding,
    double chartHeight,
  ) {
    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final labels = [
      ('High', topPadding),
      ('Neutral', topPadding + chartHeight / 2),
      ('Low', topPadding + chartHeight),
    ];
    for (final (label, y) in labels) {
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 11,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(5, y - textPainter.height / 2),
      );
    }
  }

  void _drawGradientFill(
    Canvas canvas,
    List<Offset> points,
    Size size,
    double topPadding,
    double chartHeight,
  ) {
    if (points.isEmpty) return;
    final path = Path();
    path.moveTo(points.first.dx, size.height - 30);
    for (final point in points) {
      path.lineTo(point.dx, point.dy);
    }
    path.lineTo(points.last.dx, size.height - 30);
    path.close();
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.green.withValues(alpha: 0.3),
        Colors.amber.withValues(alpha: 0.2),
        Colors.red.withValues(alpha: 0.1),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, topPadding, size.width, chartHeight),
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  void _drawWaveLine(Canvas canvas, List<Offset> points) {
    if (points.length < 2) return;
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint = Offset(
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
      path.quadraticBezierTo(p0.dx, p0.dy, controlPoint.dx, controlPoint.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    final paint = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  void _drawMoodEmojis(Canvas canvas, List<Offset> points) {
    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final step = points.length > 10 ? (points.length / 7).ceil() : 1;
    for (int i = 0; i < points.length; i += step) {
      final point = points[i];
      final moodIndex = moodData.length > 30
          ? moodData[moodData.length - 30 + i].value
          : moodData[i].value;
      if (moodIndex >= 0 && moodIndex < Mood.values.length) {
        final mood = Mood.values[moodIndex];
        textPainter.text = TextSpan(
          text: mood.emoji,
          style: const TextStyle(fontSize: 20),
        );
        textPainter.layout();
        final circlePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 14, circlePaint);
        textPainter.paint(
          canvas,
          Offset(
            point.dx - textPainter.width / 2,
            point.dy - textPainter.height / 2,
          ),
        );
      }
    }
  }

  void _drawXAxisLabels(Canvas canvas, List<Offset> points, double y) {
    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );
    final indices = points.length > 3
        ? [0, points.length ~/ 2, points.length - 1]
        : [0, points.length - 1];
    for (final i in indices) {
      if (i >= points.length) continue;
      final dataIndex = moodData.length > 30
          ? moodData.length - 30 + i
          : i;
      if (dataIndex >= 0 && dataIndex < moodData.length) {
        final date = moodData[dataIndex].key;
        final dateStr = '${date.month}/${date.day}';
        textPainter.text = TextSpan(
          text: dateStr,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            points[i].dx - textPainter.width / 2,
            y,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(MoodWavePainter oldDelegate) {
    return oldDelegate.moodData != moodData;
  }
}
