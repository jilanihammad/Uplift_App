import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_therapist_app/config/theme.dart';

import '../../models/therapy_message.dart';

class ChatBubble extends StatelessWidget {
  final TherapyMessage message;
  final bool isUser;
  final bool isDarkMode;
  final VoidCallback? onPlayAudio;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.isDarkMode,
    this.onPlayAudio,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final isDark = theme.brightness == Brightness.dark || isDarkMode;
    final userBubbleColor =
        palette?.accentPrimary ?? theme.colorScheme.primary;
    final aiBubbleColor = palette?.surfaceHigh ?? theme.cardColor;
    final aiAvatarColor = palette?.accentSecondary ?? theme.colorScheme.secondary;
    final userTextColor =
        ThemeData.estimateBrightnessForColor(userBubbleColor) ==
                Brightness.dark
            ? Colors.white
            : Colors.black;
    final aiTextColor = theme.colorScheme.onSurface
        .withValues(alpha: isDark ? 0.9 : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: aiAvatarColor,
              child: Icon(
                Icons.emoji_emotions,
                color: ThemeData.estimateBrightnessForColor(aiAvatarColor) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser ? userBubbleColor : aiBubbleColor,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Color.fromRGBO(0, 0, 0, 0.1),
                      ),
                    ],
                  ),
                  child: Text(
                    message.content,
                    softWrap: true,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 15,
                      color: isUser ? userTextColor : aiTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.audioUrl != null)
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 20),
                        onPressed: onPlayAudio,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                      ),
                    Text(
                      DateFormat('h:mm a').format(message.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color
                                ?.withValues(alpha: isDark ? 0.6 : 0.7) ??
                            Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              backgroundColor: palette?.surfaceLow ?? theme.cardColor,
              child: Icon(
                Icons.person,
                color: theme.iconTheme.color,
              ),
            ),
        ],
      ),
    );
  }
}
