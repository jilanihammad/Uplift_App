import 'package:flutter/material.dart';
import '../../models/therapy_message.dart';
import 'chat_bubble.dart';

class ChatMessageList extends StatelessWidget {
  final List<TherapyMessage> messages;
  final ScrollController scrollController;
  final void Function(int newMessageCount)? onNewMessage;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.onNewMessage,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onNewMessage?.call(messages.length);
    });
    return ListView.builder(
      controller: scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isUser = message.isUser;
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return ChatBubble(
          message: message,
          isUser: isUser,
          isDarkMode: isDarkMode,
          onPlayAudio: message.audioUrl != null ? () {} : null,
        );
      },
    );
  }
}
