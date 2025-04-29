// lib/screens/chat_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

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

class ChatScreen extends StatefulWidget {
  final String? sessionId;

  const ChatScreen({
    Key? key,
    this.sessionId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<TherapyMessage> _messages = [];
  bool _isProcessing = false;
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
  bool _isTtsSpeaking = false;

  // Voice recording variables
  late AnimationController _micAnimationController;
  late Animation<double> _micAnimation;
  late AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;
  final VoiceService _voiceService = serviceLocator<VoiceService>();
  bool _isRecording = false;
  StreamSubscription<RecordingState>? _recordingStateSubscription;

  // Session duration
  int _sessionDurationMinutes = 15; // Default is 15 minutes

  // Services
  final TherapyService _therapyService = serviceLocator<TherapyService>();
  final ProgressService _progressService = serviceLocator<ProgressService>();

  // Countdown timer variables
  Timer? _sessionTimer;
  int _remainingTimeSeconds = 0;

  @override
  void initState() {
    super.initState();

    // Set up microphone animation
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _micAnimation = Tween(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _micAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Set up rotation animation for the speaking circle
    _rotationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _rotationAnimation = Tween(begin: 0.0, end: 2.0 * 3.14159).animate(
      CurvedAnimation(
        parent: _rotationAnimationController,
        curve: Curves.linear,
      ),
    );

    // Listen for text input to change button state
    _messageController.addListener(_onTextChanged);

    // Load therapist style
    _loadTherapistStyle();

    // Initialize voice service
    _initializeVoiceService();

    // Initialize session after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSession().then((_) {
        setState(() {
          _isInitializing = false;
        });
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
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _recordingStateSubscription?.cancel();
    _micAnimationController.dispose();
    _rotationAnimationController.dispose();
    _voiceService.dispose();
    _sessionTimer?.cancel(); // Cancel the timer when disposing
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _confirmExit(context),
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
                    child: Icon(_therapistStyle!.icon,
                        size: 16, color: _therapistStyle!.color),
                  ),
                ),
            ],
          ),
          actions: [
            // Countdown timer - only show when in session
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
                          horizontal: 10, vertical: 4),
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
            // Only show End button when in actual chat (not during setup screens)
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
                        : _buildTextChatView(),
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
              children: [
                MoodSelector(
                  onMoodSelected: _handleMoodSelection,
                ),
              ],
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
        color: (color ?? Theme.of(context).primaryColor)
            .withOpacity(onPressed == null ? 0.4 : 0.85),
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
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceChatView() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Main empty area with central voice indicator
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Circle for voice visualization
                  AnimatedBuilder(
                    animation: _rotationAnimationController,
                    builder: (context, child) {
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isTtsSpeaking
                              ? SweepGradient(
                                  center: Alignment.center,
                                  startAngle: 0.0,
                                  endAngle: 2 * 3.14159,
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.7),
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.5),
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.3),
                                    Theme.of(context).primaryColor,
                                  ],
                                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                                  transform: GradientRotation(
                                      _rotationAnimation.value),
                                )
                              : null,
                          color: _isTtsSpeaking
                              ? null
                              : Theme.of(context)
                                  .disabledColor
                                  .withOpacity(0.3),
                        ),
                        child: Center(
                          child: Icon(
                            _isTtsSpeaking ? Icons.volume_up : Icons.mic,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isTtsSpeaking
                        ? "Maya is speaking..."
                        : _isRecording
                            ? "Listening to you..."
                            : "Tap the mic button to speak",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isProcessing) const LinearProgressIndicator(),

          // Bottom control buttons
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
                // Switch to Chat Mode button
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: InkWell(
                    onTap: _toggleChatMode,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                ),

                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Voice input button (Talk)
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_isRecording
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
                        message:
                            _isRecording ? 'Stop Recording' : 'Start Recording',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _startVoiceInput,
                            child: Center(
                              child: Text(
                                _isRecording ? 'Stop' : 'Talk',
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

                    // Speaker mute/unmute button
                    _buildCircularButton(
                      icon:
                          _isSpeakerMuted ? Icons.volume_off : Icons.volume_up,
                      tooltip:
                          _isSpeakerMuted ? 'Unmute Speaker' : 'Mute Speaker',
                      onPressed: () {
                        setState(() {
                          _isSpeakerMuted = !_isSpeakerMuted;
                        });

                        if (_isSpeakerMuted) {
                          _voiceService.stopAudio();
                          setState(() {
                            _isTtsSpeaking = false;
                          });
                        }
                      },
                      color: _isSpeakerMuted ? Colors.grey : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextChatView() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Main chat area
          Expanded(
            child: _messages.isEmpty && _isProcessing
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      return _buildMessageItem(message);
                    },
                  ),
          ),

          if (_isProcessing) const LinearProgressIndicator(),

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
                      child: IconButton(
                        icon: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: _isRecording ? Colors.red : null,
                        ),
                        onPressed: _startVoiceInput,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                          ),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isTyping
                          ? const Icon(Icons.send)
                          : const Icon(Icons.graphic_eq),
                      tooltip:
                          _isTyping ? 'Send message' : 'Switch to voice mode',
                      onPressed: _isProcessing
                          ? null
                          : _isTyping
                              ? _sendMessage
                              : _toggleChatMode,
                    ),
                  ],
                ),

                // Add Switch to voice mode button
                if (!_isTyping)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: InkWell(
                      onTap: _toggleChatMode,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Voice waves icon
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
                      color: isUser ? Colors.white : Colors.black87,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            const CircleAvatar(
              child: Icon(Icons.person),
            ),
        ],
      ),
    );
  }

  Future<void> _initializeVoiceService() async {
    try {
      await _voiceService.initialize();

      // Listen to recording state changes
      _recordingStateSubscription =
          _voiceService.recordingState.listen((state) {
        if (state == RecordingState.recording) {
          _startPulseMicAnimation();
        } else {
          _stopPulseMicAnimation();
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initialize microphone: $e')),
      );
    }
  }

  void _startPulseMicAnimation() {
    _micAnimationController.repeat(reverse: true);
    setState(() {
      _isRecording = true;
    });
  }

  void _stopPulseMicAnimation() {
    _micAnimationController.stop();
    _micAnimationController.reset();
    setState(() {
      _isRecording = false;
    });
  }

  // Show a confirmation dialog when user tries to navigate away
  Future<bool> _confirmExit(BuildContext context) async {
    if (_messages.isEmpty) {
      // No messages to save, allow exit without confirmation
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End ongoing session?'),
        content: const Text(
            'Are you sure you want to end the current therapy session? Your progress will be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // End session and save before navigating
              _endSession().then((_) {
                Navigator.of(context).pop(true);
              });
            },
            child: const Text('End and Save'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _loadTherapistStyle() async {
    final preferencesService = serviceLocator<PreferencesService>();
    final userPreferences = preferencesService.preferences;

    // Set therapist style
    _therapistStyle = TherapistStyle.getById(
        userPreferences?.therapistStyleId ?? 'humanistic');

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
      setState(() {
        _isProcessing = true;
      });

      // Simulate loading delay (replace with actual loading)
      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _addAIMessage(
            'Welcome back to our session! How have you been since we last talked?');
        _isProcessing = false;

        // Start the session timer for continuing sessions too
        _startSessionTimer();
      });
    } else {
      // Start new session
      _currentSessionId = const Uuid().v4();

      // Create the session in the repository to ensure it exists
      try {
        final sessionRepository = serviceLocator<SessionRepository>();
        final sessionTitle =
            'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';

        await sessionRepository.createSession(sessionTitle,
            id: _currentSessionId);

        if (kDebugMode) {
          print('Created new session with ID: $_currentSessionId');
        }
      } catch (e) {
        // Log the error but continue the session
        if (kDebugMode) {
          print('Error creating session in repository: $e');
        }
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
    });
  }

  void _handleMoodSelection(Mood selectedMood) {
    // First update state for UI
    setState(() {
      _initialMood = selectedMood;
      _showMoodSelector = false;
      _isProcessing = true; // Show loading indicator
      // Ensure we start in voice mode
      _isVoiceMode = true;

      // Start the session timer
      _startSessionTimer();
    });

    // Add initial AI message based on mood
    String welcomeMessage;
    if (selectedMood == Mood.happy) {
      welcomeMessage =
          "I'm glad to hear you're feeling positive today! What would you like to talk about?";
    } else if (selectedMood == Mood.sad) {
      welcomeMessage =
          "I'm sorry to hear you're feeling down. Would you like to talk about what's troubling you?";
    } else if (selectedMood == Mood.anxious) {
      welcomeMessage =
          "I notice you're feeling anxious. Let's explore what's causing these feelings and find ways to help you feel more at ease.";
    } else if (selectedMood == Mood.angry) {
      welcomeMessage =
          "I can see you're feeling frustrated or angry. It's good to acknowledge these emotions. Would you like to talk about what triggered these feelings?";
    } else if (selectedMood == Mood.stressed) {
      welcomeMessage =
          "It sounds like you're under stress. Let's talk about what's happening and explore some coping strategies that might help.";
    } else {
      welcomeMessage =
          "Thank you for sharing how you're feeling. What would you like to focus on in our conversation today?";
    }

    // Wait briefly to ensure UI is updated
    Future.microtask(() {
      _addAIMessage(welcomeMessage);
    });
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
    if (_messageController.text.trim().isEmpty) return;

    final message = _messageController.text;
    _messageController.clear();

    final userMessage = TherapyMessage(
      id: const Uuid().v4(),
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isProcessing = true;
      _isTyping = false;
    });

    _scrollToBottom();

    // Get AI response using therapy service
    try {
      if (_isVoiceMode) {
        // Voice mode - get response with audio
        final response =
            await _therapyService.processUserMessageWithAudio(message);

        final aiMessage = TherapyMessage(
          id: const Uuid().v4(),
          content: response['text'],
          isUser: false,
          timestamp: DateTime.now(),
          audioUrl: response['audioPath'],
        );

        setState(() {
          _messages.add(aiMessage);
          _isProcessing = false;
        });

        _scrollToBottom();

        // Auto-play the response if audio is available
        if (aiMessage.audioUrl != null && !_isSpeakerMuted) {
          await _playAudio(aiMessage.audioUrl!, inVoiceMode: true);
        }
      } else {
        // Text mode - get response without audio to save API calls
        final response = await _therapyService.processUserMessage(message);

        final aiMessage = TherapyMessage(
          id: const Uuid().v4(),
          content: response,
          isUser: false,
          timestamp: DateTime.now(),
        );

        setState(() {
          _messages.add(aiMessage);
          _isProcessing = false;
        });

        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _addAIMessage(String text) async {
    final message = TherapyMessage(
      id: const Uuid().v4(),
      content: text,
      isUser: false,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(message);
      _isProcessing = true;
    });

    _scrollToBottom();

    try {
      if (_isVoiceMode) {
        // Generate audio for voice mode
        final audioPath =
            await _voiceService.generateAudio(text, isAiSpeaking: true);

        // Update the message with the audio URL
        final indexOfMessage = _messages.indexWhere((m) => m.id == message.id);
        if (indexOfMessage != -1) {
          setState(() {
            _messages[indexOfMessage] = message.copyWith(audioUrl: audioPath);
            _isProcessing = false;
          });

          // Auto-play the welcome message
          if (!_isSpeakerMuted) {
            await _playAudio(audioPath, inVoiceMode: true);
          }
        }
      } else {
        // In text mode, we don't generate audio
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error generating audio for welcome message: $e');
      }
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _scrollToBottom() {
    // Wait for layout to complete before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startVoiceInput() async {
    if (_isRecording) {
      // Stop recording and process
      final transcription = await _voiceService.stopRecording();

      if (transcription.isNotEmpty) {
        setState(() {
          _isProcessing = true;
        });

        try {
          // Add user message
          final userMessage = TherapyMessage(
            id: const Uuid().v4(),
            content: transcription,
            isUser: true,
            timestamp: DateTime.now(),
          );

          setState(() {
            _messages.add(userMessage);
          });

          _scrollToBottom();

          if (_isVoiceMode) {
            // In voice mode, get AI response with audio
            final response = await _therapyService
                .processUserMessageWithAudio(transcription);

            final aiMessage = TherapyMessage(
              id: const Uuid().v4(),
              content: response['text'],
              isUser: false,
              timestamp: DateTime.now(),
              audioUrl: response['audioPath'],
            );

            setState(() {
              _messages.add(aiMessage);
              _isProcessing = false;
            });

            _scrollToBottom();

            // Auto-play the response in voice mode
            if (aiMessage.audioUrl != null && !_isSpeakerMuted) {
              await _playAudio(aiMessage.audioUrl!, inVoiceMode: true);
            }
          } else {
            // In text mode, get response without audio to save API calls
            final response =
                await _therapyService.processUserMessage(transcription);

            final aiMessage = TherapyMessage(
              id: const Uuid().v4(),
              content: response,
              isUser: false,
              timestamp: DateTime.now(),
            );

            setState(() {
              _messages.add(aiMessage);
              _isProcessing = false;
            });

            _scrollToBottom();
          }
        } catch (e) {
          setState(() {
            _isProcessing = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error processing voice: $e')),
          );
        }
      }
    } else {
      // Start recording
      await _voiceService.startRecording();
    }
  }

  Future<void> _playAudio(String audioPath, {bool inVoiceMode = false}) async {
    if (inVoiceMode) {
      _updateSpeakingAnimation(true);
    } else {
      setState(() {
        _isRecording = true;
      });
    }

    try {
      await _voiceService.playAudio(audioPath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    } finally {
      if (mounted) {
        if (inVoiceMode) {
          _updateSpeakingAnimation(false);
        } else {
          setState(() {
            _isRecording = false;
          });
        }
      }
    }
  }

  Future<void> _endSession() async {
    if (_messages.isEmpty) {
      // No messages to end session with
      Navigator.pop(context);
      return;
    }

    // Show confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content:
            const Text('Are you sure you want to end this therapy session?'),
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

    // Stop any ongoing audio playback immediately
    await _voiceService.stopAudio();

    setState(() {
      _isProcessing = true;
    });

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
      final messageList = _messages.map((m) => m.toJson()).toList();

      if (kDebugMode) {
        print('Ending therapy session with ${messageList.length} messages');
      }

      // Get session summary from therapy service
      final sessionData = await _therapyService.endSession(messageList);

      final summary = sessionData['summary'] as String;
      final actionItems = sessionData['actionItems'] as List<dynamic>;
      final insights = sessionData['insights'] as List<dynamic>? ?? [];

      if (kDebugMode) {
        print('Session summary generated successfully');
      }

      // Save the session to the repository
      try {
        final sessionRepository = serviceLocator<SessionRepository>();

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
          await sessionRepository.createSession(sessionTitle,
              id: _currentSessionId);
        }

        // Now save the session with its summary and messages
        await sessionRepository.saveSession(
          id: _currentSessionId,
          messages: _messages.map((m) => m.toJson()).toList(),
          summary: summary,
          actionItems: actionItems.cast<String>(),
          initialMood: _initialMood,
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

      setState(() {
        _isProcessing = false;
      });

      // Navigate to summary screen using GoRouter instead of named routes
      if (!mounted) return;

      // Use context.push for GoRouter navigation
      context.push('/session_summary', extra: {
        'sessionId': _currentSessionId,
        'summary': summary,
        'actionItems': actionItems.cast<String>(),
        'insights': insights.cast<String>(),
        'messages': _messages,
        'initialMood': _initialMood,
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ending session: $e')),
      );
    }
  }

  // Toggle between voice and text chat modes
  void _toggleChatMode() {
    // Stop any ongoing audio before switching modes
    _voiceService.stopAudio();

    setState(() {
      _isVoiceMode = !_isVoiceMode;
      _isTtsSpeaking = false;
    });
  }

  // Method to control TTS speaking animation
  void _updateSpeakingAnimation(bool isSpeaking) {
    setState(() {
      _isTtsSpeaking = isSpeaking;
    });

    if (isSpeaking) {
      _rotationAnimationController.repeat();
    } else {
      _rotationAnimationController.stop();
    }
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({
    Key? key,
    required this.text,
    required this.isUser,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                    color: Color.fromRGBO(0, 0, 0, 0.1),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            const CircleAvatar(
              child: Icon(Icons.person),
            ),
        ],
      ),
    );
  }
}
