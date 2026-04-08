library;
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/facades/session_voice_facade.dart';
import '../services/vad_manager.dart';
import '../services/enhanced_vad_manager.dart';
import '../services/session_scope_manager.dart';
import '../services/voice_session_coordinator.dart';
import '../services/auto_listening_coordinator.dart';
import '../services/audio_player_manager.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../widgets/mood_selector.dart'; // For Mood enum
import '../utils/amplitude_utils.dart';
import '../services/gemini_live_duplex_controller.dart';
import '../services/pipeline/voice_pipeline_controller.dart';
import '../services/pipeline/voice_pipeline_dependencies.dart';
import '../services/pipeline/audio_capture.dart';
import '../services/pipeline/audio_playback.dart';
import '../services/pipeline/ai_gateway.dart';
import '../services/pipeline/mic_auto_mode_controller.dart';
import 'managers/session_state_manager.dart';
import 'managers/timer_manager.dart';
import 'managers/message_coordinator.dart';
class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  final VoiceService voiceService;
  final SessionVoiceFacade voiceFacade;
  final VADManager vadManager;
  final ITherapyService? therapyService;
  final IVoiceService? interfaceVoiceService;
  final IProgressService? progressService;
  final INavigationService? navigationService;
  final VoicePipelineControllerFactory? _voicePipelineControllerFactory;
  VoicePipelineController? _voicePipelineController;
  bool get _pipelineControlsRecording =>
      _voicePipelineController?.supportsRecording == true;
  bool get _pipelineControlsPlayback =>
      _voicePipelineController?.supportsPlayback == true;
  StreamSubscription? _recordingStateSub;
  StreamSubscription? _audioPlaybackSub;
  StreamSubscription? _ttsStateSub;
  StreamSubscription? _amplitudeSub;
  StreamSubscription<VoicePipelineSnapshot>? _pipelineSnapshotSub;
  Completer<void>? _voiceModeSwitchCompleter;
  double _lastSmoothedAmplitude = 0.0;
  late final SessionStateManager _sessionManager;
  late final TimerManager _timerManager;
  late final MessageCoordinator _messageCoordinator;
  final SessionScopeManager _scopeManager = SessionScopeManager();
  void Function(String audioPath)? _autoRecordingCompleteHandler;
  late WidgetsBindingObserver _lifecycleObserver;
  int _modeGeneration = 0;
  bool _welcomeAutoModeArmed = false;
  int _micControlGuardDepth = 0;
  Completer<void>? _atomicResetCompleter;
  bool _deferAutoMode = false;
  bool _sessionStarted = false;
  final bool _usesGeminiLive;
  StreamSubscription<GeminiLiveEvent>? _geminiLiveSub;
  StringBuffer? _geminiResponseBuffer;
  bool get inSession => _scopeManager.inSession;
  @visibleForTesting
  int get debugModeGeneration => _modeGeneration;
  int get currentGeneration => _modeGeneration;
  bool _isSessionValid() {
    return inSession &&
        _sessionManager.state.status != VoiceSessionStatus.ended &&
        state.isVoiceMode; // CRITICAL: Must be in voice mode for TTS
  }
  bool get isTtsActive =>
      state.ttsStatus == TtsStatus.streaming ||
      state.ttsStatus == TtsStatus.playing;
  Stream<bool> get isTtsActiveStream => stream
      .map((state) =>
          state.ttsStatus == TtsStatus.streaming ||
          state.ttsStatus == TtsStatus.playing)
      .distinct();
  VoiceSessionBloc({
    required this.voiceFacade,
    required this.voiceService,
    required this.vadManager,
    this.therapyService,
    this.interfaceVoiceService, // Optional for backward compatibility
    this.progressService,
    this.navigationService,
    VoicePipelineControllerFactory? voicePipelineControllerFactory,
  })  : _usesGeminiLive = voiceService.geminiLiveEnabled,
        _voicePipelineControllerFactory = voicePipelineControllerFactory,
        super(VoiceSessionState.initial()) {
    assert(
      voiceFacade.voiceService == null ||
          identical(voiceFacade.voiceService, voiceService),
      'VoiceSessionBloc received mismatched VoiceService and facade instance',
    );
    _sessionManager = SessionStateManager();
    _timerManager = TimerManager();
    _messageCoordinator = MessageCoordinator();
    _timerManager.onTimeUpdate = _onTimerUpdate;
    _timerManager.onSessionExpired = _onSessionExpired;
    _timerManager.onTimeWarning = _onTimeWarning;
    on<StartSession>(_onStartSession);
    on<EndSession>(_onEndSession);
    on<StartListening>(_onStartListening);
    on<StopListening>(_onStopListening);
    on<SelectMood>(_onSelectMood);
    on<ChangeDuration>(_onChangeDuration);
    on<SessionStarted>(_onSessionStarted);
    on<MoodSelected>(_onMoodSelected);
    on<DurationSelected>(_onDurationSelected);
    on<TextMessageSent>(_onTextMessageSent);
    on<EndSessionRequested>(_onEndSessionRequested);
    on<SwitchMode>(_onSwitchMode);
    on<ProcessAudio>(_onProcessAudio);
    on<HandleError>(_onHandleError);
    on<ClearErrorEvent>(_onClearError);
    on<RetryLastActionEvent>(_onRetryLastAction);
    on<UpdateAmplitude>(_onUpdateAmplitude);
    on<AddMessage>(_onAddMessage);
    on<SetProcessing>(_onSetProcessing);
    on<SetRecordingState>(_onSetRecordingState);
    on<ProcessTextMessage>(_onProcessTextMessage);
    on<ShowMoodSelector>(_onShowMoodSelector);
    on<ShowDurationSelector>(_onShowDurationSelector);
    on<ToggleMicMute>(_onToggleMicMute);
    on<EnsureMicToggleEnabled>(_onEnsureMicToggleEnabled);
    on<SetSpeakerMuted>(_onSetSpeakerMuted);
    on<InitializeService>(_onInitializeService);
    on<StopAudio>(_onStopAudio);
    on<PlayAudio>(_onPlayAudio);
    on<AudioPlaybackStateChanged>(_onAudioPlaybackStateChanged);
    on<TtsStateChanged>(_onTtsStateChanged);
    on<PlayWelcomeMessage>(_onPlayWelcomeMessage);
    on<WelcomeMessageCompleted>(_onWelcomeMessageCompleted);
    on<SetInitializing>(_onSetInitializing);
    on<SetEndingSession>(_onSetEndingSession);
    on<UpdateSessionTimer>(_onUpdateSessionTimer);
    on<AutoEndTriggered>(_onAutoEndTriggered);
    on<ClearAutoEndTrigger>(_onClearAutoEndTrigger);
    on<StartSessionRequested>(_onStartSessionRequested);
    on<InitialMoodSelected>(_onInitialMoodSelected);
    on<GeminiLiveEventReceived>(_onGeminiLiveEventReceived);
    on<VoicePipelineSnapshotUpdated>(_onVoicePipelineSnapshotUpdated);
    if (interfaceVoiceService != null) {
      final ttsState$ = _safeVoiceService.isTtsActuallySpeaking
          .distinct() // Remove identical edges
          .shareReplay(maxSize: 1); // Hot, single subscription
      _ttsStateSub = ttsState$.listen((isSpeaking) {
        add(TtsStateChanged(isSpeaking));
        if (!isSpeaking && _deferAutoMode) {
          _deferAutoMode = false;
          unawaited(_enableAutoModeIfGenerationMatches(
              context: 'ControllerSnapshot'));
        }
      });
      final audioLevel$ = _safeVoiceService.audioLevelStream
          .scan<bool>((prev, curr, _) {
            const hi = 0.85, lo = 0.65; // Hysteresis thresholds
            return prev ? curr > lo : curr > hi;
          }, false)
          .distinct() // Remove identical states
          .shareReplay(maxSize: 1); // Single subscription
      _recordingStateSub = audioLevel$.listen((isRecording) {
        add(SetRecordingState(isRecording));
      });
      final playbackState$ = DependencyContainer()
          .ttsService
          .playbackStateStream
          .distinct()
          .shareReplay(maxSize: 1);
      _audioPlaybackSub = playbackState$.listen((isPlaying) {
        add(AudioPlaybackStateChanged(isPlaying));
      });
    } else {
      final recordingState$ = voiceService.recordingState
          .map((recState) => recState.toString().contains('recording'))
          .distinct()
          .shareReplay(maxSize: 1);
      _recordingStateSub = recordingState$.listen((isRecording) {
        add(SetRecordingState(isRecording));
      });
      final playbackState$ = voiceService
          .getAudioPlayerManager()
          .isPlayingStream
          .distinct()
          .shareReplay(maxSize: 1);
      _audioPlaybackSub = playbackState$.listen((isPlaying) {
        add(AudioPlaybackStateChanged(isPlaying));
      });
      final ttsState$ =
          voiceService.isTtsActuallySpeaking.distinct().shareReplay(maxSize: 1);
      _ttsStateSub = ttsState$.listen((isSpeaking) {
        add(TtsStateChanged(isSpeaking));
      });
    }
    _setupAmplitudeStream();
    _lifecycleObserver = _VoiceSessionLifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    voiceService.isVoiceModeCallback = () => state.isVoiceMode;
    voiceService.canStartListeningCallback = () =>
        state.isVoiceMode &&
        state.isInitialGreetingPlayed &&
        state.isMicEnabled && // CRITICAL: Include mic state to handle toggles during TTS
        !state.isVoiceModeSwitching;
    DependencyContainer().ttsService.setSessionValidityCallback(_isSessionValid);
    voiceService.isSessionValidCallback = _isSessionValid;
    if (_usesGeminiLive) {
      _geminiLiveSub = voiceService.geminiLiveEventStream
          .listen((event) => add(GeminiLiveEventReceived(event)));
    }
  }
  IVoiceService get _safeVoiceService {
    return interfaceVoiceService ?? voiceService as IVoiceService;
  }
  void _wireAutoListeningCallbacks() {
    // NOTE: Recording callback MUST be wired even when controller is authoritative.
    _autoRecordingCompleteHandler ??= (audioPath) {
      if (audioPath.isEmpty) {
        return;
      }
      if (isClosed) {
        return;
      }
      add(ProcessAudio(audioPath));
    };
    _safeVoiceService
        .setAutoListeningRecordingCallback(_autoRecordingCompleteHandler);
  }
  void _clearAutoListeningCallbacks() {
    if (_autoRecordingCompleteHandler != null) {
      _safeVoiceService.setAutoListeningRecordingCallback(null);
      _autoRecordingCompleteHandler = null;
    }
  }
  bool get _shouldAbortVoicePrep => isClosed || !state.isVoiceMode;
  void _guardMicControl({String reason = ''}) {
    if (isClosed) {
      return;
    }
    _micControlGuardDepth++;
    if (state.isMicControlGuarded) {
      return;
    }
    emit(state.copyWith(isMicControlGuarded: true));
  }
  void _releaseMicControlGuard({String reason = ''}) {
    if (_micControlGuardDepth > 0) {
      _micControlGuardDepth--;
    }
    if (isClosed) {
      return;
    }
    if (_micControlGuardDepth > 0) {
      return;
    }
    if (!state.isMicControlGuarded) {
      return;
    }
    emit(state.copyWith(isMicControlGuarded: false));
  }
  void _forceReleaseMicControlGuard({String reason = ''}) {
    _micControlGuardDepth = 0;
    if (isClosed || !state.isMicControlGuarded) {
      return;
    }
    emit(state.copyWith(isMicControlGuarded: false));
  }
  void _updateListeningState({
    required bool listening,
    String source = '',
  }) {
    final pipelineReady = listening && state.isInitialGreetingPlayed;
    final nextListening = listening;
    final nextAutoMode = listening;
    final nextPipelineReady = listening ? pipelineReady : false;
    if (state.isListening == nextListening &&
        state.isAutoListeningEnabled == nextAutoMode &&
        state.isVoicePipelineReady == nextPipelineReady) {
      return;
    }
    emit(state.copyWith(
      isListening: nextListening,
      isAutoListeningEnabled: nextAutoMode,
      isVoicePipelineReady: nextPipelineReady,
    ));
  }
  Future<void> _awaitVoiceFacadeStable() async {
    var attempts = 0;
    while (voiceFacade.isTransitioning && attempts < 40) {
      await Future.delayed(const Duration(milliseconds: 25));
      attempts++;
    }
    if (voiceFacade.isTransitioning && kDebugMode) {
      debugPrint(
          '[VoiceSessionBloc] voiceFacade transition still in progress after wait window');
    }
  }
  Future<void> _prepareForVoiceMode(AudioPlayerManager audioPlayerManager,
      Emitter<VoiceSessionState> emit) async {
    _guardMicControl(reason: 'Voice mode prep start');
    if (_voiceModeSwitchCompleter?.isCompleted == false) {
      await _voiceModeSwitchCompleter!.future;
    }
    final transitionCompleter = Completer<void>();
    _voiceModeSwitchCompleter = transitionCompleter;
    const settleDelay = Duration(milliseconds: 150);
    final bool aiSpeakingBeforeSwitch = state.isAiSpeaking;
    final bool ttsActiveBeforeSwitch = isTtsActive;
    final bool wasAiSpeaking = aiSpeakingBeforeSwitch || ttsActiveBeforeSwitch;
    final hadMessages = state.messages.isNotEmpty;
    final bool isInitialVoicePrep = !state.isInitialGreetingPlayed;
    final bool shouldTriggerListeningOnEnable = !isInitialVoicePrep;
    try {
      _atomicResetCompleter = Completer<void>();
      // CRITICAL: Always call startSession during voice mode preparation.
      await _awaitVoiceFacadeStable();
      await voiceFacade.startSession();
      audioPlayerManager.mute(false);
      if (isClosed) {
        return;
      }
      emit(state.copyWith(
        isVoiceMode: true,
        ttsAudible: true,
        isAiSpeaking: false,
        ttsStatus: TtsStatus.idle,
        isAutoListeningEnabled: false,
        isVoicePipelineReady: false,
        isVoiceModeSwitching: true,
      ));
      if (_shouldAbortVoicePrep) {
        return;
      }
      await audioPlayerManager.lightweightReset();
      await Future.sync(() => _safeVoiceService.resetTTSState());
      _wireAutoListeningCallbacks();
      if (!(_atomicResetCompleter?.isCompleted ?? true)) {
        _atomicResetCompleter?.complete();
      }
      if (_shouldAbortVoicePrep) {
        return;
      }
      if (settleDelay > Duration.zero) {
        await Future.delayed(settleDelay);
      }
      if (_shouldAbortVoicePrep) {
        return;
      }
      if (isInitialVoicePrep) {
        await _voicePipelineController?.requestEnableAutoMode();
        final shouldDeferAutoEnable = !state.isInitialGreetingPlayed ||
            isTtsActive ||
            audioPlayerManager.isPlaybackActive;
        if (shouldDeferAutoEnable) {
          _deferAutoMode = true;
        } else {
          _triggerListening();
        }
      } else {
        if (!_welcomeAutoModeArmed) {
          _welcomeAutoModeArmed = true;
        }
        try {
          await _voicePipelineController?.requestEnableAutoMode();
          if (shouldTriggerListeningOnEnable) {
            _triggerListening();
          }
        } catch (e) {
          emit(state.copyWith(errorMessage: e.toString()));
        }
      }
      if (_shouldAbortVoicePrep) {
        return;
      }
      bool pipelineReady = false;
      if (isInitialVoicePrep) {
        final autoState = _safeVoiceService.autoListeningState;
        pipelineReady = autoState == AutoListeningState.listening ||
            autoState == AutoListeningState.listeningForVoice;
      }
      if (_shouldAbortVoicePrep) {
        return;
      }
      emit(state.copyWith(
        isAutoListeningEnabled: true,
        isVoicePipelineReady: isInitialVoicePrep ? pipelineReady : true,
        ttsStatus: TtsStatus.idle,
        isVoiceModeSwitching: false,
      ));
      if (isInitialVoicePrep) {
        // CRITICAL FIX: Don't start listening if we deferred for welcome TTS
        if (_deferAutoMode) {
        } else if (!pipelineReady) {
          _triggerListening();
        } else if (hadMessages) {
          _triggerListening();
        }
      }
      if (wasAiSpeaking || isTtsActive) {
        _deferAutoMode = true;
      }
    } catch (e, stackTrace) {
      if (!_shouldAbortVoicePrep) {
        emit(state.copyWith(errorMessage: e.toString()));
      }
      rethrow;
    } finally {
      if (!(_atomicResetCompleter?.isCompleted ?? true)) {
        _atomicResetCompleter?.complete();
      }
      if (!transitionCompleter.isCompleted) {
        transitionCompleter.complete();
      }
      if (!isClosed && state.isVoiceModeSwitching) {
        emit(state.copyWith(isVoiceModeSwitching: false));
      }
      if (identical(_voiceModeSwitchCompleter, transitionCompleter)) {
        _voiceModeSwitchCompleter = null;
      }
      _releaseMicControlGuard(reason: 'Voice mode prep complete');
    }
  }
  bool get aiSpeakingForVAD => state.isAiSpeaking;
  bool get aiSpeakingForUI => state.isAiSpeaking && state.ttsAudible;
  Future<void> _enableAutoModeIfGenerationMatches({String context = ''}) async {
    if (!state.isVoiceMode ||
        state.isAutoListeningEnabled ||
        state.isRecording) {
      return;
    }
    await _voicePipelineController?.requestEnableAutoMode();
    emit(state.copyWith(isAutoListeningEnabled: true));
    _triggerListening();
  }
  void _triggerListening() {
    _voicePipelineController?.notifyListeningReady(context: 'blocTrigger');
  }
  void _onProcessingComplete() {}
  Future<void> _onStartSession(
      StartSession event, Emitter<VoiceSessionState> emit) async {
    if (inSession) {
      return;
    }
    _welcomeAutoModeArmed = false;
    try {
      final stopwatch = Stopwatch()..start();
      await _awaitVoiceFacadeStable();
      await voiceFacade.startSession();
      await _scopeManager.createSessionScope();
      final voiceCoordinator = _scopeManager.get<VoiceSessionCoordinator>();
      _wireAutoListeningCallbacks();
      final sessionAudioPlayer = _scopeManager.get<AudioPlayerManager>();
      final recordingManager = voiceService.getRecordingManager();
      AudioCapture? audioCapture;
      AudioPlayback? audioPlayback;
      AiGateway? aiGateway;
      MicAutoModeController? micController;
      final autoListeningSnapshot =
          _safeVoiceService.autoListeningSnapshotSource;
      if (_voicePipelineControllerFactory != null &&
          autoListeningSnapshot != null) {
        audioCapture = RecordingManagerAudioCapture(recordingManager);
        audioPlayback = AudioPlayerManagerPlayback(sessionAudioPlayer);
        aiGateway = VoiceCoordinatorAiGateway(voiceCoordinator);
        micController = VoiceServiceMicController(_safeVoiceService);
      }
      if (_voicePipelineControllerFactory != null &&
          autoListeningSnapshot != null) {
        _attachPipelineController(
          VoicePipelineDependencies(
            voiceService: voiceService,
            autoListening: autoListeningSnapshot,
            audioPlayerManager: sessionAudioPlayer,
            recordingManager: recordingManager,
            sessionCoordinator: voiceCoordinator,
            audioCapture: audioCapture,
            audioPlayback: audioPlayback,
            aiGateway: aiGateway,
            micController: micController,
          ),
        );
      } else if (_voicePipelineControllerFactory != null && kDebugMode) {
      }
      await voiceCoordinator.initialize();
      _safeVoiceService.setAutoListeningTtsActivityStream(isTtsActiveStream);
      final newState = _sessionManager.startNewSession();
      _messageCoordinator.resetMessages();
      _timerManager.stopTimer();
      if (state.selectedDuration != null) {
        _timerManager.setSessionDuration(state.selectedDuration!);
        _timerManager.startTimer();
        add(const UpdateSessionTimer());
      }
      if (_usesGeminiLive) {
        await voiceService.startGeminiLiveSession();
      }
      emit(newState);
      await _voicePipelineController?.startSession(
        VoiceSessionConfig(
          sessionId: newState.currentSessionId,
          targetDuration: newState.selectedDuration,
        ),
      );
    } catch (e) {
      await _awaitVoiceFacadeStable();
      await voiceFacade.endSession();
      await _cleanupFailedSession();
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
  Future<void> _onEndSession(
      EndSession event, Emitter<VoiceSessionState> emit) async {
    if (!inSession) {
      return;
    }
    try {
      if (_safeVoiceService.hasPendingOrActiveTts) {
        await DependencyContainer().ttsService.cancelAllStreams();
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await _safeVoiceService.stopAudio(); // Await playback completion
      _safeVoiceService.resetTTSState(); // Flush TTS monitor (sync operation)
      await _safeVoiceService.disableAutoMode(); // Disable auto listening
      await _safeVoiceService
          .tryStopRecording(); // Stop VAD/recording (idempotent)
      _clearAutoListeningCallbacks();
      await _scopeManager.destroySessionScope();
      await _awaitVoiceFacadeStable();
      await voiceFacade.endSession();
      await _voicePipelineController?.teardown();
      await _detachPipelineController();
      if (_usesGeminiLive) {
        await voiceService.stopGeminiLiveSession();
      }
      _sessionStarted = false;
      _welcomeAutoModeArmed = false;
    } catch (e) {
      await _forceSessionCleanup();
    }
    emit(state.copyWith(
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      isAiSpeaking: false,
    ));
    _timerManager.stopTimer();
    add(const UpdateSessionTimer());
  }
  void _onStartListening(
      StartListening event, Emitter<VoiceSessionState> emit) {
    _updateListeningState(
      listening: true,
      source: 'StartListeningEvent',
    );
  }
  void _onStopListening(StopListening event, Emitter<VoiceSessionState> emit) {
    _updateListeningState(
      listening: false,
      source: 'StopListeningEvent',
    );
  }
  void _onSelectMood(SelectMood event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(selectedMood: event.mood));
  }
  void _onChangeDuration(
      ChangeDuration event, Emitter<VoiceSessionState> emit) {
    _sessionManager.updateState(state);
    final updatedState =
        _sessionManager.selectDuration(Duration(minutes: event.minutes));
    emit(updatedState);
  }
  Future<void> _onSwitchMode(
      SwitchMode event, Emitter<VoiceSessionState> emit) async {
    if (++_modeGeneration == 0) {
      _modeGeneration = 1; // Skip 0, avoid wrap-around
    }
    _deferAutoMode = false;
    final audioPlayerManager = voiceService.getAudioPlayerManager();
    if (event.isVoiceMode) {
      try {
        await _prepareForVoiceMode(audioPlayerManager, emit);
      } catch (_) {}
    } else {
      if (_voiceModeSwitchCompleter?.isCompleted == false) {
        await _voiceModeSwitchCompleter!.future;
      }
      try {
        if (_safeVoiceService.hasPendingOrActiveTts) {
          await DependencyContainer().ttsService.cancelAllStreams();
        }
        await _safeVoiceService.stopAudio();
        audioPlayerManager.mute(true); // Backup safety
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          ttsAudible: false,
          isAiSpeaking: false,
          isVoicePipelineReady: true,
          isVoiceModeSwitching: false,
          isAutoListeningEnabled: false,
        ));
        _forceReleaseMicControlGuard(reason: 'Switched to chat mode');
        await _safeVoiceService.disableAutoMode();
        String? path = await _safeVoiceService.tryStopRecording();
        if (path != null && path.isNotEmpty) {
          add(ProcessAudio(path));
        } else {
          emit(state.copyWith(isProcessingAudio: false));
        }
        emit(state.copyWith(isAutoListeningEnabled: false, isRecording: false));
        await _awaitVoiceFacadeStable();
        await voiceFacade.endSession();
        _clearAutoListeningCallbacks();
      } catch (e) {
        emit(state.copyWith(errorMessage: e.toString()));
      }
    }
  }
  Future<void> _onProcessAudio(
      ProcessAudio event, Emitter<VoiceSessionState> emit) async {
    if (_usesGeminiLive) {
      _messageCoordinator.addUserMessage('[Voice message]');
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
        isProcessingAudio: true,
      ));
      return;
    }
    if (_sessionManager.state.status == VoiceSessionStatus.ended) {
      return;
    }
    emit(state.copyWith(isProcessingAudio: true));
    try {
      final transcription =
          await _safeVoiceService.processRecordedAudioFile(event.audioPath);
      if (transcription.trim().isEmpty || transcription.startsWith("Error:")) {
        emit(state.copyWith(
            isProcessingAudio: false,
            errorMessage: 'Could not understand audio'));
        return;
      }
      if (_sessionManager.state.status == VoiceSessionStatus.ended) {
        emit(state.copyWith(isProcessingAudio: false));
        return;
      }
      _messageCoordinator.addUserMessage(transcription);
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
      final history = _messageCoordinator.buildConversationHistory();
      if (state.isVoiceMode) {
        emit(
            state.copyWith(isAiSpeaking: true, ttsStatus: TtsStatus.preparing));
        final therapyServiceInstance =
            therapyService ?? DependencyContainer().therapy;
        assert(!isTtsActive,
            'Attempted to start TTS while another session is active (status: ${state.ttsStatus})');
        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          transcription,
          history,
          onTTSStart: (responseText) {
            _messageCoordinator.addAIMessage(responseText);
            emit(state.copyWith(
              ttsStatus: TtsStatus.streaming,
              messages: _messageCoordinator.messages,
              currentMessageSequence: _messageCoordinator.currentSequence,
            ));
          },
          onTTSPlaybackComplete: () async {
            emit(state.copyWith(
                isProcessingAudio: false,
                isAiSpeaking: false,
                ttsStatus: TtsStatus.idle));
            _onProcessingComplete();
          },
          onTTSError: (error) async {
            emit(state.copyWith(
                isProcessingAudio: false,
                errorMessage: error.toString(),
                isAiSpeaking: false,
                ttsStatus: TtsStatus.idle));
            _onProcessingComplete();
          },
        );
        final mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
        // Note: Maya's message is now added to MessageCoordinator in onTTSStart callback
      } else {
        final therapyServiceInstance =
            therapyService ?? DependencyContainer().therapy;
        final mayaResponseText =
            await therapyServiceInstance.processUserMessage(
          transcription,
          history: history,
        );
        if (mayaResponseText.trim().isEmpty) {
          emit(state.copyWith(
              isProcessingAudio: false,
              errorMessage: 'Failed to get response from Maya'));
          return;
        }
        _messageCoordinator.addAIMessage(mayaResponseText);
        emit(state.copyWith(
          messages: _messageCoordinator.messages,
          currentMessageSequence: _messageCoordinator.currentSequence,
          isProcessingAudio: false,
        ));
      }
    } catch (e) {
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }
  Future<void> _onGeminiLiveEventReceived(
      GeminiLiveEventReceived wrapper, Emitter<VoiceSessionState> emit) async {
    final event = wrapper.event;
    if (event is GeminiLiveReadyEvent) {
      emit(state.copyWith(
        geminiLiveSessionId: event.sessionId,
        status: VoiceSessionStatus.listening,
      ));
      return;
    }
    if (event is GeminiLiveTextEvent) {
      _geminiResponseBuffer ??= StringBuffer();
      _geminiResponseBuffer!.write(event.text);
      final partial = _geminiResponseBuffer!.toString();
      emit(state.copyWith(
        geminiLivePartialText: partial,
        isProcessingAudio: true,
        status: VoiceSessionStatus.processing,
      ));
      if (event.isFinal) {
        final finalText = partial.trim();
        _geminiResponseBuffer = null;
        if (finalText.isNotEmpty) {
          _messageCoordinator.addAIMessage(finalText);
          emit(state.copyWith(
            messages: _messageCoordinator.messages,
            currentMessageSequence: _messageCoordinator.currentSequence,
            geminiLivePartialText: null,
            isProcessingAudio: true,
          ));
        } else {
          emit(state.copyWith(
            geminiLivePartialText: null,
            isProcessingAudio: true,
          ));
        }
      }
      return;
    }
    if (event is GeminiLiveAudioStartedEvent) {
      emit(state.copyWith(
        ttsStatus: TtsStatus.streaming,
        isAiSpeaking: true,
        status: VoiceSessionStatus.speaking,
      ));
      return;
    }
    if (event is GeminiLiveAudioCompletedEvent) {
      emit(state.copyWith(
        ttsStatus: TtsStatus.idle,
        isAiSpeaking: false,
        status: VoiceSessionStatus.listening,
        isProcessingAudio: false,
      ));
      _onProcessingComplete();
      return;
    }
    if (event is GeminiLiveTurnCompleteEvent) {
      _geminiResponseBuffer = null;
      emit(state.copyWith(
        geminiLivePartialText: null,
        isProcessingAudio: false,
        status: VoiceSessionStatus.listening,
      ));
      return;
    }
    if (event is GeminiLiveErrorEvent) {
      _geminiResponseBuffer = null;
      emit(state.copyWith(
        errorMessage: event.message,
        hasError: true,
        geminiLivePartialText: null,
        status: VoiceSessionStatus.error,
      ));
      return;
    }
    if (event is GeminiLiveDisconnectedEvent) {
      _geminiResponseBuffer = null;
      emit(state.copyWith(
        geminiLiveSessionId: null,
        geminiLivePartialText: null,
        status: VoiceSessionStatus.idle,
      ));
    }
  }
  void _onHandleError(HandleError event, Emitter<VoiceSessionState> emit) {
    String userFriendlyMessage;
    final errorString = event.error.toString();
    if (errorString.startsWith('BackendSchemaException:')) {
      userFriendlyMessage =
          "Update required - please restart the app and try again. "
          "If this continues, contact support.";
    } else if (errorString.contains('Connection error:') ||
        errorString.contains('SocketException') ||
        errorString.contains('TimeoutException')) {
      userFriendlyMessage =
          "Connection issue. Please check your internet connection and try again.";
    } else if (errorString.contains('Authentication required') ||
        errorString.contains('401')) {
      userFriendlyMessage =
          "Session expired. Please restart the app to continue.";
    } else {
      userFriendlyMessage = "Something went wrong. Please try again.";
    }
    emit(state.copyWith(
      errorMessage: userFriendlyMessage,
      hasError: true,
    ));
  }
  void _onClearError(ClearErrorEvent event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(hasError: false, clearErrorMessage: true));
  }
  void _onRetryLastAction(RetryLastActionEvent event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(hasError: false, clearErrorMessage: true));
    final messages = state.messages;
    if (messages.isNotEmpty) {
      final lastUserMsg = messages.lastWhere(
        (m) => m.isUser,
        orElse: () => messages.last,
      );
      if (lastUserMsg.isUser) {
        add(ProcessTextMessage(lastUserMsg.content));
      }
    }
  }
  void _onUpdateAmplitude(
      UpdateAmplitude event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(amplitude: event.amplitude));
  }
  Future<void> _onAddMessage(
      AddMessage event, Emitter<VoiceSessionState> emit) async {
    try {
      _messageCoordinator.addMessage(event.message);
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
    } catch (e) {
      emit(state.copyWith(
          errorMessage: 'Failed to add message: $e', hasError: true));
    }
  }
  void _onSetProcessing(SetProcessing event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isProcessingAudio: event.isProcessing));
  }
  void _onSetRecordingState(
      SetRecordingState event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isRecording: event.isRecording));
  }
  Future<void> _onProcessTextMessage(
      ProcessTextMessage event, Emitter<VoiceSessionState> emit) async {
    if (_sessionManager.state.status == VoiceSessionStatus.ended) {
      return;
    }
    if (_usesGeminiLive) {
      _messageCoordinator.addUserMessage(event.text);
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
        isProcessingAudio: true,
      ));
      await voiceService.sendGeminiLiveText(event.text, turnComplete: true);
      return;
    }
    emit(state.copyWith(isProcessingAudio: true));
    try {
      _messageCoordinator.addUserMessage(event.text);
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
      final history = _messageCoordinator.buildConversationHistory();
      final therapyServiceInstance =
          therapyService ?? DependencyContainer().therapy;
      String mayaResponseText;
      if (state.isVoiceMode) {
        emit(
            state.copyWith(isAiSpeaking: true, ttsStatus: TtsStatus.preparing));
        assert(!isTtsActive,
            'Attempted to start TTS while another session is active (status: ${state.ttsStatus})');
        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          event.text,
          history,
          onTTSStart: (responseText) {
            _messageCoordinator.addAIMessage(responseText);
            emit(state.copyWith(
              ttsStatus: TtsStatus.streaming,
              messages: _messageCoordinator.messages,
              currentMessageSequence: _messageCoordinator.currentSequence,
            ));
          },
          onTTSPlaybackComplete: () async {
            emit(
                state.copyWith(isAiSpeaking: false, ttsStatus: TtsStatus.idle));
          },
          onTTSError: (error) {
            emit(state.copyWith(
                isAiSpeaking: false, errorMessage: error.toString()));
          },
        );
        mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
      } else {
        mayaResponseText = await therapyServiceInstance.processUserMessage(
          event.text,
          history: history,
        );
      }
      if (!state.isVoiceMode) {
        _messageCoordinator.addAIMessage(mayaResponseText);
      }
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        isProcessingAudio: false,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessingAudio: false,
        errorMessage: 'Failed to get response: ${e.toString()}',
        hasError: true,
      ));
      _messageCoordinator.addAIMessage(
          "I'm sorry, I'm having trouble responding right now. Please try again.");
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
    }
  }
  void _onShowMoodSelector(
      ShowMoodSelector event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setMoodSelectorVisibility(event.show);
    emit(newState);
  }
  void _onShowDurationSelector(
      ShowDurationSelector event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setDurationSelectorVisibility(event.show);
    emit(newState);
  }
  void _onToggleMicMute(ToggleMicMute event, Emitter<VoiceSessionState> emit) {
    if (state.isMicControlGuarded) {
      return;
    }
    final newMicEnabledState = !state.isMicEnabled;
    emit(state.copyWith(isMicEnabled: newMicEnabledState));
    _voicePipelineController?.updateExternalMicState(!newMicEnabledState);
    if (newMicEnabledState) {
      if (state.isVoiceMode && !state.isRecording) {
        unawaited(_enableAutoModeIfGenerationMatches(context: 'MicToggle'));
      } else {
        _deferAutoMode = true;
      }
    } else {
      _voicePipelineController?.requestDisableAutoMode();
    }
  }
  void _onEnsureMicToggleEnabled(
      EnsureMicToggleEnabled event, Emitter<VoiceSessionState> emit) {
    _forceReleaseMicControlGuard(reason: 'EnsureMicToggleEnabled event');
  }
  void _onSetSpeakerMuted(
      SetSpeakerMuted event, Emitter<VoiceSessionState> emit) {
    _safeVoiceService.setSpeakerMuted(event.isMuted);
    emit(state.copyWith(speakerMuted: event.isMuted));
  }
  Future<void> _onInitializeService(
      InitializeService event, Emitter<VoiceSessionState> emit) async {
    emit(state.copyWith(isProcessingAudio: true));
    try {
      await _safeVoiceService.initialize();
      final therapyServiceInstance =
          therapyService ?? DependencyContainer().therapy;
      await therapyServiceInstance.init();
      emit(state.copyWith(isProcessingAudio: false));
    } catch (e) {
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }
  Future<void> _onStopAudio(
      StopAudio event, Emitter<VoiceSessionState> emit) async {
    try {
      await _safeVoiceService.stopAudio();
      emit(state.copyWith(isAiSpeaking: false, ttsStatus: TtsStatus.idle));
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
  Future<void> _onPlayAudio(
      PlayAudio event, Emitter<VoiceSessionState> emit) async {
    try {
      await _safeVoiceService.playAudio(event.audioPath);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
  Future<void> _onPlayWelcomeMessage(
      PlayWelcomeMessage event, Emitter<VoiceSessionState> emit) async {
    if (state.isMicControlGuarded) {
      return;
    }
    _guardMicControl(reason: 'Welcome TTS');
    try {
      if (_atomicResetCompleter != null &&
          !_atomicResetCompleter!.isCompleted) {
        await _atomicResetCompleter!.future;
      }
      _safeVoiceService.updateTTSSpeakingState(true); // Stops auto-listening
      final ttsService = DependencyContainer().ttsService;
      await ttsService.speak(event.welcomeMessage, makeBackupFile: false);
      _safeVoiceService.updateTTSSpeakingState(false); // Starts auto-listening
      add(const WelcomeMessageCompleted());
    } catch (e) {
      _safeVoiceService.updateTTSSpeakingState(false); // Reset state on error
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      await Future.delayed(const Duration(milliseconds: 120));
      _releaseMicControlGuard(reason: 'Welcome TTS complete');
    }
  }
  void _onAudioPlaybackStateChanged(
      AudioPlaybackStateChanged event, Emitter<VoiceSessionState> emit) {
  }
  void _onTtsStateChanged(
      TtsStateChanged event, Emitter<VoiceSessionState> emit) {
    final bool wasSpeaking = state.isAiSpeaking;
    emit(state.copyWith(isAiSpeaking: event.isSpeaking));
    if (wasSpeaking &&
        !event.isSpeaking &&
        !state.isInitialGreetingPlayed &&
        state.isVoiceMode) {
      emit(state.copyWith(isInitialGreetingPlayed: true));
      _welcomeAutoModeArmed = true;
      unawaited(_enableAutoModeIfGenerationMatches(context: 'InitialGreeting'));
    }
    if (!event.isSpeaking && _deferAutoMode) {
      _deferAutoMode = false;
      unawaited(_enableAutoModeIfGenerationMatches(context: 'DeferredAuto'));
    }
    // CRITICAL FIX: When TTS finishes mid-session in voice mode with mic enabled,
    if (wasSpeaking &&
        !event.isSpeaking &&
        state.isInitialGreetingPlayed &&
        state.isVoiceMode &&
        state.isMicEnabled &&
        !state.isAutoListeningEnabled) {
      unawaited(_enableAutoModeIfGenerationMatches(context: 'TtsCompletionRestore'));
    }
  }
  void _onWelcomeMessageCompleted(
      WelcomeMessageCompleted event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setInitialGreetingPlayed();
    emit(newState);
    _welcomeAutoModeArmed = true;
    if (!isClosed) {
      unawaited(
          _enableAutoModeIfGenerationMatches(context: 'WelcomeCompletion'));
    }
  }
  void _onSetInitializing(
      SetInitializing event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setInitializing(event.isInitializing);
    emit(newState);
  }
  void _onSetEndingSession(
      SetEndingSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
        status: event.isEndingSession
            ? VoiceSessionStatus.ended
            : VoiceSessionStatus.idle));
  }
  void _onUpdateSessionTimer(
      UpdateSessionTimer event, Emitter<VoiceSessionState> emit) {
    final remaining = _timerManager.remainingSeconds;
    if (state.timerRemainingSeconds != remaining) {
      emit(state.copyWith(timerRemainingSeconds: remaining));
    }
  }
  // ========== Two-Step Session Start Flow ==========
  void _onStartSessionRequested(
      StartSessionRequested event, Emitter<VoiceSessionState> emit) {
    if (state.status == VoiceSessionStatus.idle ||
        state.status == VoiceSessionStatus.initial) {
      emit(state.copyWith(
        status: VoiceSessionStatus.awaitingMood,
        showDurationSelector: true,
        showMoodSelector: false,
      ));
    } else {
    }
  }
  void _onInitialMoodSelected(
      InitialMoodSelected event, Emitter<VoiceSessionState> emit) async {
    if (state.status != VoiceSessionStatus.awaitingMood) {
      return;
    }
    _guardMicControl(reason: 'Initial mood selection');
    try {
      await _beginSessionIfNeeded(event.mood, emit);
    } finally {
      _releaseMicControlGuard(reason: 'Initial mood selection complete');
    }
  }
  Future<void> _beginSessionIfNeeded(
      Mood mood, Emitter<VoiceSessionState> emit) async {
    if (_sessionStarted) {
      return;
    }
    if (state.selectedDuration == null) {
      emit(state.copyWith(
        errorMessage: 'Please select a session duration first',
        status: VoiceSessionStatus.awaitingMood,
        showDurationSelector: true,
        showMoodSelector: false,
      ));
      return;
    }
    _sessionStarted = true;
    add(const SwitchMode(true));
    try {
      await _startSessionWithMood(mood, emit);
    } catch (e) {
      _sessionStarted = false; // Reset flag on error
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
  Future<void> _startSessionWithMood(
      Mood mood, Emitter<VoiceSessionState> emit) async {
    try {
      final stopwatch = Stopwatch()..start();
      await _scopeManager.createSessionScope();
      final voiceCoordinator = _scopeManager.get<VoiceSessionCoordinator>();
      _wireAutoListeningCallbacks();
      await voiceCoordinator.initialize();
      _safeVoiceService.setAutoListeningTtsActivityStream(isTtsActiveStream);
      final newState = _sessionManager.selectMood(mood);
      try {
        await progressService?.logMood(mood);
      } catch (e) {}
      _messageCoordinator.resetMessages();
      final welcomeMessage = _messageCoordinator.addWelcomeMessage(mood);
      _timerManager.stopTimer();
      if (state.selectedDuration != null) {
        _timerManager.setSessionDuration(state.selectedDuration!);
        _timerManager.startTimer();
        add(const UpdateSessionTimer());
      }
      final finalState = newState.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
        status: VoiceSessionStatus.voiceModeActive, // SESSION IS NOW ACTIVE
      );
      _sessionManager.updateState(finalState);
      emit(finalState);
      if (finalState.isVoiceMode) {
        add(PlayWelcomeMessage(welcomeMessage.content));
      }
    } catch (e) {
      _sessionStarted = false; // Reset flag on error
      await _cleanupFailedSession();
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
  // ========== Phase 1A.3: New Event Handlers for Refactoring ==========
  void _onSessionStarted(
      SessionStarted event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setSessionStarted(event.sessionId);
    emit(newState);
  }
  void _onMoodSelected(MoodSelected event, Emitter<VoiceSessionState> emit) {
    var newState = _sessionManager.selectMood(event.mood);
    final welcomeMessage = _messageCoordinator.addWelcomeMessage(event.mood);
    newState = newState.copyWith(
      messages: _messageCoordinator.messages,
      currentMessageSequence: _messageCoordinator.currentSequence,
      status: VoiceSessionStatus.idle, // Session ready after welcome message
    );
    _sessionManager.updateState(newState);
    emit(newState);
    if (newState.isVoiceMode) {
      add(PlayWelcomeMessage(welcomeMessage.content));
    }
  }
  void _onDurationSelected(
      DurationSelected event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.selectDuration(event.duration);
    _timerManager.setSessionDuration(event.duration);
    emit(newState);
  }
  void _onTextMessageSent(
      TextMessageSent event, Emitter<VoiceSessionState> emit) {
    add(ProcessTextMessage(event.message));
  }
  void _onEndSessionRequested(
      EndSessionRequested event, Emitter<VoiceSessionState> emit) {
    final newState = _sessionManager.setSessionEnding();
    _timerManager.stopTimer();
    _sessionStarted = false;
    emit(newState);
    // Note: Wakelock, navigation, VAD stopping remain in UI layer for now
  }
  void _onAutoEndTriggered(
      AutoEndTriggered event, Emitter<VoiceSessionState> emit) {
    if (state.autoEndTriggered) {
      return; // Already flagged, avoid redundant emissions
    }
    final newState = state.copyWith(autoEndTriggered: true);
    _sessionManager.updateState(newState);
    emit(newState);
  }
  void _onClearAutoEndTrigger(
      ClearAutoEndTrigger event, Emitter<VoiceSessionState> emit) {
    if (!state.autoEndTriggered) {
      return; // Nothing to clear
    }
    final newState = state.copyWith(autoEndTriggered: false);
    _sessionManager.updateState(newState);
    emit(newState);
  }
  void _onTimerUpdate(int elapsedSeconds, int remainingSeconds) {
    add(const UpdateSessionTimer());
  }
  void _onSessionExpired() {
    add(const AutoEndTriggered());
    add(const EndSessionRequested());
  }
  void _onTimeWarning() {
  }
  Future<void> _cleanupFailedSession() async {
    _welcomeAutoModeArmed = false;
    _clearAutoListeningCallbacks();
    await _scopeManager.destroySessionScope();
  }
  Future<void> _forceSessionCleanup() async {
    _welcomeAutoModeArmed = false;
    _clearAutoListeningCallbacks();
    await _scopeManager.destroySessionScope();
    await _awaitVoiceFacadeStable();
    await voiceFacade.endSession();
  }
  void _onAppLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        if (this.state.isVoiceMode) {
          try {
            final audioPlayerManager = voiceService.getAudioPlayerManager();
            audioPlayerManager.mute(true);
          } catch (e) {}
        }
        break;
      case AppLifecycleState.resumed:
        if (this.state.isVoiceMode && this.state.ttsAudible) {
          try {
            final audioPlayerManager = voiceService.getAudioPlayerManager();
            audioPlayerManager.mute(false);
          } catch (e) {
            try {
              final audioPlayerManager = voiceService.getAudioPlayerManager();
              audioPlayerManager.mute(true);
              Future.delayed(const Duration(milliseconds: 100), () {
                audioPlayerManager.mute(false);
              });
            } catch (fallbackError) {}
          }
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
  void _setupAmplitudeStream() {
    try {
      Stream<double> amplitudeStream;
      if (AutoListeningCoordinator.isEnhancedVADEnabled) {
        final enhancedVAD = _safeVoiceService.autoListeningVadManager;
        if (enhancedVAD is EnhancedVADManager) {
          amplitudeStream = enhancedVAD.amplitudeStream;
        } else {
          amplitudeStream = vadManager.amplitudeStream;
        }
      } else {
        amplitudeStream = vadManager.amplitudeStream;
      }
      final processedAmplitudeStream = amplitudeStream
          .map((dbValue) =>
              AmplitudeUtils.dbToLinear(dbValue)) // Convert dB to linear
          .map((linearValue) {
            _lastSmoothedAmplitude = AmplitudeUtils.applySmoothing(
                linearValue, _lastSmoothedAmplitude);
            return _lastSmoothedAmplitude;
          })
          .throttleTime(const Duration(milliseconds: 33)) // 30fps throttling
          .distinct((prev, curr) =>
              (prev - curr).abs() < 0.02); // Reduce micro-changes
      _amplitudeSub = processedAmplitudeStream.listen((amplitude) {
        if (state.isVoiceMode &&
            (state.isListeningForVoice || state.isRecording)) {
          add(UpdateAmplitude(amplitude));
        }
      });
    } catch (e) {}
  }
  void _attachPipelineController(VoicePipelineDependencies dependencies) {
    if (_voicePipelineControllerFactory == null) {
      return;
    }
    _pipelineSnapshotSub?.cancel();
    _voicePipelineController?.disposeAsync();
    final controller = _voicePipelineControllerFactory!(
      dependencies: dependencies,
      micMutedGetter: () => !state.isMicEnabled,
    );
    _voicePipelineController = controller;
    controller.setRecordingCompleteCallback((path) {
      if (!isClosed) {
        add(ProcessAudio(path));
      }
    });
    voiceService.attachPipelineController(controller);
    _pipelineSnapshotSub = controller.snapshots.listen((snapshot) {
      add(VoicePipelineSnapshotUpdated(snapshot));
    });
  }
  Future<void> _detachPipelineController() async {
    await _pipelineSnapshotSub?.cancel();
    _pipelineSnapshotSub = null;
    await _voicePipelineController?.disposeAsync();
    voiceService.attachPipelineController(null);
    _voicePipelineController = null;
  }
  Future<void> _onVoicePipelineSnapshotUpdated(
      VoicePipelineSnapshotUpdated event,
      Emitter<VoiceSessionState> emit) async {
    final snapshot = event.snapshot;
    final listeningExpected = snapshot.phase == VoicePipelinePhase.listening;
    final recordingExpected = snapshot.phase == VoicePipelinePhase.recording;
    final speakingExpected =
        snapshot.phase == VoicePipelinePhase.speaking || snapshot.isTtsActive;
    final bool phaseListening = snapshot.phase == VoicePipelinePhase.listening;
    final bool phaseRecording = snapshot.phase == VoicePipelinePhase.recording;
    final bool phaseSpeaking =
        snapshot.phase == VoicePipelinePhase.speaking || snapshot.isTtsActive;
    emit(state.copyWith(
      pipelinePhase: snapshot.phase,
      pipelineMicMuted: snapshot.micMuted,
      pipelineAutoModeEnabled: snapshot.autoModeEnabled,
      isAutoListeningEnabled: snapshot.autoModeEnabled,
      isListening: phaseListening,
      isRecording: _pipelineControlsRecording ? phaseRecording : null,
      isAiSpeaking: _pipelineControlsPlayback ? phaseSpeaking : null,
    ));
  }
  @override
  Future<void> close() async {
    if (inSession) {
      await _forceSessionCleanup();
    }
    await _awaitVoiceFacadeStable();
    await voiceFacade.endSession();
    _recordingStateSub?.cancel();
    _audioPlaybackSub?.cancel();
    _ttsStateSub?.cancel();
    _amplitudeSub?.cancel();
    await _detachPipelineController();
    await _geminiLiveSub?.cancel();
    _geminiLiveSub = null;
    if (_usesGeminiLive) {
      await voiceService.stopGeminiLiveSession();
    }
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _timerManager.dispose();
    return super.close();
  }
}
class _VoiceSessionLifecycleObserver with WidgetsBindingObserver {
  final VoiceSessionBloc _bloc;
  _VoiceSessionLifecycleObserver(this._bloc);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _bloc._onAppLifecycleStateChanged(state);
  }
}
