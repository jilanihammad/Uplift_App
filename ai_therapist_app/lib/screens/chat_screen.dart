// lib/screens/chat_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/chat_bloc.dart';
import '../blocs/voice_session_bloc.dart';
import '../blocs/voice_session_state.dart';
import '../blocs/voice_session_event.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';

import '../di/service_locator.dart';
import '../services/voice_service.dart';
import '../services/therapy_service.dart' hide TherapyServiceMessage;
import '../services/progress_service.dart';
import '../services/preferences_service.dart';
import '../widgets/mood_selector.dart';
import '../models/therapist_style.dart';
import '../models/user_preferences.dart';
import '../models/therapy_message.dart';
import '../data/repositories/session_repository.dart';
import '../services/navigation_service.dart';
import '../services/audio_generator.dart';
import '../data/repositories/message_repository.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/auto_listening_coordinator.dart';
import '../services/base_voice_service.dart' as bvs;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:ai_therapist_app/screens/widgets/duration_selector.dart';
import 'package:ai_therapist_app/screens/widgets/mood_selector_screen.dart';
import 'package:ai_therapist_app/screens/widgets/voice_controls.dart';
import 'package:ai_therapist_app/screens/widgets/text_input_bar.dart';
import 'package:ai_therapist_app/screens/widgets/chat_bubble.dart';
import 'package:ai_therapist_app/screens/widgets/chat_message_list.dart';

class ChatScreen extends StatelessWidget {
  final String? sessionId;
  const ChatScreen({Key? key, this.sessionId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VoiceSessionBloc>(
      create: (context) => VoiceSessionBloc(
        voiceService: serviceLocator<VoiceService>(),
        vadManager: serviceLocator<VADManager>(),
      ),
      child: _ChatScreenBody(sessionId: sessionId),
    );
  }
}

class _ChatScreenBody extends StatefulWidget {
  final String? sessionId;
  const _ChatScreenBody({Key? key, this.sessionId}) : super(key: key);

  @override
  State<_ChatScreenBody> createState() => _ChatScreenBodyState();
}

class _ChatScreenBodyState extends State<_ChatScreenBody>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Local state that doesn't belong in Bloc (UI-specific only)
  bool _isInitializing = true; // Add this flag to track initialization
  String _currentSessionId = '';
  Mood? _initialMood;
  TherapistStyle? _therapistStyle;
  bool _isMicMuted = false;
  bool _isSpeakerMuted = false;

  // Voice recording variables
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  late VoiceService _voiceService;
  StreamSubscription<bool>? _ttsSubscription;

  // Services
  final TherapyService _therapyService = serviceLocator<TherapyService>();
  final ProgressService _progressService = serviceLocator<ProgressService>();
  final NavigationService _navigationService =
      serviceLocator<NavigationService>();

  // Session timer - kept local for UI timing
  Timer? _sessionTimer;
  int _remainingTimeSeconds = 0;

  // Declare a variable to track if session is being ended
  bool _isEndingSession = false;

  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('[ChatScreen] initState called');
    WakelockPlus.enable(); // Keep screen awake during session
    // Set up microphone animation
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _micAnimation = Tween(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _micAnimationController, curve: Curves.easeInOut),
    );

    // Load therapist style
    _loadTherapistStyle();

    // Initialize voice service instance and setup
    _voiceService = serviceLocator<VoiceService>();
    _initializeVoiceService();

    // Wire up recording completion to Bloc
    _voiceService.autoListeningCoordinator.onRecordingCompleteCallback =
        (audioPath) {
      if (mounted) {
        context.read<VoiceSessionBloc>().add(ProcessAudio(audioPath));
      }
    };

    // Initialize session after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[ChatScreen] PostFrameCallback: calling _initSession');
      _initSession().then((_) {
        setState(() {
          _isInitializing = false;
        });
        print('[ChatScreen] _initSession complete, _isInitializing=false');
      });
    });
  }

  @override
  void dispose() {
    debugPrint('[ChatScreen] dispose called');
    WakelockPlus.disable(); // Allow screen to sleep after session
    _messageController.dispose();
    _scrollController.dispose();
    _ttsSubscription?.cancel();
    _micAnimationController.dispose();
    _voiceService.dispose();
    _sessionTimer?.cancel();
    _navigationService.showBottomNav();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ChatScreen] build called');
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        return WillPopScope(
          onWillPop: () async {
            print('[ChatScreen] onWillPop called');
            final blocState = context.read<ChatBloc>().state;
            final hasMessages =
                blocState is ChatLoaded && blocState.messages.isNotEmpty;
            if (hasMessages &&
                !state.showDurationSelector &&
                !state.showMoodSelector &&
                !_isInitializing) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please use the End button to finish your session.',
                  ),
                ),
              );
              return false;
            }
            return true;
          },
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const Text('Ongoing Session'),
                  if (_therapistStyle != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Tooltip(
                        message: _therapistStyle!.name,
                        child: Icon(
                          _therapistStyle!.icon,
                          size: 16,
                          color: _therapistStyle!.color,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                if (!_isInitializing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.lightBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.lightBlue, width: 1),
                          ),
                          child: Text(
                            _formatRemainingTime(),
                            style: const TextStyle(
                              color: Colors.lightBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isInitializing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      onPressed: _endSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('End'),
                    ),
                  ),
              ],
            ),
            body: _isInitializing
                ? const Center(child: CircularProgressIndicator())
                : state.showDurationSelector
                    ? DurationSelector(
                        selectedDuration: state.sessionDurationMinutes,
                        onDurationSelected: _handleDurationSelection,
                      )
                    : state.showMoodSelector
                        ? MoodSelectorScreen(
                            selectedMood: _initialMood,
                            onMoodSelected: _handleMoodSelection,
                          )
                        : state.isVoiceMode
                            ? _buildVoiceChatView()
                            : _buildTextChatView(),
          ),
        );
      },
    );
  }

  Widget _buildVoiceChatView() {
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        // Mic animation logic: trigger animation when state.isRecording changes
        if (state.isRecording && !_micAnimationController.isAnimating) {
          _micAnimationController.repeat(reverse: true);
        } else if (!state.isRecording && _micAnimationController.isAnimating) {
          _micAnimationController.stop();
          _micAnimationController.reset();
        }
        return Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      child: state.isRecording
                          ? Lottie.asset(
                              'assets/animations/Microphone Animation.json',
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
                    ),
                    const SizedBox(height: 32),
                    Text(
                      state.isRecording
                          ? "Listening to you..."
                          : 'Press "Talk" to speak',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VoiceControls(
              isRecording: state.isRecording,
              isProcessing: state.isProcessing,
              isSpeakerMuted: _isSpeakerMuted,
              micAnimation: _micAnimation,
              onMicTap: () {
                final bloc = context.read<VoiceSessionBloc>();
                if (state.isRecording) {
                  bloc.add(StopListening());
                } else {
                  bloc.add(StartListening());
                }
              },
              onSpeakerToggle: () async {
                setState(() {
                  _isSpeakerMuted = !_isSpeakerMuted;
                });
                if (_isSpeakerMuted) {
                  await _voiceService.stopAudio();
                }
              },
              onSwitchMode: _toggleChatMode,
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextChatView() {
    debugPrint('[ChatScreen] _buildTextChatView called');
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              Expanded(
                child: ChatMessageList(
                  messages: state.messages,
                  scrollController: _scrollController,
                  onNewMessage: (count) {
                    // Scroll to bottom when new messages are added
                    if (count > _previousMessageCount) {
                      _scrollToBottom();
                    }
                    _previousMessageCount = count;
                  },
                ),
              ),
              if (state.isProcessing) const LinearProgressIndicator(),
              TextInputBar(
                messageController: _messageController,
                micAnimation: _micAnimation,
                micButton: _buildMicButton(),
                isProcessing: state.isProcessing,
                onSend: _sendMessage,
                onSwitchMode: _toggleChatMode,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(TherapyMessage message) {
    final isUser = message.isUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return ChatBubble(
      message: message,
      isUser: isUser,
      isDarkMode: isDarkMode,
      onPlayAudio:
          message.audioUrl != null ? () => _playAudio(message.audioUrl!) : null,
    );
  }

  Future<void> _initializeVoiceService() async {
    // Dispose old subscriptions before creating new ones
    await _ttsSubscription?.cancel();
    _ttsSubscription = null;

    try {
      await _voiceService.initialize();
      _ttsSubscription = _voiceService.audioPlaybackStream.listen((_) {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initialize microphone: $e')),
      );
    }
  }

  Future<void> _loadTherapistStyle() async {
    final preferencesService = serviceLocator<PreferencesService>();
    final userPreferences = preferencesService.preferences;

    // Set therapist style
    _therapistStyle = TherapistStyle.getById(
      userPreferences?.therapistStyleId ?? 'humanistic',
    );

    // Initialize therapy service if needed
    await _therapyService.init();

    // Apply therapist style to therapy service
    _therapyService.setTherapistStyle(_therapistStyle!.systemPrompt);

    if (kDebugMode) {
      print('Loaded therapist style: ${_therapistStyle!.name}');
    }
  }

  Future<void> _initSession() async {
    final bloc = context.read<VoiceSessionBloc>();

    if (widget.sessionId != null) {
      // Load existing session (would normally fetch from repository)
      _currentSessionId = widget.sessionId ?? '';
      bloc.add(ShowMoodSelector(false));
      bloc.add(ShowDurationSelector(false));

      // Show loading indicator
      bloc.add(SetProcessing(true));

      // Simulate loading delay (replace with actual loading)
      await Future.delayed(const Duration(seconds: 1));

      bloc.add(SetProcessing(false));

      // Start the session timer for continuing sessions too
      _startSessionTimer();
    } else {
      // Generate a UUID for the session but don't create it yet
      // We'll create the session only after the user selects a duration
      _currentSessionId = const Uuid().v4();

      if (kDebugMode) {
        print(
          'Generated session ID: $_currentSessionId (will be created after duration selection)',
        );
      }

      // For new sessions, we show the duration selector first, then mood selector
      bloc.add(ShowDurationSelector(true));
      bloc.add(SwitchMode(true)); // Ensure we start in voice mode
    }
  }

  void _handleDurationSelection(int minutes) {
    final bloc = context.read<VoiceSessionBloc>();
    bloc.add(ChangeDuration(minutes));
    bloc.add(ShowDurationSelector(false));
    bloc.add(ShowMoodSelector(true));
    debugPrint('Duration selected: $minutes min, showing mood selector');
  }

  void _handleMoodSelection(Mood selectedMood) {
    final bloc = context.read<VoiceSessionBloc>();
    setState(() {
      _initialMood = selectedMood;
      _isInitializing = false;
    });
    bloc.add(ShowMoodSelector(false));
    debugPrint('Mood selected: $selectedMood, session is now active');
    _addInitialAIMessage(selectedMood);
  }

  void _addInitialAIMessage(Mood mood) {
    String welcomeMessage;
    switch (mood) {
      case Mood.happy:
        welcomeMessage =
            "I'm glad to hear you're feeling positive today! What would you like to talk about?";
        break;
      case Mood.sad:
        welcomeMessage =
            "I'm sorry to hear you're feeling down. Would you like to talk about what's troubling you?";
        break;
      case Mood.anxious:
        welcomeMessage =
            "I notice you're feeling anxious. Let's explore what's causing these feelings and find ways to help you feel more at ease.";
        break;
      case Mood.angry:
        welcomeMessage =
            "I can see you're feeling frustrated or angry. It's good to acknowledge these emotions. Would you like to talk about what triggered these feelings?";
        break;
      case Mood.stressed:
        welcomeMessage =
            "It sounds like you're under stress. Let's talk about what's happening and explore some coping strategies that might help.";
        break;
      default:
        welcomeMessage =
            "Thank you for sharing how you're feeling. What would you like to focus on in our conversation today?";
    }

    final aiWelcomeMsg = TherapyMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString() + '_maya_welcome',
      content: welcomeMessage,
      isUser: false,
      timestamp: DateTime.now(),
      audioUrl: null,
    );

    context.read<VoiceSessionBloc>().add(AddMessage(aiWelcomeMsg));

    final state = context.read<VoiceSessionBloc>().state;
    if (state.isVoiceMode) {
      _voiceService.autoListeningCoordinator.enableAutoMode().then((_) {
        if (kDebugMode)
          print(
            '[ChatScreen] Auto mode enabled by _addInitialAIMessage before welcome TTS.',
          );
        _voiceService.streamAndPlayTTS(
          text: welcomeMessage,
          onDone: _startListeningAfterTTS,
          onError: (error) {
            if (kDebugMode)
              print(
                '[ChatScreen] Error during initial welcome TTS: $error',
              );
            _startListeningAfterTTS();
          },
        );
      }).catchError((e) {
        if (kDebugMode)
          print(
            '[ChatScreen] Error enabling auto mode in _addInitialAIMessage: $e',
          );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error enabling voice mode: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }
  }

  void _startSessionTimer() {
    // Timer logic should be handled by Bloc; this can be removed or left empty.
  }

  String _formatRemainingTime() {
    final state = context.read<VoiceSessionBloc>().state;
    final minutes = (state.sessionTimerSeconds / 60).floor();
    final seconds = state.sessionTimerSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final state = context.read<VoiceSessionBloc>().state;
    if (state.isVoiceMode) {
      // Existing voice mode logic
      return;
    }
    context.read<VoiceSessionBloc>().add(ProcessTextMessage(text));
    _messageController.clear();
  }

  void _scrollToBottom() {
    // Wait for layout to complete before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Helper: After TTS completes, re-enable VAD and start recording
  Future<void> _startListeningAfterTTS() async {
    if (!mounted) return; // Added safety check for mounted state
    if (kDebugMode) {
      print(
        '[ChatScreen] _startListeningAfterTTS: TTS playback complete. AutoListeningCoordinator should handle VAD reactivation.',
      );
    }
    // The AutoListeningCoordinator should react to its isTtsActuallySpeakingStream
    // and its autoModeEnabled state to restart VAD. No need to call enableAutoMode() here.

    // Ensure ChatScreen's processing state is reset.
    if (mounted) {
      context.read<VoiceSessionBloc>().add(StartListening());
    }
    // If autoMode is enabled in ALC, it should start listening automatically
    // when isAiSpeaking stream becomes false.
  }

  Future<void> _startVoiceInput({String? preRecordedAudioPath}) async {
    final state = context.read<VoiceSessionBloc>().state;
    if (!_voiceService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone not ready. Please try again or end the session.',
          ),
        ),
      );
      return;
    }

    // If a preRecordedAudioPath is provided (VAD flow)
    if (preRecordedAudioPath != null) {
      if (kDebugMode) {
        print(
          '💬 CHAT: VAD flow - Transcribing pre-recorded audio at $preRecordedAudioPath',
        );
      }

      // Ensure UI reflects processing state immediately
      if (mounted && !state.isProcessing) {
        context.read<VoiceSessionBloc>().add(SetProcessing(true));
      }
      // If this was triggered by VAD, ensure _isRecording visually stops if it hasn't already
      // The actual recording is already stopped by AutoListeningCoordinator.
      // The _isRecording state in ChatScreen is updated via the recordingState stream.
      // However, to be absolutely sure the UI for recording stops if VAD triggers this,
      // and the stream update might be slightly delayed:
      if (preRecordedAudioPath != null && state.isProcessing && mounted) {
        // setState(() { _isRecording = false; }); // This might conflict with stream updates.
        // Let the stream handle _isRecording, _isProcessing is key here.
      }

      String transcription;
      try {
        if (preRecordedAudioPath != null && preRecordedAudioPath.isNotEmpty) {
          // VAD flow: transcribe the provided audio path
          if (kDebugMode) {
            print(
              '💬 CHAT: VAD flow - Transcribing pre-recorded audio at $preRecordedAudioPath',
            );
          }
          transcription = await _voiceService.processRecordedAudioFile(
            preRecordedAudioPath,
          );
        } else {
          if (kDebugMode) {
            print(
              '⚠️ CHAT: _startVoiceInput called to stop, but not recording and no VAD path.',
            );
          }
          if (mounted) {
            context.read<VoiceSessionBloc>().add(SetProcessing(false));
          }
          return;
        }

        if (kDebugMode) {
          print('💬 CHAT: Transcription received/processed: "$transcription"');
        }

        if (transcription.startsWith("Error:")) {
          if (mounted) {
            if (kDebugMode) print('💬 CHAT ERROR: $transcription');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(transcription),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
            context.read<VoiceSessionBloc>().add(SetProcessing(false));
          }
          return;
        }

        if (transcription.isNotEmpty &&
            !transcription.contains("Tap to speak") &&
            !transcription.contains("type your message")) {
          if (kDebugMode) {
            print('💬 CHAT: Valid transcription obtained: $transcription');
          }

          // 1. Create and add user message to ChatBloc
          final userMessage = TherapyMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            content: transcription,
            isUser: true,
            timestamp: DateTime.now(),
          );

          List<TherapyMessage> currentMessagesForBloc = [];
          final currentChatState = context.read<ChatBloc>().state;
          if (currentChatState is ChatLoaded) {
            currentMessagesForBloc = List.from(currentChatState.messages);
          } else if (currentChatState is ChatCompletedState) {
            currentMessagesForBloc = List.from(currentChatState.messages);
          } else if (currentChatState is ChatErrorState) {
            currentMessagesForBloc = List.from(currentChatState.messages);
          }
          // Add other states like ChatInitial or ChatLoading if needed

          currentMessagesForBloc.add(userMessage);
          if (mounted) {
            // Ensure mounted before interacting with context/Bloc
            context.read<ChatBloc>().add(
                  ReplaceMessages(List.from(currentMessagesForBloc)),
                ); // Add copy
            if (kDebugMode)
              print(
                '💬 CHAT: Emitted ChatLoaded with user message: "$transcription"',
              );
          }

          final history =
              currentMessagesForBloc // Use the updated list for history
                  .where(
                    (m) => m.id != userMessage.id,
                  ) // Exclude current user message from history for LLM
                  .map(
                    (m) => {
                      'role': m.isUser ? 'user' : 'assistant',
                      'content': m.content,
                    },
                  )
                  .toList();

          debugPrint('📜 Passing history to ChatBloc/therapyService: $history');

          // 2. Call TherapyService
          final Map<String, dynamic>? responseData =
              await _therapyService.processUserMessageWithStreamingAudio(
            transcription,
            history,
            onTTSPlaybackComplete: _startListeningAfterTTS,
            onTTSError: (String error) {
              if (kDebugMode) {
                print('💬 CHAT: TTS Error from TherapyService: $error');
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('TTS Error: $error'),
                    backgroundColor: Colors.orangeAccent,
                  ),
                );
                _startListeningAfterTTS();
              }
            },
          );

          final aiResponseText = responseData?['text'] as String?;

          // 3. If AI response is valid, create and add AI message to ChatBloc
          if (aiResponseText != null && aiResponseText.trim().isNotEmpty) {
            if (kDebugMode) {
              print('🟩 AI Response Text from TherapyService: $aiResponseText');
            }
            final aiMessage = TherapyMessage(
              id: DateTime.now()
                  .microsecondsSinceEpoch
                  .toString(), // Ensure unique ID
              content: aiResponseText,
              isUser: false,
              timestamp: DateTime.now(),
            );
            currentMessagesForBloc.add(
              aiMessage,
            ); // Add to the list that already has user's message
            if (mounted) {
              // Ensure mounted
              context.read<ChatBloc>().add(
                    ReplaceMessages(List.from(currentMessagesForBloc)),
                  ); // Add copy
              if (kDebugMode)
                print(
                  '🟩 CHAT: Emitted ChatLoaded with AI message: "$aiResponseText"',
                );
            }
          } else {
            if (kDebugMode) {
              print('⚠️ Empty AI reply text from TherapyService.');
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Maya had no text response.')),
              );
              // If no AI text, the state was already emitted with just user message.
              // _startListeningAfterTTS should be called by onTTSPlaybackComplete or onTTSError.
              // If TherapyService guarantees to call one of them, this is fine.
              // Safety net if neither was called due to no text:
              if (responseData == null ||
                  (responseData['text'] as String? ?? '').trim().isEmpty) {
                if (kDebugMode)
                  print(
                    'Ensuring listening restarts after empty/null AI text response and no TTS activity.',
                  );
                await _startListeningAfterTTS();
              }
            }
          }
        } else if (transcription.isNotEmpty) {
          // Got a placeholder message, just show it to the user
          if (mounted) {
            if (kDebugMode) {
              print('💬 CHAT: Got placeholder: $transcription');
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(transcription),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        // Ensure _isProcessing is reset if not handled by specific AI response paths
        if (mounted && state.isProcessing) {
          context.read<VoiceSessionBloc>().add(SetProcessing(false));
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            '💬 CHAT ERROR: Error processing voice in _startVoiceInput: $e',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing voice: $e'),
              backgroundColor: Colors.red,
            ),
          );
          if (state.isProcessing) {
            context.read<VoiceSessionBloc>().add(SetProcessing(false));
          }
        }
      } finally {
        // Final safety net to ensure _isProcessing is false
        if (mounted && state.isProcessing) {
          context.read<VoiceSessionBloc>().add(SetProcessing(false));
        }
      }
    } else {
      // This block is for starting recording (manual "Talk" button press when not already recording)
      if (kDebugMode) {
        print('💬 CHAT: Starting recording manually');
      }
      if (mounted && !state.isProcessing) {
        // Ensure processing is true while attempting to start
        context.read<VoiceSessionBloc>().add(SetProcessing(true));
      }

      try {
        // Disable ALC before manual recording starts to prevent VAD interference
        await _voiceService.autoListeningCoordinator.disableAutoMode();
        if (kDebugMode) print('[ChatScreen] Manual recording: ALC disabled.');

        // VoiceService.startRecording now delegates to RecordingManager,
        // and RecordingManager updates its own state stream, which ChatScreen listens to.
        // So, _isRecording will be set by the stream listener.
        await _voiceService.startRecording();
        // _isRecording is now true due to stream update if successful
        if (kDebugMode) {
          print('💬 CHAT: Manual recording start initiated via VoiceService.');
        }
      } catch (e) {
        // _isRecording should remain false or be set by stream to error/stopped.
        if (kDebugMode) {
          print('💬 CHAT ERROR: Failed to start recording manually: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error starting recording: $e'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
          // If starting failed, re-enable ALC if in voice mode, as it was just disabled
          if (state.isVoiceMode) {
            _voiceService.autoListeningCoordinator.enableAutoMode().catchError((
              alcError,
            ) {
              if (kDebugMode)
                print(
                  '[ChatScreen] Error re-enabling ALC after failed manual start: $alcError',
                );
            });
          }
        }
      } finally {
        // Reset _isProcessing after attempting to start.
        // _isRecording state is managed by the stream.
        if (mounted && state.isProcessing) {
          context.read<VoiceSessionBloc>().add(SetProcessing(false));
        }
      }
    }
  }

  Future<void> _playAudio(String audioPath, {bool inVoiceMode = false}) async {
    // This method is primarily for playing back user-recorded or non-TTS audio.
    // TTS audio playback and its animation are now handled by isTtsActuallySpeaking stream.
    context.read<VoiceSessionBloc>().add(SetProcessing(false));

    if (kDebugMode) {
      print(
        '💬 CHAT: Starting general audio playback for path: $audioPath (not TTS)',
      );
    }

    try {
      // Play audio - if it's TTS, VoiceService will handle the speaking state.
      // For other audio, we don't show the "Maya is speaking" animation.
      await _voiceService.playAudio(audioPath);
    } catch (e) {
      if (kDebugMode) {
        print('💬 CHAT ERROR: Error playing general audio: $e');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error playing audio: $e')));
    }
  }

  Future<void> _endSession() async {
    final state = context.read<VoiceSessionBloc>().state;
    if (_isEndingSession || state.isProcessing) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session ending in progress...')));
      return;
    }

    // Don't generate a summary if the session didn't actually start
    // (no messages or still in setup screens)
    final blocState = context.read<ChatBloc>().state;
    List<TherapyMessage> messages = [];
    if (blocState is ChatLoaded) {
      messages = blocState.messages;
    } else if (blocState is ChatCompletedState) {
      messages = blocState.messages;
    } else if (blocState is ChatErrorState) {
      messages = blocState.messages;
    }
    if (messages.isEmpty ||
        state.showDurationSelector ||
        state.showMoodSelector) {
      if (kDebugMode) {
        print(
          'Session not properly started, skipping session summary generation',
        );
      }
      // Show the bottom navigation bar and return to previous screen
      _navigationService.showBottomNav();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Show confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: const Text('Are you sure you want to end this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (result != true) return;

    setState(() {
      _isEndingSession = true;
      context.read<VoiceSessionBloc>().add(SetProcessing(true));
    });

    _navigationService.showBottomNav();

    // Stop and dispose audio/TTS resources robustly
    if (kDebugMode)
      print('🛑 Ending session: stopping and disposing VoiceService');
    await _voiceService.autoListeningCoordinator.disableAutoMode();
    await _voiceService.stopRecording();
    await _voiceService.stopAudio();
    _micAnimationController.stop();
    _micAnimationController.reset();
    context.read<VoiceSessionBloc>().add(SetProcessing(false));
    _voiceService.dispose();

    // Unregister and re-register VoiceService and AudioGenerator for a fresh instance
    if (kDebugMode)
      print(
        '🗑️ Unregistering VoiceService and AudioGenerator from service locator',
      );
    if (serviceLocator.isRegistered<VoiceService>()) {
      serviceLocator.unregister<VoiceService>();
    }
    if (serviceLocator.isRegistered<AudioGenerator>()) {
      serviceLocator.unregister<AudioGenerator>();
    }
    if (kDebugMode) print('🔄 Registering new VoiceService and AudioGenerator');
    serviceLocator.registerLazySingleton<VoiceService>(() {
      final service = VoiceService(apiClient: serviceLocator<ApiClient>());
      service.initializeOnlyIfNeeded();
      return service;
    });
    serviceLocator.registerLazySingleton<AudioGenerator>(() {
      final generator = AudioGenerator(
        voiceService: serviceLocator<VoiceService>(),
        apiClient: serviceLocator<ApiClient>(),
      );
      generator.initializeOnlyIfNeeded();
      return generator;
    });
    // Update local reference to the new VoiceService
    if (kDebugMode) print('🔄 Updating local _voiceService reference');
    final newVoiceService = serviceLocator<VoiceService>();
    _voiceService = newVoiceService;

    // Re-initialize VoiceService for next session
    if (kDebugMode) print('🔄 Re-initializing VoiceService for next session');
    await _voiceService.initializeOnlyIfNeeded();
    await _initializeVoiceService(); // <-- Ensure subscriptions and mic are set up for the new instance

    // Show a modal progress indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating session summary...'),
            ],
          ),
        ),
      );
    }

    try {
      if (kDebugMode) {
        print('Ending session with ID: $_currentSessionId');
      }
      // Log current mood
      if (_initialMood != null) {
        await _progressService.logMood(_initialMood!);
        if (kDebugMode) {
          print('Mood logged: $_initialMood, Notes: null');
        }
      }

      // Prepare messages for the session summary
      final messageList = messages.map((m) => m.toJson()).toList();

      if (kDebugMode) {
        print('Ending therapy session with ${messageList.length} messages');
      }

      // Get session summary from therapy service
      final sessionData = await _therapyService.endSession(messageList);

      final summary = sessionData['summary'] as String? ??
          'Thank you for your session today. I hope our conversation was helpful.';

      final actionItems = sessionData['action_items'] as List<dynamic>? ??
          sessionData['actionItems'] as List<dynamic>? ??
          ['Take care of yourself', 'Return soon for another session'];

      final insights = sessionData['insights'] as List<dynamic>? ?? [];

      if (kDebugMode) {
        print('Session summary generated successfully');
      }

      // Save the session to the repository
      try {
        // Additional validation to ensure we have a valid session to save
        if (_currentSessionId.isEmpty ||
            state.showDurationSelector ||
            state.showMoodSelector) {
          if (kDebugMode) {
            print(
              'Invalid session state, skipping save: ' +
                  'sessionId=${_currentSessionId.isEmpty}, ' +
                  'showDurationSelector=${state.showDurationSelector}, ' +
                  'showMoodSelector=${state.showMoodSelector}',
            );
          }
          throw Exception('Cannot save incomplete session');
        }

        final sessionRepository = serviceLocator<SessionRepository>();
        final messageRepository = serviceLocator<MessageRepository>();

        // Ensure the session exists in the repository before updating it
        try {
          await sessionRepository.getSession(_currentSessionId);
        } catch (e) {
          if (kDebugMode) {
            print('Session not found in repository, creating it now');
          }
          // Create the session if it doesn't exist
          final sessionTitle =
              'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';
          final createdSession = await sessionRepository.createSession(
            sessionTitle,
            id: _currentSessionId,
          );
          // Update _currentSessionId to backend's returned ID if it differs
          if (createdSession.id != _currentSessionId) {
            if (kDebugMode) {
              print(
                'Updating _currentSessionId from $_currentSessionId to ${createdSession.id}',
              );
            }
            _currentSessionId = createdSession.id;
          }
        }

        // Now save the session with its summary and messages
        await sessionRepository.saveSession(
          id: _currentSessionId,
          messages: messages.map((m) => m.toJson()).toList(),
          summary: summary,
          actionItems: actionItems.cast<String>(),
          initialMood: _initialMood,
          messageRepository: messageRepository,
        );

        if (kDebugMode) {
          print('Session saved to repository successfully');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error saving session to repository: $e');
        }
        // Continue anyway - we don't want to block the user
      }

      // Close the progress dialog if it's still showing
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      setState(() {
        _isEndingSession = false;
        context.read<VoiceSessionBloc>().add(SetProcessing(false));
      });

      // Navigate to summary screen using GoRouter
      if (!mounted) return;
      context.pushReplacement(
        '/session_summary',
        extra: {
          'sessionId': _currentSessionId,
          'summary': summary,
          'actionItems': actionItems.cast<String>(),
          'insights': insights.cast<String>(),
          'messages': messages,
          'initialMood': _initialMood,
        },
      );
    } catch (e) {
      // Close the progress dialog if it's still showing
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      setState(() {
        _isEndingSession = false;
        context.read<VoiceSessionBloc>().add(SetProcessing(false));
      });

      if (kDebugMode) {
        print('Error ending session: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to generate session summary: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e}',
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Try Again',
            onPressed: () {
              _endSession(); // Allow retry
            },
          ),
        ),
      );
    }
  }

  // Toggle between voice and text chat modes
  void _toggleChatMode() {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;
    // Stop any ongoing audio before switching modes
    _voiceService.stopAudio();
    setState(() {
      _isSpeakerMuted = false;
      _messageController.clear();
    });
    // Toggle the mode in the bloc
    bloc.add(SwitchMode(!state.isVoiceMode));
    debugPrint('🔄 Switched to \\${state.isVoiceMode ? "chat" : "voice"} mode');
  }

  void _switchToTextMode() {
    context.read<VoiceSessionBloc>().add(SwitchMode(false));
    setState(() {
      _isSpeakerMuted = true;
    });
    debugPrint('🔄 Switched to text mode');
  }

  void _switchToVoiceMode() {
    context.read<VoiceSessionBloc>().add(SwitchMode(true));
    setState(() {
      _isSpeakerMuted = false;
    });
    debugPrint('🔄 Switched to voice mode');
  }

  void _navigateAway() {
    debugPrint('[ChatScreen] Navigating away from chat screen');
    Navigator.of(context).pop();
  }

  Widget _buildMicButton() {
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        if (!state.isVADActive) {
          // VAD is off: show idle/off mic
          return IconButton(
            icon: Icon(Icons.mic_off, color: Colors.grey),
            onPressed: null,
          );
        } else if (state.isRecording) {
          // Recording: show active/recording mic
          return ScaleTransition(
            scale: _micAnimation,
            child: IconButton(
              icon: Lottie.asset(
                'assets/animations/Microphone Animation.json',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
              ),
              color: Colors.red,
              onPressed: () {
                context.read<VoiceSessionBloc>().add(StopListening());
              },
            ),
          );
        } else {
          // VAD is on, not recording: show listening/pulse mic
          return ScaleTransition(
            scale: _micAnimation,
            child: IconButton(
              icon: Icon(Icons.mic, color: Colors.blue),
              onPressed: () {
                context.read<VoiceSessionBloc>().add(StartListening());
              },
            ),
          );
        }
      },
    );
  }

  // Add this guard function
  void _ensureLock() async {
    final enabled = await WakelockPlus.enabled;
    if (!enabled) {
      debugPrint('Wakelock unexpectedly disabled, re-enabling');
      WakelockPlus.enable();
    }
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({Key? key, required this.text, required this.isUser})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.emoji_emotions, color: Colors.white),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).cardColor,
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
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: isUser
                      ? Colors.white
                      : isDarkMode
                          ? Colors.cyan[100]
                          : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) const CircleAvatar(child: Icon(Icons.person)),
        ],
      ),
    );
  }
}
