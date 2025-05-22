import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/therapy_message.dart';
import '../../blocs/chat_bloc.dart';
import 'chat_bubble.dart';

class ChatMessageList extends StatefulWidget {
  final ScrollController scrollController;
  final void Function(int newMessageCount)? onNewMessage;

  const ChatMessageList({
    Key? key,
    required this.scrollController,
    this.onNewMessage,
  }) : super(key: key);

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  int _previousMessageCount = 0;

  List<TherapyMessage> _extractMessages(ChatState state) {
    if (state is ChatLoaded) return state.messages;
    if (state is ChatCompletedState) return state.messages;
    if (state is ChatErrorState) return state.messages;
    if (state is ChatLoading) return [];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        List<TherapyMessage> messages = _extractMessages(state);
        // Scroll-to-bottom logic
        if (messages.length > _previousMessageCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.scrollController.hasClients) {
              widget.scrollController.animateTo(
                widget.scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            if (widget.onNewMessage != null) {
              widget.onNewMessage!(messages.length);
            }
          });
        }
        _previousMessageCount = messages.length;
        return ListView.builder(
          controller: widget.scrollController,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return ChatBubble(
              message: message,
              isUser: message.isUser,
              isDarkMode: isDarkMode,
              onPlayAudio: message.audioUrl != null
                  ? () => _playAudio(context, message.audioUrl!)
                  : null,
            );
          },
        );
      },
    );
  }

  void _playAudio(BuildContext context, String audioUrl) {
    // This callback should be provided by the parent if needed.
    // For now, just show a snackbar as a placeholder.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Play audio: $audioUrl')),
    );
  }
}
