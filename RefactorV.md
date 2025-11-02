# Voice/Chat Pipeline Isolation Refactor

## Goal
Decouple chat-only flows from the voice pipeline so TTS callbacks, AutoListeningCoordinator, and recording state are wired only when voice mode is active. This eliminates cross-mode race conditions without altering shared LLM/message services. Keep the existing mutex/lock work, but only after the lifecycle split prevents chat from receiving voice callbacks.

## 1. Audit Existing Wiring
- Inspect `lib/di/service_locator.dart` for registrations of:
  - `VoiceService`
  - `SimpleTTSService`
  - `AutoListeningCoordinator`
  - `VoiceSessionBloc`
- Trace every call path that triggers `VoiceService.initialize` / `initializeOnlyIfNeeded`.
  ```dart
  final voiceService = GetIt.I<VoiceService>();
  await voiceService.initializeOnlyIfNeeded();
  ```
- Log duplicate init cases to understand why we see repeated
  “Voice service initialized successfully”.

## 2. Introduce Mode Facades & Scoped Services
- Create two façade classes in `lib/services/facades/`:
  - `ChatVoiceFacade` (text only, no auto listening, never touches `VoiceService`).
  - `VoiceModeFacade` (live TTS + VAD, owns the lifecycle of `VoiceService` + `AutoListeningCoordinator`).
- Both implement a shared contract (subset of `IVoiceService`). Example skeleton:
  ```dart
  abstract class SessionVoiceFacade {
    Future<void> sendText(String text);
    Future<void> startSession();
    Future<void> endSession();
  }
  ```
- `VoiceModeFacade.startSession()` lazily creates (or reuses) `VoiceService`, initializes `AutoListeningCoordinator`, and registers TTS/VAD callbacks. `endSession()` tears them down.
- `ChatVoiceFacade.startSession()` is a no-op for voice services; it just exposes text responses via `TherapyService`.

## 3. Adjust DI Registrations
- Register `VoiceModeFacade` as a factory scoped to voice sessions (not app-wide):
  ```dart
  sl.registerFactory<VoiceModeFacade>(() => VoiceModeFacade(
    voiceService: sl<VoiceService>(),
    ttsService: sl<SimpleTTSService>(),
  ));
  ```
- Register `ChatVoiceFacade` separately; ensure chat flows never request `VoiceService` directly.
- Change bloc constructors to request the appropriate façade instead of the raw service.

## 4. Mode-Scoped AutoListeningCoordinator & TTS Callbacks
- Instantiate the coordinator inside `VoiceModeFacade.startSession()`:
  ```dart
  Future<void> startSession() async {
    await voiceService.initializeOnlyIfNeeded();
    await voiceService.autoListeningCoordinator.initialize();
    _subs = [voiceService.isTtsActuallySpeaking.listen(_handleTts)];
    ttsService.setOnSpeakingState(voiceService.updateTTSSpeakingState);
  }
  ```
- On `endSession`, stop playback, disable auto mode, unsubscribe TTS callbacks, and dispose the coordinator **in reverse order of setup**:
  ```dart
  Future<void> endSession() async {
    await ttsService.stopPlayback();
    await voiceService.autoListeningCoordinator.stopListening();
    ttsService.setOnSpeakingState(null);
    _subs?.cancel();
    await voiceService.dispose();
  }
  ```
- Guard late callbacks by comparing session tokens:
  ```dart
  if (sessionGeneration != _activeGeneration) return;
  ```
- Remove app-start auto-enable calls (`VoiceService` should **not** force auto mode anymore).
- In chat mode, never register the TTS callback (and log if someone tries to call it).

## 5. Chat-Safe TTS
- Provide a chat-specific helper that invokes `TherapyService.processUserMessage`, then returns text without touching `updateTTSSpeakingState`.
- Add assertions/logging if the chat façade attempts to call methods that require the voice façade (e.g., starting recordings).
- Confirm via tests that chat responses never trigger the voice callback logs.
- Add a debug guard in `VoiceService` to detect chat access:
  ```dart
  void assertVoiceModeActive() {
    assert(isVoiceModeCallback?.call() ?? true,
        'VoiceService accessed while not in voice mode');
  }
  ```

## 6. Prevent Double Initialization
- Wrap `VoiceService` registration with an `isRegistered` check; only instantiate when entering voice mode.
- Reduce `initialize()` usage to the voice façade; chat façade must never touch it.
- Add a guard inside `VoiceService.initialize`:
  ```dart
  if (_isInitialized) {
    debugPrint('[VoiceService] initialize skipped (already initialized)');
    return;
  }
  ```

## 7. Mode Transition Workflow
- Chat → Voice:
  1. Resolve `VoiceModeFacade` (creates `VoiceService` if needed).
  2. Call `startSession()` (initializes coordinator, registers callbacks, resets state).
  3. Switch UI to voice controls.
- Voice → Chat:
  1. Call `endSession()` (stop playback, disable auto mode, dispose coordinator, unregister callbacks).
  2. Drop references so future TTS events can’t reach chat listeners.
  3. Switch UI to chat controls.

## 8. Regression Safeguards
- Maintain existing public APIs by keeping façade method signatures aligned with current bloc calls.
- Add unit/integration tests covering:
  - Chat mode TTS completions do **not** trigger `startListening()`.
  - Voice mode toggles repeatedly without double-init logs.
  - End session cleans up coordinator (auto mode disabled + no lingering listeners).
  - After transition, `voiceService.canStartListeningCallback` is null/guarded in chat mode.
- Ensure `VoiceSessionBloc` unsubscribes from TTS/recording streams and resets flags on `close()`, and avoid double-invoking `endSession()` via both UI and bloc disposal.
- Update UI so `TextInputBar` disables (not hides) the mic button whenever `isTtsActive || isRecording`.

## 9. Rollout Strategy
- Hide changes behind a feature flag (`voice_facade_enabled`).
  ```dart
  if (config.voiceFacadeEnabled) {
    sl.registerFactory<SessionVoiceController>(() => VoiceModeFacade(...));
  } else {
    sl.registerFactory<SessionVoiceController>(() => LegacyVoiceController(...));
  }
  ```
- Ship to QA with both modes available for comparison; validate rapid chat↔voice switches, long TTS streams, and error recovery.
- Watch new assertion logs (`VoiceService accessed while not in voice mode`, `isTransitioning` guard) to catch rogue call sites early.
- Once validated, remove legacy path and flag, update documentation (`VoicToggle.md`, `RaceFix.md`).

## 10. Monitoring & Verification
- Add debug prints around façade creation/destruction, AutoListeningCoordinator init/dispose, and TTS callback registration/unregistration.
- During QA, capture logs to ensure chat flows no longer trigger voice listeners.
- After release, monitor crash/analytics dashboards for audio-related anomalies.
- Once lifecycle isolation is verified, keep the existing playback mutex to guard against internal overlaps in voice mode.
- Maintain internal mutex/state locks within both `VoiceService` and `AutoListeningCoordinator` to serialize mic start/stop alongside RNNoise/native callbacks.
- Roll the feature out incrementally (feature flag on staging first, then controlled ramp) so we can quickly rollback if analytics show regressions.
- Keep alerting or dashboards focused on TTS latency and session crashes for the first release; if metrics stay flat, remove the flag in the follow-up release.

## 11. Shared-State Transition Contract
- Define an explicit contract for how in-flight LLM/streaming work is handled during mode switches.
  - Introduce an `isTransitioning` flag on the session controller; new chat/voice requests must check this and queue or reject while a mode switch is in progress.
  - Ensure the bloc sets `isTransitioning = true` before calling `startSession()`/`endSession()` and clears it only after teardown/startup completes.
- Capture the contract in documentation (e.g., “voice hand-off waits for current LLM response to finish, chat requests are paused until `isTransitioning` is false”).
- Use generation/session tokens in voice services to ignore callbacks from prior sessions once a transition begins.

### Defensive Session Start/Stop
- Wrap `startSession()` and `endSession()` in try/catch blocks that roll back partial state:
  ```dart
  Future<void> startSession() async {
    isTransitioning = true;
    try {
      await voiceService.initializeOnlyIfNeeded();
      await autoListeningCoordinator.initialize();
      // additional init...
    } catch (error, stack) {
      await _rollbackVoiceInit();
      rethrow;
    } finally {
      isTransitioning = false;
    }
  }

  Future<void> endSession() async {
    isTransitioning = true;
    try {
      await ttsService.stopPlayback();
      await autoListeningCoordinator.stopListening();
      // additional teardown...
    } catch (error, stack) {
      await _rollbackVoiceTeardown();
      rethrow;
    } finally {
      isTransitioning = false;
    }
  }
  ```
- The rollback helpers should catch any partially initialized components (coordinator, subscriptions, service instances) and dispose them safely.

## Final Fix
- Add an `AudioPlayerManager.playbackActive` stream (true while ExoPlayer is actually playing, false once it returns to `ProcessingState.completed/idle`) so higher-level services can observe real playback state instead of inferring from queued TTS events.
- Replace eager `enableAutoMode()` calls with a deferred helper (for example, `enableAutoModeWhenPlaybackCompletes`) that waits for both `_ttsActive == false` *and* `playbackActive == false` before rearming the mic, skipping re-enable if the session or mode has changed in the meantime.
- Gate AutoListeningCoordinator restarts on a “first frame rendered” signal from ExoPlayer (via `AudioPlayerManager` callbacks or a dedicated stream) so listening only resumes after playback has genuinely begun and then completed.

## VAD Race Guard Plan
1. **Introduce VAD Transition Lock**  
   - Add a `Completer<void>? _vadTransitionLock` inside `AutoListeningCoordinator`.  
   - Wrap `_startListening()` and `_stopListeningAndRecording()` so each checks for an in-flight lock, awaits it, assigns a new completer, performs work, then completes the lock inside a `finally`.  
   - Ensure all entry points (`enableAutoMode`, `_triggerListening`, unified-TTS callbacks) go through these guarded methods.
2. **Atomic Auto-Mode Setter**  
   - Replace direct `_autoModeEnabled = ...` writes with a private `void _setAutoModeEnabled(bool value)` that no-ops if unchanged, logs the transition, updates the stream controller, and only ever flips the flag on the main isolate.  
   - Update `enableAutoMode()*` and `disableAutoMode()` paths to call the setter instead of mutating the field in multiple places.
3. **VAD Generation Guard**  
   - Maintain an `int _vadGeneration` that increments inside `_startListening()` before any async awaits.  
   - Timers/callbacks (speech end timers, retry timers, `_startSpeechEndTimer`) capture the generation value and re-check `if (gen != _vadGeneration)` before mutating state.  
   - Cancel stale timers and reset the generation when auto mode is disabled or voice mode tears down.
4. **Cleanup & Delay Safety Nets**  
   - Add `cancelAllTimers()` helper invoked before each `_startListening()` to clear `_speechEndDebounceTimer`, `_pendingSpeechEndTimer`, `_stuckStateTimer`.  
   - After `_stopRecording()` returns, `await Future.delayed(const Duration(milliseconds: 100))` so Android’s `AudioRecord` can release native buffers before `_startListening()` is allowed to continue.  
   - Integrate this delay into the transition lock so rapid stop→start loops respect it.

## AutoListeningCoordinator Race Fix Plan
- Instrument `_startListening`, `_stopListeningAndRecording`, and `_startRecording` with temporary telemetry (timestamps, `_autoModeEnabled`, generation values) to establish baseline overlap conditions during rapid voice/chat switches.
- Introduce `_vadTransitionLock` helpers (`_awaitVadTransition`, `_beginVadTransition`, `_endVadTransition`) and wrap `_startListeningAfterDelay`, `_startListening`, `_stopListeningAndRecording` so only one transition can run at a time.
- Replace direct `_autoModeEnabled` writes with `_setAutoModeEnabled(bool value, {String context})` and call it from every path (`enableAutoMode*`, `disableAutoMode`, `reset`, `initialize`) to keep toggles atomic and centrally logged.
- Maintain `_vadGeneration`/`_activeListeningGeneration`; pass the current generation into `_executeListeningStart`, `_startRecording`, and timer callbacks to ignore stale work when the generation changes.
- Add `_cancelAllTimers(reason)` and call it before each transition; after `_safeStopVAD()` and `_stopRecording()` await a short delay (`kPostStopDelay`) so AudioRecord releases native resources before new starts.
- Ensure `VoiceService.enableAutoModeWhenPlaybackCompletes()` waits for both `_ttsActive == false` and `AudioPlayerManager.playbackActive == false` before re-enabling auto mode, and that `_stopListeningAndRecording` clears pending auto-mode flags so the bloc re-validates mode state.
- After implementation, run focused unit/integration tests with overlapping starts/stops to verify stale callbacks are ignored, and capture logs to confirm auto-mode flips occur strictly in sequence without the prior race symptoms.
