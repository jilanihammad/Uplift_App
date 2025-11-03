import 'package:flutter/material.dart';

import 'package:ai_therapist_app/config/theme.dart';

class VoiceControls extends StatelessWidget {
  final bool isRecording;
  final bool isProcessing;
  final bool isSpeakerMuted;
  final Animation<double> micAnimation;
  final VoidCallback onMicTap;
  final VoidCallback onSpeakerToggle;
  final VoidCallback onSwitchMode;

  const VoiceControls({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.isSpeakerMuted,
    required this.micAnimation,
    required this.onMicTap,
    required this.onSpeakerToggle,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final accentPrimary = palette?.accentPrimary ?? theme.colorScheme.primary;
    final accentSecondary =
        palette?.accentSecondary ?? theme.colorScheme.secondary;
    final micBaseColor =
        isRecording ? theme.colorScheme.error : accentPrimary;
    final micTextColor = ThemeData.estimateBrightnessForColor(micBaseColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final speakerColor =
        isSpeakerMuted ? theme.colorScheme.outline : accentSecondary;
    final speakerIconColor = ThemeData.estimateBrightnessForColor(speakerColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            // boxShadow: const [
            //   BoxShadow(
            //     offset: Offset(0, -2),
            //     blurRadius: 4,
            //     color: Color.fromRGBO(0, 0, 0, 0.1),
            //   ),
            // ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: micBaseColor.withValues(alpha: 0.9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Tooltip(
                      message:
                          isRecording ? 'Stop Recording' : 'Start Recording',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onMicTap,
                          child: Center(
                            child: Text(
                              isRecording ? 'Stop' : 'Talk',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: micTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSpeakerMuted
                          ? theme.colorScheme.outline.withValues(alpha: 0.65)
                          : speakerColor.withValues(alpha: 0.9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Tooltip(
                      message:
                          isSpeakerMuted ? 'Unmute Speaker' : 'Mute Speaker',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onSpeakerToggle,
                          child: Center(
                          child: Icon(
                            isSpeakerMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: isSpeakerMuted
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6)
                                : speakerIconColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: onSwitchMode,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accentPrimary.withValues(
                      theme.brightness == Brightness.light ? 0.12 : 0.18,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: accentPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Switch to Chat Mode',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accentPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isProcessing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
