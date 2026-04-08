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
        if (dependencyContainer
                .isRegistered<VoicePipelineControllerFactory>()) {
          pipelineFactory =
              dependencyContainer.get<VoicePipelineControllerFactory>();
        }
        return VoiceSessionBloc(
          voiceFacade: sessionFacade,
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
  String _currentSessionId = '';
  Mood? _initialMood;
  TherapistStyle? _therapistStyle;
  late VoiceService _voiceService;
  late final ITherapyService _therapyService;
  late final IProgressService _progressService;
  late final INavigationService _navigationService;
  Timer? _sessionTimer;
  Timer? _metricsChangeTimer;
  Future<void> _enableWakelock() async {
    try {
      await NativeWakelockService.enable();
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
        AppLogger.d(
            'ChatScreen: App resumed, re-enabling wakelock for active session');
        _enableWakelock();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        AppLogger.d(
            'ChatScreen: App lifecycle changed to $state, keeping wakelock active for session');
        break;
    }
  }
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _metricsChangeTimer?.cancel();
    _metricsChangeTimer = Timer(const Duration(milliseconds: 250), () {
      _handleMetricsChange();
    });
  }
  void _handleMetricsChange() {
    final bloc = context.read<VoiceSessionBloc>();
    final sessionState = bloc.state;
    final isActiveSession = !sessionState.showMoodSelector &&
        !sessionState.showDurationSelector &&
        !sessionState.isInitializing &&
        sessionState.messages.isNotEmpty;
    if (isActiveSession) {
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
    _therapyService = DependencyContainer().therapy;
    _progressService = DependencyContainer().progress;
    _navigationService = DependencyContainer().navigation;
    _voiceService = DependencyContainer().get<VoiceService>();
    _initializeServices();
    _loadTherapistStyle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.d('ChatScreen: PostFrameCallback: calling _initSession');
      _initSession();
    });
  }
  @override
  void dispose() {
    AppLogger.d('ChatScreen: dispose called');
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
            _handleSessionStatusChange(state.status);
          },
        ),
        BlocListener<VoiceSessionBloc, VoiceSessionState>(
          listenWhen: (previous, current) =>
              !previous.autoEndTriggered && current.autoEndTriggered,
          listener: (context, state) {
            unawaited(_endSession(autoTriggered: true));
          },
        ),
      ],
      child: BlocBuilder<VoiceSessionBloc, VoiceSessionState>(
        builder: (context, state) {
          if (state.isInitializing) {
            return const Scaffold(
              appBar: ChatAppBar.simple(),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.showDurationSelector) {
            return Scaffold(
              appBar: const ChatAppBar.simple(),
              body: DurationSelector(
                selectedDuration: state.sessionDurationMinutes,
                onDurationSelected: _handleDurationSelection,
              ),
            );
          }
          if (state.showMoodSelector) {
            return Scaffold(
              appBar: const ChatAppBar.simple(),
              body: MoodSelectorScreen(
                selectedMood: _initialMood,
                onMoodSelected: _handleMoodSelection,
              ),
            );
          }
          return PopScope(
            canPop: true,
            onPopInvoked: (didPop) async {
              if (!didPop) return;
              final shouldPop = await _handleBackPress(state);
              if (!shouldPop && mounted) {
              }
            },
            child: Scaffold(
              appBar: ChatAppBar(
                therapistStyle: _therapistStyle,
                onEndSession: () => _endSession(),
              ),
              body: Column(
                children: [
                  if (state.hasError)
                    MaterialBanner(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      content: Text(
                        state.errorMessage ?? 'Something went wrong. Please try again.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      leading: Icon(
                        Icons.cloud_off,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      actions: [
                        TextButton(
                          onPressed: () {
                            context.read<VoiceSessionBloc>().add(
                              const ClearErrorEvent(),
                            );
                          },
                          child: const Text('DISMISS'),
                        ),
                        TextButton(
                          onPressed: () {
                            context.read<VoiceSessionBloc>().add(
                              const RetryLastActionEvent(),
                            );
                          },
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: ChatInterfaceView(
                      onSwitchMode: _toggleChatMode,
                      onSendMessage: _sendMessage,
                      messageController: _messageController,
                      scrollController: _scrollController,
                    ),
                  ),
                ],
              ),
              endDrawer: kDebugMode ? const DebugDrawer() : null,
            ),
          );
        },
      ),
    );
  }
  void _handleSessionStatusChange(VoiceSessionStatus status) {
    switch (status) {
      case VoiceSessionStatus.voiceModeActive:
      case VoiceSessionStatus.textModeActive:
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
      context.read<VoiceSessionBloc>().add(const InitializeService());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize services: $e')),
        );
      }
    }
  }
  Future<void> _loadTherapistStyle() async {
    _therapistStyle = TherapistStyle.getById('cbt');
    await _therapyService.init();
    _therapyService.setTherapistStyle(_therapistStyle!.systemPrompt);
  }
  void _initSession() {
    final bloc = context.read<VoiceSessionBloc>();
    if (widget.sessionId != null) {
      _currentSessionId = widget.sessionId ?? '';
      bloc.add(const SetInitializing(true));
      bloc.add(const ShowMoodSelector(false));
      bloc.add(const ShowDurationSelector(false));
      // TODO: Implement proper existing session loading
      _startSessionTimer();
      bloc.add(const SetInitializing(false));
    } else {
      _currentSessionId = const Uuid().v4();
      bloc.add(const StartSessionRequested());
    }
  }
  void _handleDurationSelection(int minutes) {
    final bloc = context.read<VoiceSessionBloc>();
    bloc.add(ChangeDuration(minutes));
  }
  void _handleMoodSelection(Mood selectedMood) {
    final bloc = context.read<VoiceSessionBloc>();
    final currentState = bloc.state;
    if (currentState.selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a session duration first'),
          backgroundColor: Colors.red,
        ),
      );
      bloc.add(const ShowDurationSelector(true));
      bloc.add(const ShowMoodSelector(false));
      return;
    }
    bloc.add(InitialMoodSelected(selectedMood));
    setState(() {
      _initialMood = selectedMood;
    });
    _navigationService.hideBottomNav();
    bloc.add(const SetSpeakerMuted(false));
    _enableWakelock();
    _startSessionTimer();
  }
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        context.read<VoiceSessionBloc>().add(const UpdateSessionTimer());
      }
    });
  }
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    context.read<VoiceSessionBloc>().add(TextMessageSent(text));
    _messageController.clear();
  }
  Future<void> _endSession({bool autoTriggered = false}) async {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;
    if (autoTriggered) {
      bloc.add(const ClearAutoEndTrigger());
    }
    if (state.isEndingSession && !autoTriggered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session ending in progress...')),
      );
      return;
    }
    if (state.messages.isEmpty ||
        state.showDurationSelector ||
        state.showMoodSelector) {
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
      if (result != true || !mounted) return;
    } else if (!mounted) {
      return;
    }
    if (!state.isEndingSession) {
      bloc.add(const EndSessionRequested());
    }
    try {
      await NativeWakelockService.disable();
    } catch (e) {}
    _sessionTimer?.cancel();
    _sessionTimer = null;
    bloc.add(const SetEndingSession(true));
    bloc.add(const SetProcessing(true));
    _navigationService.showBottomNav();
    bloc.add(const EndSession());
    await Future.delayed(const Duration(milliseconds: 200));
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
      final sessionData = await _generateSessionSummary(state.messages);
      await _saveSession(sessionData, state.messages);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
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
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      bloc.add(const SetEndingSession(false));
      bloc.add(const SetProcessing(false));
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
    if (_initialMood != null) {
      await _progressService.logMood(_initialMood!);
    }
    final messageList = messages.map((m) => m.toJson()).toList();
    final sessionTitle =
        'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';
    final sessionData = await _therapyService.endSessionWithMessages(
      messageList,
      sessionTitle: sessionTitle,
      userId: 1, // Default user ID for now
    );
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
      final userContextService = DependencyContainer().userContextService;
      final userId = userContextService.getSignedInUserId(operation: 'ChatScreen._saveSession');
      if (userId == null) {
        throw Exception('Cannot save session: User not authenticated');
      }
      final sessionRepository = DependencyContainer().sessionRepository;
      final backendSessionId = sessionData['id']?.toString();
      final sessionIdToUse = backendSessionId ?? _currentSessionId;
      var actionItems = <String>[];
      final insights = (sessionData['insights'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList();
      if (backendSessionId != null) {
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
        _currentSessionId = sessionIdToUse;
      } else {
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
        } catch (e) {}
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save session: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
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
    } catch (e) {}
  }
  void _toggleChatMode() {
    final bloc = context.read<VoiceSessionBloc>();
    final state = bloc.state;
    bloc.add(const StopAudio());
    setState(() {
      _messageController.clear();
    });
    bloc.add(SwitchMode(!state.isVoiceMode));
  }
}
