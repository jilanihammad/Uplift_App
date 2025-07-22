// lib/screens/widgets/chat_interface_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/voice_session_bloc.dart';
import '../../blocs/voice_session_state.dart';
import '../../blocs/voice_session_event.dart';
import 'voice_controls_panel.dart';
import 'chat_message_list.dart';
import 'text_input_bar.dart';
import '../../models/subscription_tier.dart';

/// Callback types for interface actions
typedef InterfaceCallback = void Function();

/// Container widget that composes all chat interface components and handles
/// mode switching between voice and text modes
class ChatInterfaceView extends StatefulWidget {
  final InterfaceCallback onSwitchMode;
  final InterfaceCallback onSendMessage;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final SubscriptionTier subscriptionTier;

  const ChatInterfaceView({
    super.key,
    required this.onSwitchMode,
    required this.onSendMessage,
    required this.messageController,
    required this.scrollController,
    required this.subscriptionTier,
  });

  @override
  State<ChatInterfaceView> createState() => _ChatInterfaceViewState();
}

class _ChatInterfaceViewState extends State<ChatInterfaceView> {
  int _previousMessageCount = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        return state.isVoiceMode
            ? _buildVoiceInterface()
            : _buildTextInterface();
      },
    );
  }

  /// Builds the voice mode interface with VoiceControlsPanel
  Widget _buildVoiceInterface() {
    return VoiceControlsPanel(
      onSwitchMode: widget.onSwitchMode,
    );
  }

  /// Builds the text mode interface with ChatMessageList and TextInputBar
  Widget _buildTextInterface() {
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        return Column(
          children: [
            // Chat messages area
            Expanded(
              child: ChatMessageList(
                messages: state.messages,
                scrollController: widget.scrollController,
                onNewMessage: _handleNewMessage,
              ),
            ),
            // Processing indicator
            _buildProcessingIndicator(),
            // Text input area
            _buildTextInput(),
          ],
        );
      },
    );
  }

  /// Builds the processing indicator that shows during message processing
  Widget _buildProcessingIndicator() {
    return BlocSelector<VoiceSessionBloc, VoiceSessionState, bool>(
      selector: (state) => state.isProcessing,
      builder: (context, isProcessing) {
        return isProcessing
            ? const LinearProgressIndicator()
            : const SizedBox.shrink();
      },
    );
  }

  /// Builds the text input bar with mic button and controls
  Widget _buildTextInput() {
    return BlocSelector<VoiceSessionBloc, VoiceSessionState,
        ({bool isVoice, bool isProcessing, bool canSend})>(
      selector: (state) => (
        isVoice: state.isVoiceMode,
        isProcessing: state.isProcessing,
        canSend: !state.isProcessing && 
                 !state.isInitializing && 
                 !state.isEndingSession &&
                 !state.showMoodSelector &&
                 !state.showDurationSelector,
      ),
      builder: (context, data) {
        if (data.isVoice) {
          return const SizedBox.shrink();
        }
        return TextInputBar(
          messageController: widget.messageController,
          micButton: _buildMicButton(),
          isProcessing: data.isProcessing,
          onSend: widget.onSendMessage,
          onSwitchMode: widget.onSwitchMode,
          enabled: data.canSend,
        );
      },
    );
  }

  /// Builds the microphone button for text mode with appropriate states
  Widget _buildMicButton() {
    // Check if voice functionality is allowed for current subscription tier
    if (!widget.subscriptionTier.allowsVoiceSessions) {
      // Show upgrade prompt for basic tier users
      return IconButton(
        icon: Icon(
          Icons.mic_off,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        onPressed: () => _showVoiceUpgradeDialog(context),
      );
    }

    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        if (!state.isVADActive) {
          // VAD is off: show idle/off mic
          return IconButton(
            icon: Icon(
              Icons.mic_off, 
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            onPressed: null,
          );
        } else if (state.isRecording || state.isListeningForVoice) {
          // Recording or listening: show active/recording mic
          return IconButton(
            icon: Icon(
              Icons.mic,
              color: state.isRecording ? Colors.red : Colors.blue,
            ),
            onPressed: () {
              if (state.isRecording) {
                context.read<VoiceSessionBloc>().add(StopListening());
              } else {
                context.read<VoiceSessionBloc>().add(StartListening());
              }
            },
          );
        } else {
          // VAD is on, not recording or listening: show listening/pulse mic
          return IconButton(
            icon: const Icon(Icons.mic, color: Colors.blue),
            onPressed: () {
              context.read<VoiceSessionBloc>().add(StartListening());
            },
          );
        }
      },
    );
  }

  /// Handles new message notifications and auto-scrolling
  void _handleNewMessage(int messageCount) {
    if (messageCount > _previousMessageCount) {
      _scrollToBottom();
    }
    _previousMessageCount = messageCount;
  }

  /// Scrolls the message list to the bottom
  void _scrollToBottom() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Show upgrade dialog when basic tier users try to use voice features
  void _showVoiceUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.mic, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Voice Features'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voice therapy sessions are available with Premium subscription.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Premium Plan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '\$10/month',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• Voice + chat therapy sessions'),
                  const Text('• Real-time voice processing'),
                  const Text('• All premium features'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to subscription screen
              Navigator.pushNamed(context, '/subscription');
            },
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }
}