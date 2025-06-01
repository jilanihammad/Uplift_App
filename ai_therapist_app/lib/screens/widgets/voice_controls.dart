import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class VoiceControls extends StatelessWidget {
  final bool isRecording;
  final bool isProcessing;
  final bool isSpeakerMuted;
  final Animation<double> micAnimation;
  final VoidCallback onMicTap;
  final VoidCallback onSpeakerToggle;
  final VoidCallback onSwitchMode;

  const VoiceControls({
    Key? key,
    required this.isRecording,
    required this.isProcessing,
    required this.isSpeakerMuted,
    required this.micAnimation,
    required this.onMicTap,
    required this.onSpeakerToggle,
    required this.onSwitchMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
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
                      color: (isRecording
                              ? Colors.red
                              : Theme.of(context).primaryColor)
                          .withOpacity(0.85),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
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
                              style: const TextStyle(
                                color: Colors.white,
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
                          ? Colors.grey
                          : Theme.of(context).primaryColor.withOpacity(0.85),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
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
                              color: Colors.white,
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
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Switch to Chat Mode',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
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
