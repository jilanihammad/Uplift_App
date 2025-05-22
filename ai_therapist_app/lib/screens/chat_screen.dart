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
import 'package:ai_therapist_app/services/vad_manager.dart';

class ChatScreen extends StatefulWidget {
  final String? sessionId;

  const ChatScreen({Key? key, this.sessionId}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isProcessing = ValueNotifier(false);
  final ValueNotifier<bool> _isVADActive = ValueNotifier(false);
  final ValueNotifier<bool> _isRecording = ValueNotifier(false);
  bool _showMoodSelector = false;
  bool _showDurationSelector = false;
  bool _isInitializing = true; // Add this flag to track initialization
  String _currentSessionId = '';
  Mood? _initialMood;
  TherapistStyle? _therapistStyle;

  // Mode management variables
  bool _isVoiceMode = true; // Default to voice mode
  bool _isMicMuted = false;
  bool _isSpeakerMuted = false;
  bool _isTyping = false;

  // Voice recording variables
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  late VoiceService _voiceService;
  StreamSubscription<bool>? _ttsSubscription;
  StreamSubscription<bvs.RecordingState>?
      _voiceServiceRecordingStateSubscription;

  // Session duration
  int _sessionDurationMinutes = 15; // Default is 15 minutes

  // Services
  final TherapyService _therapyService = serviceLocator<TherapyService>();
  final ProgressService _progressService = serviceLocator<ProgressService>();
  final NavigationService _navigationService =
      serviceLocator<NavigationService>();

  // Countdown timer variables
  Timer? _sessionTimer;
  int _remainingTimeSeconds = 0;

  // Declare a variable to track if session is being ended
  bool _isEndingSession = false;

  // Add a variable to track VAD state
  StreamSubscription<bool>? _vadSubscription;

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

    // Listen for text input to change button state
    _messageController.addListener(_onTextChanged);

    // Load therapist style
    _loadTherapistStyle();

    // Initialize voice service instance and setup
    _voiceService = serviceLocator<VoiceService>();
    _initializeVoiceService();

    // Listen to VAD/auto-listening state
    _vadSubscription =
        _voiceService.autoListeningModeEnabledStream.listen((enabled) {
      _isVADActive.value = enabled;
    });

    // Listen to recording state for animation
    _voiceServiceRecordingStateSubscription =
        _voiceService.recordingState.listen((
      state,
    ) {
      if (kDebugMode) {
        print(
          '[ChatScreen] Recording state update from VoiceService: $state, _isRecording: \x1B[36m${_isRecording.value}[0m',
        );
      }
      if (mounted &&
          _isRecording.value != (state == bvs.RecordingState.recording)) {
        _isRecording.value = (state == bvs.RecordingState.recording);
      }
    });

    // Setup AutoListeningCoordinator callback for VAD-completed recordings
    _voiceService.autoListeningCoordinator.onRecordingCompleteCallback = (
      audioPath,
    ) async {
      if (audioPath == null || audioPath.isEmpty) {
        if (kDebugMode) {
          print(
            '[ChatScreen][ALC Callback] Received null or empty audioPath. Skipping.',
          );
        }
        return;
      }
      if (kDebugMode) {
        print(
          '[ChatScreen][ALC Callback] Processing VAD audio from path: $audioPath',
        );
      }
      // Call the refactored _startVoiceInput with the path from VAD
      // No need to check _isRecording here, as ALC manages the recording lifecycle for VAD.
      // _startVoiceInput will handle the transcription and further processing.
      await _startVoiceInput(preRecordedAudioPath: audioPath);
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

  void _onTextChanged() {
    final isCurrentlyTyping = _messageController.text.isNotEmpty;
    if (_isTyping != isCurrentlyTyping) {
      setState(() {
        _isTyping = isCurrentlyTyping;
      });
    }
  }

  @override
  void dispose() {
    debugPrint('[ChatScreen] dispose called');
    WakelockPlus.disable(); // Allow screen to sleep after session
    _vadSubscription?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _ttsSubscription?.cancel();
    _voiceServiceRecordingStateSubscription?.cancel();
    _micAnimationController.dispose();
    _voiceService.dispose();
    _sessionTimer?.cancel();
    _navigationService.showBottomNav();
    _isProcessing.dispose();
    _isVADActive.dispose();
    _isRecording.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ChatScreen] build called');
    return WillPopScope(
      onWillPop: () async {
        print('[ChatScreen] onWillPop called');
        final blocState = context.read<ChatBloc>().state;
        final hasMessages =
            blocState is ChatLoaded && blocState.messages.isNotEmpty;
        if (hasMessages &&
            !_showDurationSelector &&
            !_showMoodSelector &&
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
            if (!_showDurationSelector &&
                !_showMoodSelector &&
                !_isInitializing)
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
            if (!_showDurationSelector &&
                !_showMoodSelector &&
                !_isInitializing)
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
            : _showDurationSelector
                ? _buildDurationSelectorView()
                : _showMoodSelector
                    ? _buildMoodSelectorView()
                    : _isVoiceMode
                        ? _buildVoiceChatView()
                        : BlocListener<ChatBloc, ChatState>(
                            listener: (context, state) {
                              final messages = _extractMessages(state);
                              if (messages.length > _previousMessageCount) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (_scrollController.hasClients) {
                                    _scrollController.animateTo(
                                      _scrollController
                                          .position.maxScrollExtent,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                });
                              }
                              _previousMessageCount = messages.length;
                            },
                            child: _buildTextChatView(),
                          ),
      ),
    );
  }

  Widget _buildDurationSelectorView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).primaryColor.withOpacity(0.05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Select Session Duration',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDurationButton(5),
                const SizedBox(width: 24),
                _buildDurationButton(15),
                const SizedBox(width: 24),
                _buildDurationButton(30),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationButton(int minutes) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _handleDurationSelection(minutes),
          splashColor: Theme.of(context).primaryColor.withOpacity(0.3),
          highlightColor: Theme.of(context).primaryColor.withOpacity(0.2),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).primaryColor.withOpacity(0.15),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$minutes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  'min',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).primaryColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoodSelectorView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).primaryColor.withOpacity(0.05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'How are you feeling today?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [MoodSelector(onMoodSelected: _handleMoodSelection)],
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to create circular buttons
  Widget _buildCircularButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (color ?? Theme.of(context).primaryColor).withOpacity(
          onPressed == null ? 0.4 : 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(child: Icon(icon, color: Colors.white, size: 24)),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceChatView() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isRecording,
      builder: (context, isRecording, _) => ValueListenableBuilder<bool>(
        valueListenable: _isProcessing,
        builder: (context, isProcessing, __) => Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      child: isRecording
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
                      isRecording
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
            if (isProcessing) const LinearProgressIndicator(),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
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
                          message: isRecording
                              ? 'Stop Recording'
                              : 'Start Recording',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _startVoiceInput,
                              child: Center(
                                child: Text(
                                  isRecording ? 'Stop' : 'Talk',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildCircularButton(
                        icon: _isSpeakerMuted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        tooltip:
                            _isSpeakerMuted ? 'Unmute Speaker' : 'Mute Speaker',
                        onPressed: () async {
                          setState(() {
                            _isSpeakerMuted = !_isSpeakerMuted;
                          });
                          if (_isSpeakerMuted) {
                            await _voiceService
                                .stopAudio(); // Ensure all audio and TTS stop immediately
                          }
                        },
                        color: _isSpeakerMuted ? Colors.grey : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _toggleChatMode,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to extract messages from any ChatState
  List<TherapyMessage> _extractMessages(ChatState state) {
    if (state is ChatLoaded) return state.messages;
    if (state is ChatCompletedState) return state.messages;
    if (state is ChatErrorState) return state.messages;
    if (state is ChatLoading) {
      // Try to get messages from previous state if possible
      // (In practice, this may not always work, but we try)
      // In this context, just return an empty list
      return [];
    }
    return [];
  }

  Widget _buildTextChatView() {
    debugPrint('[ChatScreen] _buildTextChatView called');
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                // Reset _isProcessing after Maya's reply (text or voice)
                if (_isProcessing.value &&
                    (state is ChatLoaded || state is ChatCompletedState)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _isProcessing.value = false;
                    }
                  });
                }
                List<TherapyMessage> messages = _extractMessages(state);
                // Remove scroll-to-bottom logic from here
                debugPrint(
                  '[ChatScreen] BlocBuilder: state=\x1B[33m[33m${state.runtimeType}\x1B[0m, messages.length=${messages.length}',
                );
                for (int i = 0; i < messages.length; i++) {
                  debugPrint(
                    '[ChatScreen]   message[[33m$i[0m]: [${messages[i].isUser ? 'user' : 'assistant'}] ${messages[i].content}',
                  );
                }
                if (state is ChatLoading) {
                  debugPrint('[ChatScreen] No messages yet, but processing...');
                }
                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    debugPrint(
                      '[ChatScreen] ListView.builder item $index: [${messages[index].isUser ? 'user' : 'assistant'}] ${messages[index].content}',
                    );
                    return _buildMessageItem(messages[index]);
                  },
                );
              },
            ),
          ),
          if (_isProcessing.value) const LinearProgressIndicator(),
          Container(
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
                // Text input and send button
                Row(
                  children: [
                    ScaleTransition(
                      scale: _micAnimation,
                      child: _buildMicButton(),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
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
                        onSubmitted: (_) {
                          print('[ChatScreen] TextField onSubmitted');
                          _sendMessage();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isTyping
                          ? const Icon(Icons.send)
                          : const Icon(Icons.graphic_eq),
                      tooltip:
                          _isTyping ? 'Send message' : 'Switch to voice mode',
                      onPressed: _isProcessing.value
                          ? null
                          : _isTyping
                              ? () {
                                  print('[ChatScreen] Send button pressed');
                                  _sendMessage();
                                }
                              : () {
                                  print(
                                    '[ChatScreen] Switch to voice mode button pressed',
                                  );
                                  _toggleChatMode();
                                },
                    ),
                  ],
                ),
                if (!_isTyping)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: InkWell(
                      onTap: () {
                        print(
                          '[ChatScreen] Switch to Voice Mode (bottom) tapped',
                        );
                        _toggleChatMode();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.1),
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
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(TherapyMessage message) {
    final isUser = message.isUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
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
                    message.content,
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
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.audioUrl != null)
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 20),
                        onPressed: () => _playAudio(message.audioUrl!),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                      ),
                    Text(
                      DateFormat('h:mm a').format(message.timestamp),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) const CircleAvatar(child: Icon(Icons.person)),
        ],
      ),
    );
  }

  Future<void> _initializeVoiceService() async {
    // Dispose old subscriptions before creating new ones
    await _ttsSubscription?.cancel();
    await _voiceServiceRecordingStateSubscription?.cancel();
    _ttsSubscription = null;
    _voiceServiceRecordingStateSubscription = null;

    try {
      await _voiceService.initialize();
      _ttsSubscription = _voiceService.audioPlaybackStream.listen((_) {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initialize microphone: $e')),
      );
    }

    // Subscribe to the RecordingManager-driven stream via VoiceService
    _voiceServiceRecordingStateSubscription =
        _voiceService.recordingState.listen((
      state,
    ) {
      if (kDebugMode) {
        print('[ChatScreen][REC_STATE_LISTENER] Received raw state: $state');
      }

      if (mounted) {
        if (kDebugMode) {
          print(
            '[ChatScreen][REC_STATE_LISTENER] Component is MOUNTED. Current _isRecording: ${_isRecording.value}',
          );
        }
        bool newIsRecording = (state == bvs.RecordingState.recording);
        if (kDebugMode) {
          print(
            '[ChatScreen][REC_STATE_LISTENER] Calculated newIsRecording: $newIsRecording (from state: $state)',
          );
        }

        if (_isRecording.value != newIsRecording) {
          if (kDebugMode) {
            print(
              '[ChatScreen][REC_STATE_LISTENER] _isRecording (${_isRecording.value}) != newIsRecording ($newIsRecording). Calling setState...',
            );
          }
          _isRecording.value = newIsRecording;
          if (kDebugMode) {
            print(
              '[ChatScreen][REC_STATE_LISTENER] setState COMPLETED. _isRecording is now: ${_isRecording.value}',
            );
          }
        } else {
          if (kDebugMode) {
            print(
              '[ChatScreen][REC_STATE_LISTENER] _isRecording (${_isRecording.value}) == newIsRecording ($newIsRecording). Skipping setState.',
            );
          }
        }

        // Animation logic based on the updated _isRecording
        if (_isRecording.value) {
          if (kDebugMode)
            print(
              '[ChatScreen][REC_STATE_LISTENER] Calling _startPulseMicAnimation() because _isRecording is true.',
            );
          _startPulseMicAnimation();
        } else {
          if (kDebugMode)
            print(
              '[ChatScreen][REC_STATE_LISTENER] Calling _stopPulseMicAnimation() because _isRecording is false.',
            );
          _stopPulseMicAnimation();
        }

        if (kDebugMode) {
          print(
            '[ChatScreen][REC_STATE_LISTENER] Final check. VoiceService state: $state, ChatScreen _isRecording: ${_isRecording.value}',
          );
        }
      } else {
        if (kDebugMode) {
          print(
            '[ChatScreen][REC_STATE_LISTENER] Component is NOT MOUNTED. State $state received but not processed for UI.',
          );
        }
      }
    });
  }

  void _startPulseMicAnimation() {
    if (_isRecording.value && mounted && !_micAnimationController.isAnimating) {
      _micAnimationController.repeat(reverse: true);
    }
  }

  void _stopPulseMicAnimation() {
    if (!_isRecording.value && mounted && _micAnimationController.isAnimating) {
      _micAnimationController.stop();
      _micAnimationController.reset();
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
    if (widget.sessionId != null) {
      // Load existing session (would normally fetch from repository)
      _currentSessionId = widget.sessionId ?? '';
      _showMoodSelector = false;
      _showDurationSelector = false;

      // Show loading indicator
      _isProcessing.value = true;

      // Simulate loading delay (replace with actual loading)
      await Future.delayed(const Duration(seconds: 1));

      _isProcessing.value = false;

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
      setState(() {
        _showDurationSelector = true;
        // Ensure we start in voice mode
        _isVoiceMode = true;
      });
    }
  }

  void _handleDurationSelection(int minutes) {
    setState(() {
      _sessionDurationMinutes = minutes;
      _showDurationSelector = false;
      _showMoodSelector = true;
      debugPrint('Duration selected: $minutes min, showing mood selector');
    });
  }

  void _handleMoodSelection(Mood selectedMood) {
    setState(() {
      _initialMood = selectedMood;
      _showMoodSelector = false;
      _isInitializing = false;
      debugPrint('Mood selected: $selectedMood, session is now active');
    });
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
    // Step 1: Only add the welcome message as an assistant message and play it via TTS
    // Do NOT send it to the LLM or dispatch a user message event
    final chatBloc = context.read<ChatBloc>();
    final aiWelcomeMsg = TherapyMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      content: welcomeMessage,
      isUser: false,
      timestamp: DateTime.now(),
      audioUrl: null,
    );
    // Add the assistant message to the chat state
    if (chatBloc.state is ChatLoaded) {
      final currentMessages = List<TherapyMessage>.from(
        (chatBloc.state as ChatLoaded).messages,
      );
      currentMessages.add(aiWelcomeMsg);
      chatBloc.add(ReplaceMessages(currentMessages));
    } else {
      chatBloc.add(ReplaceMessages([aiWelcomeMsg]));
    }
    // Play welcome message as audio in voice mode
    if (_isVoiceMode) {
      // Ensure AutoListeningCoordinator is in auto mode before the first TTS
      _voiceService.autoListeningCoordinator.enableAutoMode().then((_) {
        if (kDebugMode)
          print(
            '[ChatScreen] Auto mode enabled by _addInitialAIMessage before welcome TTS.',
          );
        // Now play TTS, which will trigger _startListeningAfterTTS on completion.
        // _startListeningAfterTTS will then just reset _isProcessing.
        // ALC will handle VAD reactivation based on isAiSpeaking stream.
        _voiceService.streamAndPlayTTS(
          text: welcomeMessage,
          onDone:
              _startListeningAfterTTS, // This callback will reset _isProcessing
          onError: (error) {
            if (kDebugMode)
              print(
                '[ChatScreen] Error during initial welcome TTS: $error',
              );
            // Ensure processing is reset and try to start listening anyway
            if (mounted && _isProcessing.value) {
              if (mounted) _isProcessing.value = false;
            }
            _startListeningAfterTTS(); // Attempt to recover listening state
          },
        );
      }).catchError((e) {
        if (kDebugMode)
          print(
            '[ChatScreen] Error enabling auto mode in _addInitialAIMessage: $e',
          );
        // Handle error, maybe show a message or don't proceed with TTS
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

  // Start the session countdown timer
  void _startSessionTimer() {
    // Calculate total seconds from minutes
    _remainingTimeSeconds = _sessionDurationMinutes * 60;

    // Create and start the timer
    _sessionTimer?.cancel(); // Cancel any existing timer
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTimeSeconds > 0) {
          _remainingTimeSeconds--;
          _ensureLock(); // Ensure wakelock is always enabled
        } else {
          _sessionTimer?.cancel();
          // Optionally auto-end the session or show a notification
          // For now, we'll just leave the timer at 00:00
        }
      });
    });
  }

  // Format the remaining time as mm:ss
  String _formatRemainingTime() {
    final minutes = (_remainingTimeSeconds / 60).floor();
    final seconds = _remainingTimeSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _sendMessage() async {
    debugPrint('[ChatScreen] Send button pressed');
    if (_messageController.text.trim().isEmpty) return;
    final message = _messageController.text;
    _messageController.clear();
    _isProcessing.value = true;
    _isTyping = false;
    _scrollToBottom();
    // Get conversation history (excluding the current user message)
    final currentState = context.read<ChatBloc>().state;
    final history = currentState is ChatLoaded
        ? currentState.messages
            .map(
              (m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.content,
              },
            )
            .toList() as List<Map<String, dynamic>>
        : <Map<String, dynamic>>[];
    debugPrint('[ChatScreen] _sendMessage called');
    debugPrint('[ChatScreen] _sendMessage: message="$message"');
    debugPrint('[ChatScreen] _sendMessage: history.length=${history.length}');
    context.read<ChatBloc>().add(
          SendUserMessage(
            message: message,
            history: history,
            sessionId: _currentSessionId,
          ),
        );
    debugPrint(
      '[ChatScreen] _sendMessage: Sent SendUserMessage event to ChatBloc',
    );
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
    if (_isProcessing.value) {
      if (mounted) {
        // Double check mounted before setState
        _isProcessing.value = false;
      }
    }
    // If autoMode is enabled in ALC, it should start listening automatically
    // when isAiSpeaking stream becomes false.
  }

  Future<void> _startVoiceInput({String? preRecordedAudioPath}) async {
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

    // If _isRecording is true (manual stop) OR if a preRecordedAudioPath is provided (VAD flow)
    if (_isRecording.value || preRecordedAudioPath != null) {
      if (kDebugMode) {
        print(
          '💬 CHAT: Processing voice input. Manual stop: ${_isRecording.value}, VAD path: $preRecordedAudioPath',
        );
      }

      // Ensure UI reflects processing state immediately
      if (mounted && !_isProcessing.value) {
        // Avoid redundant setState if already processing
        _isProcessing.value = true;
      }
      // If this was triggered by VAD, ensure _isRecording visually stops if it hasn't already
      // The actual recording is already stopped by AutoListeningCoordinator.
      // The _isRecording state in ChatScreen is updated via the recordingState stream.
      // However, to be absolutely sure the UI for recording stops if VAD triggers this,
      // and the stream update might be slightly delayed:
      if (preRecordedAudioPath != null && _isRecording.value && mounted) {
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
        } else if (_isRecording.value) {
          // Manual stop flow
          if (kDebugMode) {
            print(
              '💬 CHAT: Manual stop flow - Calling _voiceService.stopRecording()',
            );
          }
          transcription = await _voiceService.stopRecording();
          if (_isVoiceMode && mounted) {
            if (kDebugMode) {
              print(
                '[ChatScreen] Manual recording stopped & processed. Re-enabling ALC for voice mode.',
              );
            }
            _voiceService.autoListeningCoordinator.enableAutoMode().catchError((
              e,
            ) {
              if (kDebugMode) {
                print(
                  '[ChatScreen] Error re-enabling ALC after manual stop processing: $e',
                );
              }
            });
          }
        } else {
          if (kDebugMode) {
            print(
              '⚠️ CHAT: _startVoiceInput called to stop, but not recording and no VAD path.',
            );
          }
          if (mounted) {
            _isProcessing.value = false;
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
            _isProcessing.value = false;
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
        if (mounted && _isProcessing.value) {
          _isProcessing.value = false;
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
          if (_isProcessing.value) {
            _isProcessing.value = false;
          }
        }
      } finally {
        // Final safety net to ensure _isProcessing is false
        if (mounted && _isProcessing.value) {
          _isProcessing.value = false;
        }
      }
    } else {
      // This block is for starting recording (manual "Talk" button press when not already recording)
      if (kDebugMode) {
        print('💬 CHAT: Starting recording manually');
      }
      if (mounted && !_isProcessing.value) {
        // Ensure processing is true while attempting to start
        _isProcessing.value = true;
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
          if (_isVoiceMode) {
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
        if (mounted && _isProcessing.value) {
          _isProcessing.value = false;
        }
      }
    }
  }

  Future<void> _playAudio(String audioPath, {bool inVoiceMode = false}) async {
    // This method is primarily for playing back user-recorded or non-TTS audio.
    // TTS audio playback and its animation are now handled by isTtsActuallySpeaking stream.
    _isRecording.value = false;
    _isProcessing.value = false;

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
    // Prevent multiple end session attempts
    if (_isEndingSession || _isProcessing.value) {
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
    if (messages.isEmpty || _showDurationSelector || _showMoodSelector) {
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
      _isProcessing.value = true;
    });

    _navigationService.showBottomNav();

    // Stop and dispose audio/TTS resources robustly
    if (kDebugMode)
      print('🛑 Ending session: stopping and disposing VoiceService');
    await _voiceService.autoListeningCoordinator.disableAutoMode();
    await _voiceService.stopRecording();
    await _voiceService.stopAudio();
    _stopPulseMicAnimation();
    _isRecording.value = false;
    _isProcessing.value = false;
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
            _showDurationSelector ||
            _showMoodSelector) {
          if (kDebugMode) {
            print(
              'Invalid session state, skipping save: ' +
                  'sessionId=${_currentSessionId.isEmpty}, ' +
                  'showDurationSelector=$_showDurationSelector, ' +
                  'showMoodSelector=$_showMoodSelector',
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
        _isProcessing.value = false;
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
        _isProcessing.value = false;
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
    // Stop any ongoing audio before switching modes
    _voiceService.stopAudio();
    setState(() {
      _isVoiceMode = !_isVoiceMode;
      _messageController.clear();
      _isProcessing.value = false;
      _isTyping = false;
    });
    debugPrint('🔄 Switched to ${_isVoiceMode ? 'voice' : 'text'} mode');
  }

  void _switchToTextMode() {
    debugPrint('🔄 Switched to text mode');
    setState(() {
      _isVoiceMode = false;
    });
  }

  void _switchToVoiceMode() {
    debugPrint('🔄 Switched to voice mode');
    setState(() {
      _isVoiceMode = true;
    });
  }

  void _navigateAway() {
    debugPrint('[ChatScreen] Navigating away from chat screen');
    Navigator.of(context).pop();
  }

  Widget _buildMicButton() {
    // Determine mic state
    if (!_isVADActive.value) {
      // VAD is off: show idle/off mic
      return IconButton(
        icon: Icon(Icons.mic_off, color: Colors.grey),
        onPressed: null,
      );
    } else if (_isRecording.value) {
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
            print('[ChatScreen] Mic button pressed (recording)');
            _startVoiceInput();
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
            print('[ChatScreen] Mic button pressed (listening)');
            _startVoiceInput();
          },
        ),
      );
    }
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
