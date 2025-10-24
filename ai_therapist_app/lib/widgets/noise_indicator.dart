import 'package:flutter/material.dart';
import '../services/vad_manager.dart';

/// Widget that shows the current noise environment status
class NoiseIndicator extends StatefulWidget {
  final VADManager vadManager;
  final bool showDetails;

  const NoiseIndicator({
    super.key,
    required this.vadManager,
    this.showDetails = false,
  });

  @override
  State<NoiseIndicator> createState() => _NoiseIndicatorState();
}

class _NoiseIndicatorState extends State<NoiseIndicator> {
  Map<String, dynamic>? _noiseInfo;

  @override
  void initState() {
    super.initState();
    _updateNoiseInfo();

    // Update noise info periodically
    Future.doWhile(() async {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          _updateNoiseInfo();
        }
        return mounted;
      }
      return false;
    });
  }

  void _updateNoiseInfo() {
    final info = widget.vadManager.getNoiseInfo();
    if (mounted && info != _noiseInfo) {
      setState(() {
        _noiseInfo = info;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_noiseInfo == null) return const SizedBox.shrink();

    final isCalibrated = _noiseInfo!['isCalibrated'] as bool;
    final isVeryNoisy = _noiseInfo!['isVeryNoisy'] as bool;
    final noiseFloor = _noiseInfo!['noiseFloor'] as double;

    if (!isCalibrated) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Calibrating microphone...',
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (isVeryNoisy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up,
              size: 16,
              color: Colors.orange[700],
            ),
            const SizedBox(width: 8),
            Text(
              'Noisy environment detected',
              style: TextStyle(
                color: Colors.orange[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.showDetails) ...[
              const SizedBox(width: 4),
              Text(
                '(${noiseFloor.toStringAsFixed(0)} dB)',
                style: TextStyle(
                  color: Colors.orange[600],
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Show good environment indicator (optional)
    if (widget.showDetails) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 16,
              color: Colors.green[700],
            ),
            const SizedBox(width: 8),
            Text(
              'Good audio environment',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(${noiseFloor.toStringAsFixed(0)} dB)',
              style: TextStyle(
                color: Colors.green[600],
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
