// lib/screens/widgets/voice_controls_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import '../../blocs/voice_session_bloc.dart';
import '../../blocs/voice_session_state.dart';
import '../../blocs/voice_session_event.dart';

/// Callback types for voice control actions
typedef VoiceControlCallback = void Function();

/// Comprehensive voice controls panel widget that includes voice visualization, 
/// status text, and all voice interaction controls
class VoiceControlsPanel extends StatefulWidget {
  final VoiceControlCallback onSwitchMode;

  const VoiceControlsPanel({
    super.key,
    required this.onSwitchMode,
  });

  @override
  State<VoiceControlsPanel> createState() => _VoiceControlsPanelState();
}

class _VoiceControlsPanelState extends State<VoiceControlsPanel>
    with TickerProviderStateMixin {
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;

  @override
  void initState() {
    super.initState();
    
    // Set up microphone animation
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _micAnimation = Tween(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _micAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Voice Visualization Area
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Voice visualization container with Lottie animations
              BlocSelector<VoiceSessionBloc, VoiceSessionState,
                  ({bool rec, double amp, bool listening, bool processing, bool speaking})>(
                selector: (blocState) => (
                  rec: blocState.isRecording,
                  amp: blocState.amplitude,
                  listening: blocState.isListeningForVoice,
                  processing: blocState.isProcessingAudio,
                  speaking: blocState.isAiSpeaking,
                ),
                builder: (context, data) {
                  // Animation logic - animate during recording/listening, processing, or AI speaking
                  if ((data.rec || data.listening || data.processing || data.speaking) &&
                      !_micAnimationController.isAnimating) {
                    _micAnimationController.repeat(reverse: true);
                  } else if (!data.rec &&
                      !data.listening &&
                      !data.processing &&
                      !data.speaking &&
                      _micAnimationController.isAnimating) {
                    _micAnimationController.stop();
                    _micAnimationController.reset();
                  }
                  
                  return Container(
                    width: 120,
                    height: 120,
                    child: (data.rec || data.listening)
                        ? Lottie.asset(
                            'assets/animations/Microphone Animation.json',
                            width: 120,
                            height: 120,
                            fit: BoxFit.contain,
                          )
                        : (data.processing || data.speaking)
                            ? Lottie.asset(
                                'assets/animations/Session Animation.json',
                                width: 120,
                                height: 120,
                                fit: BoxFit.contain,
                              )
                            : Lottie.asset(
                                'assets/animations/Session Animation.json',
                                width: 120,
                                height: 120,
                                fit: BoxFit.contain,
                              ),
                  );
                },
              ),
              const SizedBox(height: 32),
              // Status text that changes based on recording state
              BlocSelector<VoiceSessionBloc, VoiceSessionState, bool>(
                selector: (blocState) => blocState.isRecording,
                builder: (context, isRecording) => Text(
                  isRecording ? "Listening to you..." : 'Press "Talk" to speak',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Voice Controls Section
        _buildVoiceControls(),
      ],
    );
  }

  Widget _buildVoiceControls() {
    return BlocSelector<VoiceSessionBloc, VoiceSessionState,
        ({bool rec, bool proc, bool muted, bool listening})>(
      selector: (state) => (
        rec: state.isRecording,
        proc: state.isProcessing,
        muted: state.isSpeakerMuted,
        listening: state.isListeningForVoice,
      ),
      builder: (context, data) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Talk and Speaker buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Talk/Stop Button
                _buildTalkButton(
                  isRecording: data.rec,
                  onTap: () {
                    final bloc = context.read<VoiceSessionBloc>();
                    if (data.rec) {
                      bloc.add(StopListening());
                    } else {
                      bloc.add(StartListening());
                    }
                  },
                ),
                // Speaker Toggle Button
                _buildSpeakerButton(
                  isMuted: data.muted,
                  onTap: () {
                    final bloc = context.read<VoiceSessionBloc>();
                    final newMuted = !data.muted;
                    bloc.add(SetSpeakerMuted(newMuted));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Switch to Chat Mode button
            InkWell(
              onTap: widget.onSwitchMode,
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
            // Processing indicator
            if (data.proc) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTalkButton({
    required bool isRecording,
    required VoidCallback onTap,
  }) {
    return Container(
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
        message: isRecording ? 'Stop Recording' : 'Start Recording',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
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
    );
  }

  Widget _buildSpeakerButton({
    required bool isMuted,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMuted
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
        message: isMuted ? 'Unmute Speaker' : 'Mute Speaker',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(
                isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}