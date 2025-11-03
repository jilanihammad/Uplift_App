import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:ai_therapist_app/config/theme.dart';

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
          debugPrint('[AutoListeningToggle] State changed: $_currentState');
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
        debugPrint('🔄 Auto listening mode initialized: $_isAutoModeEnabled');
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

  Color _getStateColor(ThemeData theme, AppPalette? palette) {
    switch (_currentState) {
      case AutoListeningState.idle:
        return theme.colorScheme.outline;
      case AutoListeningState.aiSpeaking:
        return palette?.accentSecondary ?? theme.colorScheme.secondary;
      case AutoListeningState.listening:
      case AutoListeningState.listeningForVoice:
        return palette?.accentPrimary ?? theme.colorScheme.primary;
      case AutoListeningState.userSpeaking:
        return theme.colorScheme.error;
      case AutoListeningState.processing:
        return theme.colorScheme.tertiary;
      default:
        return theme.colorScheme.outlineVariant;
    }
  }

  Widget _buildStateIndicator() {
    if (!_isAutoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningToggle] State indicator hidden: auto mode disabled');
      }
      return const SizedBox.shrink();
    }

    // Show indicator for both listeningForVoice and listening
    final showListening =
        _currentState == AutoListeningState.listeningForVoice ||
            _currentState == AutoListeningState.listening;
    if (kDebugMode) {
      debugPrint(
          '[AutoListeningToggle] State indicator: $_currentState (showListening=$showListening)');
    }

    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final stateColor = _getStateColor(theme, palette);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: stateColor.withValues(
          alpha: theme.brightness == Brightness.light ? 0.16 : 0.24,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stateColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: stateColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _getStateText(),
            style: TextStyle(
              color: stateColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w500,
      color: theme.textTheme.bodySmall?.color,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Manual', style: labelStyle),
            const SizedBox(width: 8),
            Switch(
              value: _isAutoModeEnabled,
              onChanged: _toggleAutoMode,
              activeColor: palette?.accentPrimary ?? theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('Automatic', style: labelStyle),
          ],
        ),
        const SizedBox(height: 8),
        _buildStateIndicator(),
      ],
    );
  }
}
