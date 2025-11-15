// lib/screens/chat_screen.dart

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
import '../services/facades/legacy_voice_facade.dart';
import '../di/interfaces/i_therapy_service.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/i_progress_service.dart';
import '../di/interfaces/i_navigation_service.dart';
import '../widgets/mood_selector.dart';
import '../models/therapist_style.dart';
import '../models/therapy_message.dart';
import '../services/native_wakelock_service.dart';
import 'package:ai_therapist_app/screens/widgets/duration_selector.dart';
import 'package:ai_therapist_app/screens/widgets/mood_selector_screen.dart';
import 'package:ai_therapist_app/screens/widgets/chat_app_bar.dart';
import 'package:ai_therapist_app/screens/widgets/chat_interface_view.dart';
import '../widgets/debug_drawer.dart';
import '../utils/app_logger.dart';
import '../utils/feature_flags.dart';
import '../services/pipeline/voice_pipeline_controller.dart';

class ChatScreen extends StatelessWidget {
  final String? sessionId;

  const ChatScreen({
    super.key,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<VoiceSessionBloc>(
      create: (context) {
        final dependencyContainer = DependencyContainer();
        final voiceService = dependencyContainer.get<VoiceService>();
        final useFacade = FeatureFlags.isVoiceFacadeEnabled;
        final sessionFacade = useFacade
            ? dependencyContainer.voiceModeFacade
            : LegacyVoiceFacade(
                voiceService: voiceService,
                therapyService: dependencyContainer.therapy,
              );

        VoicePipelineControllerFactory? pipelineFactory;
        final controllerFlag = FeatureFlags.isVoicePipelineControllerEnabled;
        if (controllerFlag &&
            dependencyContainer
                .isRegistered<VoicePipelineControllerFactory>()) {
          pipelineFactory =
              dependencyContainer.get<VoicePipelineControllerFactory>();
        }

        return VoiceSessionBloc(
          voiceFacade: sessionFacade,
          // Phase 1B.2: Standardized DI - use DependencyContainer for UI layer
          voiceService: voiceService,
          vadManager: dependencyContainer.vadManager,
          therapyService: dependencyContainer.therapy,
          interfaceVoiceService: dependencyContainer.voiceService,
          progressService: dependencyContainer.progress,
          navigationService: dependencyContainer.navigation,
          voicePipelineControllerFactory: pipelineFactory,
        );
      },
      child: _ChatScreenBody(
        sessionId: sessionId,
      ),
    );
  }
}

class _ChatScreenBody extends StatefulWidget {
  final String? sessionId;

  const _ChatScreenBody({
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

  // Debounce timer for metrics changes
  Timer? _metricsChangeTimer;

  // Wakelock management - simplified and safe
  Future<void> _enableWakelock() async {
    try {
      await NativeWakelockService.enable();

      // Sanity check - verify wakelock is actually enabled
      final enabled = await NativeWakelockService.isEnabled;
      AppLogger.d(
          'ChatScreen: Wakelock enabled successfully - KEEP_SCREEN_ON = $enabled');
    } catch (e) {
      AppLogger.w('ChatScreen: Failed to enable wakelock', e);
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
      AppLogger.d(
          'ChatScreen: Not in active session, skipping wakelock management');
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        // Re-enable wakelock when app comes back to foreground (engine is attached)
        AppLogger.d(
            'ChatScreen: App resumed, re-enabling wakelock for active session');
        _enableWakelock();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Keep wakelock active during therapy session - do NOT disable
        // Screen should stay on even when notification shade is pulled down,
        // proximity sensor triggers, or other brief interruptions occur
        AppLogger.d(
            'ChatScreen: App lifecycle changed to $state, keeping wakelock active for session');
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    // Debounce metrics changes to reduce spam
    _metricsChangeTimer?.cancel();
    _metricsChangeTimer = Timer(const Duration(milliseconds: 250), () {
      _handleMetricsChange();
    });
  }

  void _handleMetricsChange() {
    // Only re-apply wakelock if we're in an active therapy session
    final bloc = context.read<VoiceSessionBloc>();
    final sessionState = bloc.state;
    final isActiveSession = !sessionState.showMoodSelector &&
        !sessionState.showDurationSelector &&
        !sessionState.isInitializing &&
        sessionState.messages.isNotEmpty;

    if (isActiveSession) {
      // Called on rotation, PiP, split-screen, etc. - re-apply wakelock
      AppLogger.d(
          'ChatScreen: Metrics changed, re-enabling wakelock for active session');
      _enableWakelock();
    } else {
      AppLogger.d(
          'ChatScreen: Metrics changed, but not in active session - skipping wakelock');
    }
  }

  @override
  void initState() {
    super.initState();
    AppLogger.d('ChatScreen: initState called');
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
      AppLogger.d('ChatScreen: PostFrameCallback: calling _initSession');
      _initSession();
    });
  }

  @override
  void dispose() {
    AppLogger.d('ChatScreen: dispose called');

    // Disable wakelock immediately in dispose (fire and forget)
    NativeWakelockService.disable().then((_) {
      AppLogger.d('ChatScreen: Wakelock disabled successfully in dispose');
    }).catchError((e) {
      AppLogger.w('ChatScreen: Failed to disable wakelock in dispose', e);
    });

    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _sessionTimer?.cancel();
    _metricsChangeTimer?.cancel();
    _navigationService.showBottomNav();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.v('ChatScreen: build called');
    return MultiBlocListener(
      listeners: [
        BlocListener<VoiceSessionBloc, VoiceSessionState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            // Wakelock management based on session status
            _handleSessionStatusChange(state.status);
          },
        ),
        BlocListener<VoiceSessionBloc, VoiceSessionState>(
          listenWhen: (previous, current) =>
              !previous.autoEndTriggered && current.autoEndTriggered,
          listener: (context, state) {
            // Session duration reached zero - run the confirmed end-session flow
            unawaited(_endSession(autoTriggered: true));
          },
        ),
      ],
      child: BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
        builder: (context, state) {
          // Handle initialization state
          if (state.isInitializing) {
            return const Scaffold(
              appBar: ChatAppBar.simple(),
              body: Center(child: CircularProgressIndicator()),
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
                onEndSession: () => _endSession(),
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
      ),
    );
  }

  /// Handle session status changes for wakelock management
  void _handleSessionStatusChange(VoiceSessionStatus status) {
    // De-dupe wakelock toggles by short-circuiting when the target state is already applied
    switch (status) {
      case VoiceSessionStatus.voiceModeActive:
      case VoiceSessionStatus.textModeActive:
        // Session is active - acquire wakelock if not already enabled
        NativeWakelockService.isEnabled.then((enabled) {
          if (!enabled) {
            AppLogger.d('ChatScreen: Session active, enabling wakelock');
            _enableWakelock();
          }
        });
        break;
      case VoiceSessionStatus.ended:
      case VoiceSessionStatus.idle:
      case VoiceSessionStatus.initial:
        // Session is inactive - release wakelock if currently enabled
        NativeWakelockService.isEnabled.then((enabled) {
          if (enabled) {
            AppLogger.d('ChatScreen: Session inactive, disabling wakelock');
            NativeWakelockService.disable().then((_) {
              AppLogger.d(
                  'ChatScreen: Wakelock disabled due to session status change');
            }).catchError((e) {
              AppLogger.w('ChatScreen: Failed to disable wakelock', e);
            });
          }
        });
        break;
      default:
        // For other states (awaitingMood, selectingDuration, etc.) - no wakelock changes
        break;
    }
  }

  Future<bool> _handleBackPress(VoiceSessionState state) async {
    AppLogger.d('ChatScreen: onWillPop called');
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
    AppLogger.d('ChatScreen: _initializeServices called');

    try {
      // Initialize services through Bloc
      context.read<VoiceSessionBloc>().add(const InitializeService());

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
    // Set therapist style
    _therapistStyle = TherapistStyle.getById('cbt');

    // Initialize therapy service if needed
    await _therapyService.init();

    // Apply therapist style to therapy service
    _therapyService.setTherapistStyle(_therapistStyle!.systemPrompt);

    if (kDebugMode) {
      debugPrint('Loaded therapist style: ${_therapistStyle!.name}');
    }
  }

  void _initSession() {
    final bloc = context.read<VoiceSessionBloc>();

    if (widget.sessionId != null) {
      // Load existing session (legacy path - keep existing logic for now)
      _currentSessionId = widget.sessionId ?? '';
      bloc.add(const SetInitializing(true));
      bloc.add(const ShowMoodSelector(false));
      bloc.add(const ShowDurationSelector(false));

      // TODO: Implement proper existing session loading
      _startSessionTimer();
      bloc.add(const SetInitializing(false));
    } else {
      // Generate a temporary UUID for local session tracking
      _currentSessionId = const Uuid().v4();

      if (kDebugMode) {
        debugPrint(
            'Generated temporary session ID for local tracking: $_currentSessionId');
      }

      // For new sessions, ONLY request session start - no heavy initialization
      bloc.add(const StartSessionRequested());
    }
  }

  void _handleDurationSelection(int minutes) {
    final bloc = context.read<VoiceSessionBloc>();
    bloc.add(ChangeDuration(minutes));
    debugPrint('Duration selected: $minutes min');
  }

  void _handleMoodSelection(Mood selectedMood) {
    final bloc = context.read<VoiceSessionBloc>();
    final currentState = bloc.state;

    // Defensive validation: ensure duration was selected
    if (currentState.selectedDuration == null) {
      debugPrint('[ChatScreen] ERROR: Mood selected without duration!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a session duration first'),
          backgroundColor: Colors.red,
        ),
      );
      // Force back to duration selector
      bloc.add(const ShowDurationSelector(true));
      bloc.add(const ShowMoodSelector(false));
      return;
    }

    // Two-step session start: Use InitialMoodSelected to trigger actual session start
    bloc.add(InitialMoodSelected(selectedMood));

    debugPrint('Mood selected: $selectedMood, session is now active');

    // UI concerns remain in UI layer (as planned)
    setState(() {
      _initialMood = selectedMood;
    });

    // Hide bottom navigation bar during therapy session to prevent accidental navigation
    _navigationService.hideBottomNav();

    // Ensure speaker is unmuted for new session (in case previous session ended with mute)
    bloc.add(const SetSpeakerMuted(false));

    // Enable wakelock now that therapy session is starting
    _enableWakelock();

    // Start session timer (UI concern)
    _startSessionTimer();
  }

  void _startSessionTimer() {
    // Cancel any existing timer
    _sessionTimer?.cancel();

    // Start a new timer that updates every second
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        context.read<VoiceSessionBloc>().add(const UpdateSessionTimer());

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

  Future<void> _endSession({bool autoTriggered = false}) async {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;

    if (autoTriggered) {
      bloc.add(const ClearAutoEndTrigger());
    }

    // Prevent duplicate manual requests
    if (state.isEndingSession && !autoTriggered) {
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
        debugPrint(
            'Session not properly started, skipping session summary generation');
      }
      _navigationService.showBottomNav();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (!autoTriggered) {
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

      // If user cancels, exit early with NO state changes
      if (result != true || !mounted) return;
    } else if (!mounted) {
      return;
    }

    if (!state.isEndingSession) {
      bloc.add(const EndSessionRequested());
    }

    // Disable wakelock since session is ending (confirmed or auto-triggered)
    try {
      await NativeWakelockService.disable();
      debugPrint('[ChatScreen] Wakelock disabled successfully in _endSession');
    } catch (e) {
      debugPrint('[ChatScreen] Failed to disable wakelock in _endSession: $e');
    }

    // Stop local session timer updates
    _sessionTimer?.cancel();
    _sessionTimer = null;

    bloc.add(const SetEndingSession(true));
    bloc.add(const SetProcessing(true));

    _navigationService.showBottomNav();

    // Stop audio and clean up resources through the bloc - WAIT for completion
    bloc.add(const EndSession());

    // Give the EndSession event a brief moment to perform cleanup
    await Future.delayed(const Duration(milliseconds: 200));

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
      final sessionIdForNavigation =
          sessionData['id']?.toString() ?? _currentSessionId;

      context.pushReplacement(
        '/session_summary',
        extra: {
          'sessionId': sessionIdForNavigation,
          'summary': sessionData['summary'],
          'actionItems':
              sessionData['action_items'] ?? sessionData['actionItems'],
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

      bloc.add(const SetEndingSession(false));
      bloc.add(const SetProcessing(false));

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
    final sessionTitle =
        'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';

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
      'action_items':
          actionItemsDynamic.map((item) => item.toString()).toList(),
      'actionItems': actionItemsDynamic
          .map((item) => item.toString())
          .toList(), // Keep both for compatibility
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

      var actionItems = <String>[];
      final insights = (sessionData['insights'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList();

      if (kDebugMode) {
        debugPrint(
            'Saving session with ID: $sessionIdToUse (backend ID: $backendSessionId)');
      }

      // If we have a backend session ID, the session is already created on the backend
      // Just save to local database for offline access
      if (backendSessionId != null) {
        // Extract action items from session data
        final actionItemsDynamic =
            sessionData['action_items'] as List<dynamic>? ??
                sessionData['actionItems'] as List<dynamic>? ??
                [];
        actionItems =
            actionItemsDynamic.map((item) => item.toString()).toList();

        await sessionRepository.saveSession(
          sessionId: sessionIdToUse,
          title:
              'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
          summary: sessionData['summary'],
          actionItems: actionItems,
          messages: messages.map((m) => m.toJson()).toList(),
        );

        if (kDebugMode) {
          debugPrint(
              'Saved session $sessionIdToUse to local database with ${actionItems.length} action items');
          debugPrint('Action items saved: ${actionItems.join(", ")}');
        }

        // Update current session ID to the backend ID
        _currentSessionId = sessionIdToUse;
      } else {
        // Fallback: when backend doesn't return an ID we create the session ourselves
        final sessionTitle =
            'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';

        try {
          final createdSession = await sessionRepository.createSession(
            sessionTitle,
            id: _currentSessionId,
          );
          if (createdSession.id != _currentSessionId) {
            _currentSessionId = createdSession.id;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Failed to create backend session: $e');
          }
        }

        // Extract action items from session data for fallback case too
        final actionItemsDynamic =
            sessionData['action_items'] as List<dynamic>? ??
                sessionData['actionItems'] as List<dynamic>? ??
                [];
        actionItems =
            actionItemsDynamic.map((item) => item.toString()).toList();

        await sessionRepository.saveSession(
          sessionId: _currentSessionId,
          title: sessionTitle,
          summary: sessionData['summary'],
          actionItems: actionItems,
          messages: messages.map((m) => m.toJson()).toList(),
        );
      }

      if (FeatureFlags.isMemoryPersistenceEnabled) {
        await _syncSessionSummaryRemote(
          sessionIdToUse,
          sessionData,
          actionItems,
          insights,
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

  Future<void> _syncSessionSummaryRemote(
    String sessionId,
    Map<String, dynamic> sessionData,
    List<String> actionItems,
    List<String> insights,
  ) async {
    try {
      final apiClient = DependencyContainer().apiClientConcrete;
      final summaryPayload = {
        'session_id': sessionId,
        'summary_json': {
          'summary': sessionData['summary'],
          'action_items': actionItems,
          'insights': insights,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      await apiClient.post('/session_summaries:upsert', summaryPayload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to sync session summary to server: $e');
      }
    }
  }

  // Toggle between voice and text chat modes
  void _toggleChatMode() {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;

    debugPrint(
        '🔄 Switching from ${state.isVoiceMode ? "voice" : "chat"} to ${state.isVoiceMode ? "chat" : "voice"} mode');

    // Stop any ongoing audio before switching
    bloc.add(const StopAudio());

    setState(() {
      _messageController.clear();
    });

    // Toggle the mode in the bloc
    bloc.add(SwitchMode(!state.isVoiceMode));

    debugPrint('🔄 Mode switch complete');
  }
}
