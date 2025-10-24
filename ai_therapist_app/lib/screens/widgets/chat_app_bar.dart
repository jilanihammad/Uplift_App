// lib/screens/widgets/chat_app_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/voice_session_bloc.dart';
import '../../blocs/voice_session_state.dart';
import '../../models/therapist_style.dart';

/// Callback type for handling session end requests
typedef EndSessionCallback = Future<void> Function();

/// Extracted AppBar widget for ChatScreen with session timer, therapist style display, and end session button
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TherapistStyle? therapistStyle;
  final EndSessionCallback? onEndSession;
  final bool showTimer;
  final bool showEndButton;

  const ChatAppBar({
    super.key,
    this.therapistStyle,
    this.onEndSession,
    this.showTimer = true,
    this.showEndButton = true,
  });

  /// Factory constructor for simple app bar during initialization/selection phases
  const ChatAppBar.simple({
    Key? key,
    TherapistStyle? therapistStyle,
  }) : this(
          key: key,
          therapistStyle: therapistStyle,
          onEndSession: null,
          showTimer: false,
          showEndButton: false,
        );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        return AppBar(
          title: Row(
            children: [
              const Text('Ongoing Session'),
              if (therapistStyle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Tooltip(
                    message: therapistStyle!.name,
                    child: Icon(
                      therapistStyle!.icon,
                      size: 16,
                      color: therapistStyle!.color,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            // Session Timer
            if (showTimer)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1,
                        ),
                      ),
                      child: BlocSelector<VoiceSessionBloc, VoiceSessionState,
                          int>(
                        selector: (state) => state.sessionTimerSeconds,
                        builder: (context, seconds) {
                          final minutes = (seconds / 60).floor();
                          final secs = seconds % 60;
                          return Text(
                            "${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            // End Session Button
            if (showEndButton && onEndSession != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ElevatedButton(
                  onPressed: state.isEndingSession ? null : onEndSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('End'),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
