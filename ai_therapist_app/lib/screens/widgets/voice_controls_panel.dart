// lib/screens/widgets/voice_controls_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import '../../blocs/voice_session_bloc.dart';
import '../../blocs/voice_session_state.dart';
import '../../blocs/voice_session_event.dart';
import '../../widgets/audio_visualizer.dart';
import '../../services/accessibility_service.dart';

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

class _VoiceControlsPanelState extends State<VoiceControlsPanel> {
  AccessibilitySettings _accessibilitySettings = const AccessibilitySettings(
    motionSensitive: false,
    reducedAnimations: false,
    highContrast: false,
  );

  @override
  void initState() {
    super.initState();
    _loadAccessibilitySettings();
  }
  
  Future<void> _loadAccessibilitySettings() async {
    final settings = await AccessibilityService.getSettings();
    if (mounted) {
      setState(() {
        _accessibilitySettings = settings;
      });
    }
  }

  @override
  void dispose() {
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
              // Voice visualization container with real-time amplitude visualization
              BlocSelector<VoiceSessionBloc, VoiceSessionState,
                  ({bool rec, double amp, bool listening, bool processing, bool speaking, bool voiceMode})>(
                selector: (blocState) => (
                  rec: blocState.isRecording,
                  amp: blocState.amplitude,
                  listening: blocState.isListeningForVoice,
                  processing: blocState.isProcessingAudio,
                  speaking: blocState.isAiSpeaking,
                  voiceMode: blocState.isVoiceMode,
                ),
                builder: (context, data) {
                  // Determine visualization state based on current activity
                  VisualizationState visualState;
                  if (data.processing) {
                    visualState = VisualizationState.processing;
                  } else if (data.speaking) {
                    visualState = VisualizationState.speaking;
                  } else if (data.rec || data.listening) {
                    visualState = VisualizationState.listening;
                  } else {
                    visualState = VisualizationState.idle;
                  }
                  
                  // Show appropriate visualization based on state and mode
                  if (data.voiceMode) {
                    // In voice mode: use Lottie for listening, AudioVisualizer for others
                    if (data.rec || data.listening) {
                      return Lottie.asset(
                        'assets/animations/Microphone Animation.json',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      );
                    } else {
                      return AudioVisualizerWidget(
                        amplitude: data.amp,
                        state: visualState,
                        mode: VisualizationMode.ripple,
                        primaryColor: Theme.of(context).primaryColor,
                        accentColor: Theme.of(context).colorScheme.secondary,
                        size: 120.0,
                        motionSensitive: _accessibilitySettings.motionSensitive,
                      );
                    }
                  } else {
                    // Fallback to Lottie animations in text mode
                    return Container(
                      width: 120,
                      height: 120,
                      child: (data.processing || data.speaking)
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
                  }
                },
              ),
              const SizedBox(height: 32),
              // Status text that changes based on interaction state
              BlocSelector<VoiceSessionBloc, VoiceSessionState, 
                  ({bool rec, bool listening, bool processing, bool speaking, bool voiceMode})>(
                selector: (blocState) => (
                  rec: blocState.isRecording,
                  listening: blocState.isListeningForVoice,
                  processing: blocState.isProcessingAudio,
                  speaking: blocState.isAiSpeaking,
                  voiceMode: blocState.isVoiceMode,
                ),
                builder: (context, data) {
                  String statusText;
                  if (data.processing) {
                    statusText = "Speaking";
                  } else if (data.speaking) {
                    statusText = "Maya is speaking...";
                  } else if (data.rec) {
                    statusText = "Recording your voice...";
                  } else if (data.listening && data.voiceMode) {
                    statusText = "Listening for your voice...";
                  } else if (data.voiceMode) {
                    statusText = "Listening";
                  } else {
                    statusText = "Chat mode active";
                  }
                  
                  return Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
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
            // Mic mute and Speaker buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mic Mute Toggle Button (replaces Talk)
                _buildMicMuteButton(
                  isMicEnabled: context.read<VoiceSessionBloc>().state.isMicEnabled,
                  onTap: () {
                    final bloc = context.read<VoiceSessionBloc>();
                    bloc.add(ToggleMicMute());
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

  Widget _buildMicMuteButton({
    required bool isMicEnabled,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isMicEnabled
                ? Theme.of(context).primaryColor
                : Colors.grey)
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
        message: isMicEnabled ? 'Mute mic' : 'Unmute mic',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(
                isMicEnabled ? Icons.mic : Icons.mic_off,
                color: Colors.white,
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