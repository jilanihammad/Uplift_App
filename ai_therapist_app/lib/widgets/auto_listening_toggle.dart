import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/voice_service.dart';
import '../services/auto_listening_coordinator.dart';

/// Widget for toggling between automatic and manual recording modes
class AutoListeningToggle extends StatefulWidget {
  /// Voice service instance
  final VoiceService voiceService;

  /// Callback for when auto mode is toggled
  final Function(bool isEnabled)? onToggle;

  const AutoListeningToggle({
    super.key,
    required this.voiceService,
    this.onToggle,
  });

  @override
  State<AutoListeningToggle> createState() => _AutoListeningToggleState();
}

class _AutoListeningToggleState extends State<AutoListeningToggle> {
  bool _isAutoModeEnabled = false;
  AutoListeningState _currentState = AutoListeningState.idle;

  @override
  void initState() {
    super.initState();
    // Set auto mode to true by default
    _isAutoModeEnabled = true;

    // Listen for auto mode state changes
    widget.voiceService.autoListeningStateStream.listen((state) {
      setState(() {
        _currentState = state;
        if (kDebugMode) {
          print('[AutoListeningToggle] State changed: $_currentState');
        }
      });
    });

    // Enable auto mode when the widget initializes
    Future.microtask(() async {
      await widget.voiceService.enableAutoMode();
      setState(() {
        _isAutoModeEnabled = true; // Always true in auto mode for now
      });

      if (kDebugMode) {
        print('🔄 Auto listening mode initialized: $_isAutoModeEnabled');
      }
    });
  }

  void _toggleAutoMode(bool value) async {
    setState(() {
      _isAutoModeEnabled = value;
    });

    if (value) {
      await widget.voiceService.enableAutoMode();
    } else {
      await widget.voiceService.disableAutoMode();
    }

    if (widget.onToggle != null) {
      widget.onToggle!(value);
    }
  }

  String _getStateText() {
    switch (_currentState) {
      case AutoListeningState.idle:
        return 'Idle';
      case AutoListeningState.aiSpeaking:
        return 'Maya is speaking';
      case AutoListeningState.listening:
        return 'Listening...';
      case AutoListeningState.userSpeaking:
        return 'Recording...';
      case AutoListeningState.processing:
        return 'Processing...';
      default:
        return '';
    }
  }

  Color _getStateColor() {
    switch (_currentState) {
      case AutoListeningState.idle:
        return Colors.grey;
      case AutoListeningState.aiSpeaking:
        return Colors.blue;
      case AutoListeningState.listening:
        return Colors.amber;
      case AutoListeningState.userSpeaking:
        return Colors.red;
      case AutoListeningState.processing:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStateIndicator() {
    if (!_isAutoModeEnabled) {
      if (kDebugMode)
        print(
            '[AutoListeningToggle] State indicator hidden: auto mode disabled');
      return const SizedBox.shrink();
    }

    // Show indicator for both listeningForVoice and listening
    final showListening =
        _currentState == AutoListeningState.listeningForVoice ||
            _currentState == AutoListeningState.listening;
    if (kDebugMode)
      print(
          '[AutoListeningToggle] State indicator: $_currentState (showListening=$showListening)');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStateColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getStateColor(), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStateColor(),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _getStateText(),
            style: TextStyle(
              color: _getStateColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Manual',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: _isAutoModeEnabled,
              onChanged: _toggleAutoMode,
              activeColor: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 8),
            const Text(
              'Automatic',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildStateIndicator(),
      ],
    );
  }
}
