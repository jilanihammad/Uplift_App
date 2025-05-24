// lib/screens/chat_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/voice_session_bloc.dart';
import '../blocs/voice_session_state.dart';
import '../blocs/voice_session_event.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';

import '../di/service_locator.dart';
import '../services/therapy_service.dart' hide TherapyServiceMessage;
import '../services/progress_service.dart';
import '../services/preferences_service.dart';
import '../widgets/mood_selector.dart';
import '../models/therapist_style.dart';
import '../models/therapy_message.dart';
import '../data/repositories/session_repository.dart';
import '../services/navigation_service.dart';
import '../services/audio_generator.dart';
import '../data/repositories/message_repository.dart';
import '../data/datasources/remote/api_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:ai_therapist_app/screens/widgets/duration_selector.dart';
import 'package:ai_therapist_app/screens/widgets/mood_selector_screen.dart';
import 'package:ai_therapist_app/screens/widgets/voice_controls.dart';
import 'package:ai_therapist_app/screens/widgets/text_input_bar.dart';
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

  // Session state
  String _currentSessionId = '';
  Mood? _initialMood;
  TherapistStyle? _therapistStyle;

  // Voice recording variables
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  late VoiceService _voiceService;

  // Services
  final TherapyService _therapyService = serviceLocator<TherapyService>();
  final ProgressService _progressService = serviceLocator<ProgressService>();
  final NavigationService _navigationService =
      serviceLocator<NavigationService>();

  // Session timer
  Timer? _sessionTimer;
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

    // Initialize services
    _voiceService = serviceLocator<VoiceService>();
    _initializeServices();
    _loadTherapistStyle();

    // Initialize session after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[ChatScreen] PostFrameCallback: calling _initSession');
      _initSession();
    });
  }

  @override
  void dispose() {
    debugPrint('[ChatScreen] dispose called');
    WakelockPlus.disable(); // Allow screen to sleep after session
    _messageController.dispose();
    _scrollController.dispose();
    _micAnimationController.dispose();
    _sessionTimer?.cancel();
    _navigationService.showBottomNav();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ChatScreen] build called');
    return BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
      builder: (context, state) {
        // Handle initialization state
        if (state.isInitializing) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ongoing Session')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Handle duration selector
        if (state.showDurationSelector) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ongoing Session')),
            body: DurationSelector(
              selectedDuration: state.sessionDurationMinutes,
              onDurationSelected: _handleDurationSelection,
            ),
          );
        }

        // Handle mood selector
        if (state.showMoodSelector) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ongoing Session')),
            body: MoodSelectorScreen(
              selectedMood: _initialMood,
              onMoodSelected: _handleMoodSelection,
            ),
          );
        }

        // Main chat interface
        return WillPopScope(
          onWillPop: () async => _handleBackPress(state),
          child: Scaffold(
            appBar: _buildAppBar(state),
            body: state.isVoiceMode
                ? _buildVoiceChatView()
                : _buildTextChatView(),
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(VoiceSessionState state) {
    return AppBar(
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
        // Session timer
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
                  border: Border.all(color: Colors.lightBlue, width: 1),
                ),
                child: BlocSelector<VoiceSessionBloc, VoiceSessionState, int>(
                  selector: (state) => state.sessionTimerSeconds,
                  builder: (context, seconds) {
                    final minutes = (seconds / 60).floor();
                    final secs = seconds % 60;
                    return Text(
                      '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.lightBlue,
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
        // End session button
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: ElevatedButton(
            onPressed: state.isProcessing || state.isEndingSession
                ? null
                : _endSession,
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
    );
  }

  Future<bool> _handleBackPress(VoiceSessionState state) async {
    print('[ChatScreen] onWillPop called');
    final hasMessages = state.messages.isNotEmpty;

    if (hasMessages &&
        !state.showDurationSelector &&
        !state.showMoodSelector &&
        !state.isInitializing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use the End button to finish your session.'),
        ),
      );
      return false;
    }
    return true;
  }

  Widget _buildVoiceChatView() {
    return Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BlocSelector<VoiceSessionBloc, VoiceSessionState,
                  ({bool rec, double amp})>(
                selector: (blocState) =>
                    (rec: blocState.isRecording, amp: blocState.amplitude),
                builder: (context, data) {
                  // Mic animation logic
                  if (data.rec && !_micAnimationController.isAnimating) {
                    _micAnimationController.repeat(reverse: true);
                  } else if (!data.rec && _micAnimationController.isAnimating) {
                    _micAnimationController.stop();
                    _micAnimationController.reset();
                  }
                  return Container(
                    width: 120,
                    height: 120,
                    child: data.rec
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
                  );
                },
              ),
              const SizedBox(height: 32),
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
        BlocSelector<VoiceSessionBloc, VoiceSessionState,
            ({bool rec, bool proc, bool muted})>(
          selector: (state) => (
            rec: state.isRecording,
            proc: state.isProcessing,
            muted: state.isSpeakerMuted
          ),
          builder: (context, data) => VoiceControls(
            isRecording: data.rec,
            isProcessing: data.proc,
            isSpeakerMuted: data.muted,
            micAnimation: _micAnimation,
            onMicTap: () {
              final bloc = context.read<VoiceSessionBloc>();
              if (data.rec) {
                bloc.add(StopListening());
              } else {
                bloc.add(StartListening());
              }
            },
            onSpeakerToggle: () async {
              final bloc = context.read<VoiceSessionBloc>();
              final newMuted = !data.muted;
              bloc.add(SetSpeakerMuted(newMuted));
            },
            onSwitchMode: _toggleChatMode,
          ),
        ),
      ],
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
              BlocSelector<VoiceSessionBloc, VoiceSessionState, bool>(
                selector: (state) => state.isProcessing,
                builder: (context, isProcessing) {
                  return isProcessing
                      ? const LinearProgressIndicator()
                      : const SizedBox.shrink();
                },
              ),
              BlocSelector<VoiceSessionBloc, VoiceSessionState,
                  ({bool isVoice, bool isProcessing, bool canSend})>(
                selector: (state) => (
                  isVoice: state.isVoiceMode,
                  isProcessing: state.isProcessing,
                  canSend: state.canSend
                ),
                builder: (context, data) {
                  if (data.isVoice) {
                    return const SizedBox.shrink();
                  }
                  return TextInputBar(
                    messageController: _messageController,
                    micAnimation: _micAnimation,
                    micButton: _buildMicButton(),
                    isProcessing: data.isProcessing,
                    onSend: _sendMessage,
                    onSwitchMode: _toggleChatMode,
                    enabled: data.canSend,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _initializeServices() async {
    debugPrint('[ChatScreen] _initializeServices called');

    try {
      // Initialize services through Bloc
      context.read<VoiceSessionBloc>().add(InitializeService());

      // Set up callback for recording completion
      _voiceService.autoListeningCoordinator.onRecordingCompleteCallback =
          (String audioPath) {
        debugPrint(
            '[ChatScreen] Recording complete callback triggered with path: $audioPath');
        if (mounted) {
          context.read<VoiceSessionBloc>().add(ProcessAudio(audioPath));
        }
      };

      debugPrint('[ChatScreen] Services initialized successfully');
    } catch (e) {
      debugPrint('[ChatScreen] Service initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize services: $e')),
        );
      }
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

    // Start initialization
    bloc.add(SetInitializing(true));

    if (widget.sessionId != null) {
      // Load existing session
      _currentSessionId = widget.sessionId ?? '';
      bloc.add(ShowMoodSelector(false));
      bloc.add(ShowDurationSelector(false));

      // Simulate loading delay (replace with actual loading)
      await Future.delayed(const Duration(seconds: 1));

      // Start the session timer
      _startSessionTimer();

      // End initialization
      bloc.add(SetInitializing(false));
    } else {
      // Generate a UUID for the session
      _currentSessionId = const Uuid().v4();

      if (kDebugMode) {
        print('Generated session ID: $_currentSessionId');
      }

      // For new sessions, show duration selector first
      bloc.add(ShowDurationSelector(true));
      bloc.add(SwitchMode(true)); // Ensure we start in voice mode

      // End initialization
      bloc.add(SetInitializing(false));
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
    });
    bloc.add(ShowMoodSelector(false));
    debugPrint('Mood selected: $selectedMood, session is now active');
    _addInitialAIMessage(selectedMood);
    _startSessionTimer();
  }

  String _getWelcomeMessage(Mood mood) {
    switch (mood) {
      case Mood.happy:
        return "I'm glad to hear you're feeling positive today! What would you like to talk about?";
      case Mood.sad:
        return "I'm sorry to hear you're feeling down. Would you like to talk about what's troubling you?";
      case Mood.anxious:
        return "I notice you're feeling anxious. Let's explore what's causing these feelings and find ways to help you feel more at ease.";
      case Mood.angry:
        return "I can see you're feeling frustrated or angry. It's good to acknowledge these emotions. Would you like to talk about what triggered these feelings?";
      case Mood.stressed:
        return "It sounds like you're under stress. Let's talk about what's happening and explore some coping strategies that might help.";
      default:
        return "Thank you for sharing how you're feeling. What would you like to focus on in our conversation today?";
    }
  }

  void _addInitialAIMessage(Mood mood) {
    final state = context.read<VoiceSessionBloc>().state;
    String welcomeMessage = _getWelcomeMessage(mood);

    final aiMessage = TherapyMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_ai',
      content: welcomeMessage,
      isUser: false,
      timestamp: DateTime.now(),
    );

    // Add message to Bloc
    context.read<VoiceSessionBloc>().add(AddMessage(aiMessage));

    // If in voice mode, generate TTS for the welcome message
    if (state.isVoiceMode) {
      debugPrint('[ChatScreen] Starting welcome TTS in voice mode');

      _voiceService.streamAndPlayTTS(
        text: welcomeMessage,
        onDone: () {
          debugPrint('[ChatScreen] Welcome TTS completed');
        },
        onError: (error) {
          debugPrint('Welcome TTS Error: $error');
        },
      );
    }
  }

  void _startSessionTimer() {
    // Cancel any existing timer
    _sessionTimer?.cancel();

    // Start a new timer that updates every second
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        context.read<VoiceSessionBloc>().add(UpdateSessionTimer());
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

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

  Future<void> _endSession() async {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;

    // Prevent multiple end session calls
    if (state.isEndingSession || state.isProcessing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session ending in progress...')),
      );
      return;
    }

    // Don't generate a summary if the session didn't actually start
    if (state.messages.isEmpty ||
        state.showDurationSelector ||
        state.showMoodSelector) {
      if (kDebugMode) {
        print(
            'Session not properly started, skipping session summary generation');
      }
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

    if (result != true || !mounted) return;

    // Start ending session
    bloc.add(SetEndingSession(true));
    bloc.add(SetProcessing(true));

    _navigationService.showBottomNav();

    // Stop audio and clean up resources through the bloc - WAIT for completion
    bloc.add(const EndSession());

    // Give the EndSession event time to complete audio cleanup
    await Future.delayed(const Duration(milliseconds: 500));

    // Additional safety: Force stop audio directly
    try {
      await _voiceService.stopAudio();
      await _voiceService.stopRecording();
      _voiceService.resetTTSState();
    } catch (e) {
      debugPrint('[ChatScreen] Direct audio cleanup error: $e');
    }

    // Show progress dialog
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
      // Generate session summary
      final sessionData = await _generateSessionSummary(state.messages);

      // Save session
      await _saveSession(sessionData, state.messages);

      // Close progress dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Navigate to summary screen
      if (!mounted) return;

      context.pushReplacement(
        '/session_summary',
        extra: {
          'sessionId': _currentSessionId,
          'summary': sessionData['summary'],
          'actionItems': sessionData['actionItems'],
          'insights': sessionData['insights'],
          'messages': state.messages,
          'initialMood': _initialMood,
        },
      );
    } catch (e) {
      // Close progress dialog if still showing
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      bloc.add(SetEndingSession(false));
      bloc.add(SetProcessing(false));

      if (kDebugMode) {
        print('Error ending session: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Unable to generate session summary: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Try Again',
              onPressed: _endSession,
            ),
          ),
        );
      }
    }
  }

  Future<void> _cleanupSessionResources() async {
    if (kDebugMode) {
      print('🛑 Ending session: stopping and disposing VoiceService');
    }

    await _voiceService.autoListeningCoordinator.disableAutoMode();
    await _voiceService.stopRecording();
    await _voiceService.stopAudio();
    _micAnimationController.stop();
    _micAnimationController.reset();

    // Re-register services for fresh instance
    _reregisterServices();
  }

  void _reregisterServices() {
    if (kDebugMode) {
      print('🔄 Re-registering VoiceService and AudioGenerator');
    }

    // Unregister existing services
    if (serviceLocator.isRegistered<VoiceService>()) {
      serviceLocator.unregister<VoiceService>();
    }
    if (serviceLocator.isRegistered<AudioGenerator>()) {
      serviceLocator.unregister<AudioGenerator>();
    }

    // Register new instances
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

    // Update local reference
    _voiceService = serviceLocator<VoiceService>();
    _initializeServices();
  }

  Future<Map<String, dynamic>> _generateSessionSummary(
      List<TherapyMessage> messages) async {
    if (kDebugMode) {
      print('Ending session with ID: $_currentSessionId');
    }

    // Log mood
    if (_initialMood != null) {
      await _progressService.logMood(_initialMood!);
    }

    // Prepare messages for the session summary
    final messageList = messages.map((m) => m.toJson()).toList();

    if (kDebugMode) {
      print('Ending therapy session with ${messageList.length} messages');
    }

    // Get session summary from therapy service
    final sessionData = await _therapyService.endSession(messageList);

    // Safely extract and convert lists to List<String>
    final actionItemsDynamic = sessionData['action_items'] as List<dynamic>? ??
        sessionData['actionItems'] as List<dynamic>? ??
        ['Take care of yourself', 'Return soon for another session'];

    final insightsDynamic = sessionData['insights'] as List<dynamic>? ?? [];

    return {
      'summary': sessionData['summary'] as String? ??
          'Thank you for your session today. I hope our conversation was helpful.',
      'actionItems': actionItemsDynamic.map((item) => item.toString()).toList(),
      'insights': insightsDynamic.map((item) => item.toString()).toList(),
    };
  }

  Future<void> _saveSession(
      Map<String, dynamic> sessionData, List<TherapyMessage> messages) async {
    try {
      final sessionRepository = serviceLocator<SessionRepository>();
      final messageRepository = serviceLocator<MessageRepository>();

      // Ensure the session exists in the repository
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
          _currentSessionId = createdSession.id;
        }
      }

      // Save the session with its summary and messages
      await sessionRepository.saveSession(
        id: _currentSessionId,
        messages: messages.map((m) => m.toJson()).toList(),
        summary: sessionData['summary'],
        actionItems:
            (sessionData['actionItems'] as List<dynamic>).cast<String>(),
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
  }

  // Toggle between voice and text chat modes
  void _toggleChatMode() {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;

    debugPrint(
        '🔄 Switching from ${state.isVoiceMode ? "voice" : "chat"} to ${state.isVoiceMode ? "chat" : "voice"} mode');

    // Stop any ongoing audio before switching
    bloc.add(StopAudio());

    setState(() {
      _messageController.clear();
    });

    // Toggle the mode in the bloc
    bloc.add(SwitchMode(!state.isVoiceMode));

    debugPrint('🔄 Mode switch complete');
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
}
