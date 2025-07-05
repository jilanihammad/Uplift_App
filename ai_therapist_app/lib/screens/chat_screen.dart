// lib/screens/chat_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/voice_session_bloc.dart';
import '../blocs/voice_session_state.dart';
import '../blocs/voice_session_event.dart';
import '../services/voice_service.dart';
import '../di/interfaces/i_therapy_service.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/i_progress_service.dart';
import '../di/interfaces/i_navigation_service.dart';
import '../widgets/mood_selector.dart';
import '../models/therapist_style.dart';
import '../models/therapy_message.dart';
import '../utils/list_extensions.dart';
import '../services/native_wakelock_service.dart';
import 'package:ai_therapist_app/screens/widgets/duration_selector.dart';
import 'package:ai_therapist_app/screens/widgets/mood_selector_screen.dart';
import 'package:ai_therapist_app/screens/widgets/chat_app_bar.dart';
import 'package:ai_therapist_app/screens/widgets/chat_interface_view.dart';
import '../widgets/debug_drawer.dart';

class ChatScreen extends StatelessWidget {
  final String? sessionId;
  
  const ChatScreen({
    super.key, 
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VoiceSessionBloc>(
      create: (context) => VoiceSessionBloc(
        // Phase 1B.2: Standardized DI - use DependencyContainer for UI layer
        voiceService: DependencyContainer().get<VoiceService>(),
        vadManager: DependencyContainer().vadManager,
        therapyService: DependencyContainer().therapy,
        interfaceVoiceService: DependencyContainer().voiceService,
        progressService: DependencyContainer().progress,
        navigationService: DependencyContainer().navigation,
      ),
      child: _ChatScreenBody(
        sessionId: sessionId,
      ),
    );
  }
}

class _ChatScreenBody extends StatefulWidget {
  final String? sessionId;
  
  const _ChatScreenBody({
    super.key, 
    this.sessionId,
  });

  @override
  State<_ChatScreenBody> createState() => _ChatScreenBodyState();
}

class _ChatScreenBodyState extends State<_ChatScreenBody>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Session state
  String _currentSessionId = '';
  Mood? _initialMood;
  TherapistStyle? _therapistStyle;

  // Voice recording variables
  late VoiceService _voiceService;

  // Services - Use dependency injection with fallback to DependencyContainer
  late final ITherapyService _therapyService;
  late final IProgressService _progressService;
  late final INavigationService _navigationService;

  // Session timer
  Timer? _sessionTimer;

  // Wakelock management - simplified and safe
  Future<void> _enableWakelock() async {
    try {
      await NativeWakelockService.enable();

      // Sanity check - verify wakelock is actually enabled
      final enabled = await NativeWakelockService.isEnabled;
      debugPrint(
          '[ChatScreen] Wakelock enabled successfully - KEEP_SCREEN_ON = $enabled');
    } catch (e) {
      debugPrint('[ChatScreen] Failed to enable wakelock: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Only manage wakelock if we're in an active therapy session
    final bloc = context.read<VoiceSessionBloc>();
    final sessionState = bloc.state;
    final isActiveSession = !sessionState.showMoodSelector &&
        !sessionState.showDurationSelector &&
        !sessionState.isInitializing &&
        sessionState.messages.isNotEmpty;

    if (!isActiveSession) {
      debugPrint(
          '[ChatScreen] Not in active session, skipping wakelock management');
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        // Re-enable wakelock when app comes back to foreground (engine is attached)
        debugPrint(
            '[ChatScreen] App resumed, re-enabling wakelock for active session');
        _enableWakelock();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Keep wakelock active during therapy session - do NOT disable
        // Screen should stay on even when notification shade is pulled down,
        // proximity sensor triggers, or other brief interruptions occur
        debugPrint(
            '[ChatScreen] App lifecycle changed to $state, keeping wakelock active for session');
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    // Only re-apply wakelock if we're in an active therapy session
    final bloc = context.read<VoiceSessionBloc>();
    final sessionState = bloc.state;
    final isActiveSession = !sessionState.showMoodSelector &&
        !sessionState.showDurationSelector &&
        !sessionState.isInitializing &&
        sessionState.messages.isNotEmpty;

    if (isActiveSession) {
      // Called on rotation, PiP, split-screen, etc. - re-apply wakelock
      debugPrint(
          '[ChatScreen] Metrics changed, re-enabling wakelock for active session');
      _enableWakelock();
    } else {
      debugPrint(
          '[ChatScreen] Metrics changed, but not in active session - skipping wakelock');
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[ChatScreen] initState called');
    WidgetsBinding.instance.addObserver(this);
    
    // Phase 1B.2: Standardized DI - use DependencyContainer for UI layer
    _therapyService = DependencyContainer().therapy;
    _progressService = DependencyContainer().progress;
    _navigationService = DependencyContainer().navigation;

    // Don't enable wakelock here - only enable during active therapy session

    // Initialize services
    _voiceService = DependencyContainer().get<VoiceService>();
    _initializeServices();
    _loadTherapistStyle();

    // Initialize session after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[ChatScreen] PostFrameCallback: calling _initSession');
      _initSession();
    });
  }

  @override
  void dispose() {
    debugPrint('[ChatScreen] dispose called');

    // Disable wakelock immediately in dispose (fire and forget)
    NativeWakelockService.disable().then((_) {
      debugPrint('[ChatScreen] Wakelock disabled successfully in dispose');
    }).catchError((e) {
      debugPrint('[ChatScreen] Failed to disable wakelock in dispose: $e');
    });

    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
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
            appBar: const ChatAppBar.simple(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Handle duration selector
        if (state.showDurationSelector) {
          return Scaffold(
            appBar: const ChatAppBar.simple(),
            body: DurationSelector(
              selectedDuration: state.sessionDurationMinutes,
              onDurationSelected: _handleDurationSelection,
            ),
          );
        }

        // Handle mood selector
        if (state.showMoodSelector) {
          return Scaffold(
            appBar: const ChatAppBar.simple(),
            body: MoodSelectorScreen(
              selectedMood: _initialMood,
              onMoodSelected: _handleMoodSelection,
            ),
          );
        }

        // Main chat interface
        return PopScope(
          canPop: true,
          onPopInvoked: (didPop) async {
            if (!didPop) return;
            final shouldPop = await _handleBackPress(state);
            if (!shouldPop && mounted) {
              // Prevent pop if not allowed
              // You may want to use Navigator.of(context).maybePop() or similar if needed
            }
          },
          child: Scaffold(
            appBar: ChatAppBar(
              therapistStyle: _therapistStyle,
              onEndSession: _endSession,
            ),
            body: ChatInterfaceView(
              onSwitchMode: _toggleChatMode,
              onSendMessage: _sendMessage,
              messageController: _messageController,
              scrollController: _scrollController,
            ),
            endDrawer: kDebugMode ? const DebugDrawer() : null,
          ),
        );
      },
    );
  }


  Future<bool> _handleBackPress(VoiceSessionState state) async {
    debugPrint('[ChatScreen] onWillPop called');
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
    final preferencesService = DependencyContainer().preferences;
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
      debugPrint('Loaded therapist style: ${_therapistStyle!.name}');
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
      // Generate a temporary UUID for local session tracking
      // This will be replaced with the backend session ID when the session ends
      _currentSessionId = const Uuid().v4();

      if (kDebugMode) {
        debugPrint('Generated temporary session ID for local tracking: $_currentSessionId');
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
    
    // Phase 1A.4: Dispatch BLoC event instead of direct logic
    bloc.add(MoodSelected(selectedMood));
    
    debugPrint('Mood selected: $selectedMood, session is now active');

    // UI concerns remain in UI layer (as planned)
    setState(() {
      _initialMood = selectedMood;
    });

    // Hide bottom navigation bar during therapy session to prevent accidental navigation
    _navigationService.hideBottomNav();

    // Ensure speaker is unmuted for new session (in case previous session ended with mute)
    bloc.add(SetSpeakerMuted(false));

    // Enable wakelock now that therapy session is starting
    _enableWakelock();

    // Start session timer (UI concern)
    _startSessionTimer();
  }

  String _getWelcomeMessage(Mood mood) {
    switch (mood) {
      case Mood.happy:
        return [
          "Heyyy! What's keeping your spirits high today?",
          "Hello hello! Your positivity is contagious! What's on your mind?",
          "Hey there! Glad you're feeling upbeat! How can I support you today?",
          "Heyyy! Hearing you're happy makes me happy! Anything special you'd like to talk about?",
          "Hello hello! Would you like to share more about what's brightening your day?"
        ].random();
      case Mood.sad:
        return [
          "I'm here for you. Would you like to talk about what's making you feel this way?",
          "I'm sorry things feel tough right now. I'm ready to listen whenever you're comfortable sharing.",
          "It's okay to feel sad sometimes. What's weighing on your mind?",
          "I understand you're feeling down, and I'd like to help. What's troubling you today?",
          "You're not alone—let's take some time to talk about how you're feeling."
        ].random();
      case Mood.anxious:
        return [
          "Let's take a moment together and gently explore what's causing your anxiety today.",
          "I see you're feeling anxious, and I'm here with you. What's making you feel this way?",
          "It's perfectly natural to feel anxious sometimes. Do you want to talk about what's on your mind?",
          "I'm here to help you navigate these feelings. What's causing your anxiety right now?",
          "Anxiety can feel overwhelming. Let's slow down together and discuss what's triggering these feelings."
        ].random();
      case Mood.angry:
        return [
          "It's good that you're acknowledging your anger. Would talking about what's causing it help?",
          "I can sense you're upset right now. I'm here to listen when you're ready.",
          "Your feelings matter—would you like to share what's behind this frustration?",
          "It's understandable to feel this way sometimes. Want to discuss what's triggering these emotions?",
          "I'm glad you're recognizing these feelings. What's causing your anger today?"
        ].random();
      case Mood.stressed:
        return [
          "It sounds like you're dealing with a lot. Would you like to share what's stressing you out?",
          "Stress can be really challenging. Let's talk it through and find ways to ease the burden.",
          "I'm here to help you unpack this stress. What's been heavy on your mind?",
          "I see things are feeling tough right now. Want to talk about what's making you feel this way?",
          "You're managing a lot. Let's discuss what's going on and explore some helpful strategies."
        ].random();
      default:
        return [
          "Hey there! Thanks for opening up about how you're feeling. What should we explore today?",
          "Hello hello! What would you like to talk about?",
          "Heyyy! Thanks for sharing with me. How can I best support you today?",
          "Hey there! What brings you here today?",
          "Hello hello! I'm glad you're here. Where should we start our conversation today?"
        ].random();
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
      sequence: 1,
    );

    // Add message to Bloc
    context.read<VoiceSessionBloc>().add(AddMessage(aiMessage));

    // If in voice mode, generate TTS for welcome message WITHOUT LLM processing
    if (state.isVoiceMode) {
      debugPrint('[ChatScreen] Starting welcome TTS without LLM processing');
      
      // Use PlayWelcomeMessage event to ensure proper TTS state management
      context.read<VoiceSessionBloc>().add(PlayWelcomeMessage(welcomeMessage));
    }
  }

  void _startSessionTimer() {
    // Cancel any existing timer
    _sessionTimer?.cancel();

    // Start a new timer that updates every second
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        context.read<VoiceSessionBloc>().add(UpdateSessionTimer());

        // Timer continues - no wakelock refresh needed here
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      debugPrint('[ChatScreen] _sendMessage called but text is empty');
      return;
    }

    debugPrint('[ChatScreen] Sending text message: "$text"');
    // Phase 1A.4: Dispatch BLoC event instead of direct logic
    context.read<VoiceSessionBloc>().add(TextMessageSent(text));
    _messageController.clear();
  }


  Future<void> _endSession() async {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;

    // Prevent multiple end session calls
    if (state.isEndingSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session ending in progress...')),
      );
      return;
    }

    // Phase 1A.4: Dispatch BLoC event for core business logic
    bloc.add(const EndSessionRequested());

    // UI concerns remain in UI layer (as planned)
    // Disable wakelock immediately since session is ending
    try {
      await NativeWakelockService.disable();
      debugPrint('[ChatScreen] Wakelock disabled successfully in _endSession');
    } catch (e) {
      debugPrint('[ChatScreen] Failed to disable wakelock in _endSession: $e');
    }

    // Explicitly stop VAD immediately to prevent it from continuing to run
    try {
      await DependencyContainer().vadManager.stopListening();
      debugPrint('[ChatScreen] VAD explicitly stopped in _endSession');
    } catch (e) {
      debugPrint('[ChatScreen] Failed to stop VAD in _endSession: $e');
    }

    // Don't generate a summary if the session didn't actually start
    if (state.messages.isEmpty ||
        state.showDurationSelector ||
        state.showMoodSelector) {
      if (kDebugMode) {
        debugPrint(
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

      // Use backend session ID for navigation if available
      final sessionIdForNavigation = sessionData['id']?.toString() ?? _currentSessionId;
      
      context.pushReplacement(
        '/session_summary',
        extra: {
          'sessionId': sessionIdForNavigation,
          'summary': sessionData['summary'],
          'actionItems': sessionData['action_items'] ?? sessionData['actionItems'],
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
        debugPrint('Error ending session: $e');
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


  Future<Map<String, dynamic>> _generateSessionSummary(
      List<TherapyMessage> messages) async {
    if (kDebugMode) {
      debugPrint('Ending session with ID: $_currentSessionId');
    }

    // Log mood
    if (_initialMood != null) {
      await _progressService.logMood(_initialMood!);
    }

    // Prepare messages for the session summary
    final messageList = messages.map((m) => m.toJson()).toList();

    if (kDebugMode) {
      debugPrint('Ending therapy session with ${messageList.length} messages');
    }

    // Generate session title to pass to backend
    final sessionTitle = 'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';

    // Get session summary from therapy service, passing session metadata
    final sessionData = await _therapyService.endSessionWithMessages(
      messageList, 
      sessionTitle: sessionTitle,
      userId: 1, // Default user ID for now
    );

    // Safely extract and convert lists to List<String>
    final actionItemsDynamic = sessionData['action_items'] as List<dynamic>? ??
        sessionData['actionItems'] as List<dynamic>? ??
        ['Take care of yourself', 'Return soon for another session'];

    final insightsDynamic = sessionData['insights'] as List<dynamic>? ?? [];

    return {
      'id': sessionData['id'], // Include backend session ID
      'summary': sessionData['summary'] as String? ??
          'Thank you for your session today. I hope our conversation was helpful.',
      'action_items': actionItemsDynamic.map((item) => item.toString()).toList(),
      'actionItems': actionItemsDynamic.map((item) => item.toString()).toList(), // Keep both for compatibility
      'insights': insightsDynamic.map((item) => item.toString()).toList(),
    };
  }

  Future<void> _saveSession(
      Map<String, dynamic> sessionData, List<TherapyMessage> messages) async {
    try {
      final sessionRepository = DependencyContainer().sessionRepository;

      // If we have a backend session ID from the response, use it
      final backendSessionId = sessionData['id']?.toString();
      final sessionIdToUse = backendSessionId ?? _currentSessionId;
      
      if (kDebugMode) {
        debugPrint('Saving session with ID: $sessionIdToUse (backend ID: $backendSessionId)');
      }

      // If we have a backend session ID, the session is already created on the backend
      // Just save to local database for offline access
      if (backendSessionId != null) {
        // Extract action items from session data
        final actionItemsDynamic = sessionData['action_items'] as List<dynamic>? ??
            sessionData['actionItems'] as List<dynamic>? ??
            [];
        final actionItems = actionItemsDynamic.map((item) => item.toString()).toList();
        
        await sessionRepository.saveSession(
          sessionId: sessionIdToUse,
          title: 'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
          summary: sessionData['summary'],
          actionItems: actionItems,
          messages: messages.map((m) => m.toJson()).toList(),
        );
        
        if (kDebugMode) {
          debugPrint('Saved session $sessionIdToUse to local database with ${actionItems.length} action items');
          debugPrint('Action items saved: ${actionItems.join(", ")}');
        }
        
        // Update current session ID to the backend ID
        _currentSessionId = sessionIdToUse;
      } else {
        // Fallback: old flow for when backend doesn't return an ID
        final sessionTitle = 'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';
        
        try {
          await sessionRepository.getSession(_currentSessionId);
        } catch (e) {
          final createdSession = await sessionRepository.createSession(
            sessionTitle,
            id: _currentSessionId,
          );
          if (createdSession.id != _currentSessionId) {
            _currentSessionId = createdSession.id;
          }
        }

        // Extract action items from session data for fallback case too
        final actionItemsDynamic = sessionData['action_items'] as List<dynamic>? ??
            sessionData['actionItems'] as List<dynamic>? ??
            [];
        final actionItems = actionItemsDynamic.map((item) => item.toString()).toList();
        
        await sessionRepository.saveSession(
          sessionId: _currentSessionId,
          title: sessionTitle,
          summary: sessionData['summary'],
          actionItems: actionItems,
          messages: messages.map((m) => m.toJson()).toList(),
        );
      }

      if (kDebugMode) {
        debugPrint('Session saved to repository successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving session to repository: $e');
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

}
