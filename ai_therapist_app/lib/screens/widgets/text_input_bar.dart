import 'package:flutter/material.dart';

class TextInputBar extends StatelessWidget {
  final TextEditingController messageController;
  final Widget micButton;
  final bool isProcessing;
  final VoidCallback onSend;
  final VoidCallback onSwitchMode;
  final bool enabled;

  const TextInputBar({
    Key? key,
    required this.messageController,
    required this.micButton,
    required this.isProcessing,
    required this.onSend,
    required this.onSwitchMode,
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, -2),
            blurRadius: 4,
            color: Color.fromRGBO(0, 0, 0, 0.1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              micButton,
              Expanded(
                child: TextField(
                  controller: messageController,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: messageController,
                builder: (context, value, _) {
                  final isTyping = value.text.isNotEmpty;
                  return IconButton(
                    icon: isTyping
                        ? const Icon(Icons.send)
                        : const Icon(Icons.graphic_eq),
                    tooltip: isTyping ? 'Send message' : 'Switch to voice mode',
                    onPressed: isProcessing
                        ? null
                        : isTyping
                            ? onSend
                            : onSwitchMode,
                  );
                },
              ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: messageController,
            builder: (context, value, _) {
              final isTyping = value.text.isNotEmpty;
              if (isTyping) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: InkWell(
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
                          Icons.graphic_eq,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Switch to Voice Mode',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
