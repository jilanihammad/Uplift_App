# Maya Voice Pipeline Guard Refactor

Re-architect the voice-mode guard so Maya never starts listening while she is still speaking. This replaces the current patchwork of deferred auto-mode flags with a coordinator-level veto that tracks real audio state.

## Goals
- **Single Guard Authority**: AutoListeningCoordinator enforces the "AI silent" check internally—no external caller (bloc or service) can force listening on while TTS/audio playback is active.
- **Deterministic Flow**: Remove redundant `_pendingVoiceModeAutoEnable` logic from `VoiceSessionBloc`. Listening re-enables exactly once per TTS completion.
- **Maintain Existing UX**: Initial greeting and welcome flows stay protected; voice↔chat transitions continue to work.

## Scope
- Refactor `AutoListeningCoordinator`, `VoiceService`, and `VoiceSessionBloc` as needed.
- Update any shared interfaces (`IVoiceService`, `AutoListeningCoordinator`) to expose the necessary callbacks/state.
- Update documentation/tests.

## Work Items

### 1. Document Current Pain Points
- [x] Traced the chat→voice timeline: `_resumeDeferredVoiceAutoMode` re-enabled listening while the coordinator lacked veto authority (see `voice_session_bloc.dart`).
- [x] Identified/remodeled every `_pendingVoiceModeAutoEnable` + `_resumeDeferredVoiceAutoMode` usage (now removed from the bloc).
- [x] Confirmed `VoiceService.canStartListeningCallback` is now only used for the welcome flow; the coordinator owns all other vetoes.

### 2. Harden AutoListeningCoordinator
- [x] Added `FeatureFlags.coordinatorVoiceGuardEnabled` (debug drawer toggle) to roll back if needed.
- [x] `_aiAudioActive` + `_autoModeEnabledDuringAiAudio` now track AI playback and pending auto-mode requests.
- [x] Every entry point (`startListening`, `_startListening`, `_startListeningAfterDelay`, `_startRecording`, `_executeListeningStart`) returns early while `_aiAudioActive` is true.
- [x] `_aiAudioActiveStream` combines TTS + playback, with logging verifying both are idle before clearing.
- [x] When `_aiAudioActive` flips to false and auto mode is still pending, the coordinator schedules `_startListeningAfterDelay()` automatically.
- [x] Reused the existing `aiSpeaking` state to represent the waiting period (with new logs).

### 3. Simplify `VoiceSessionBloc`
- [x] Removed `_pendingVoiceModeAutoEnable`, `_resumeDeferredVoiceAutoMode()`, and the timeout helpers—bloc simply dispatches `EnableAutoMode` once per switch.
- [x] Welcome flow still uses `_welcomeAutoModeArmed`; we dispatch `EnableAutoMode` once the greeting TTS completes.
- [x] Chat→voice prep still stops playback/reset audio before calling `voiceService.enableAutoMode()`; no extra guards in the bloc.

### 4. Update `VoiceService` / Facade
- [x] VoiceService still exposes TTS/playback state to the coordinator.
- [x] `canStartListeningCallback` now only guards the welcome flow; all other vetoes live in the coordinator.
- [x] After TTS completes, `autoListeningCoordinator.startListening()` is called unconditionally and the coordinator decides whether to proceed.

### 5. Coordinator Behavior Changes
- [x] Coordinator now enters `aiSpeaking` whenever `_aiAudioActive` is true and won’t reopen until it clears.
- [x] Listening restarts automatically when `_aiAudioActive` flips false.
- [x] TTS start events force-stop VAD/recording and schedule the restart.
- [x] 10-second timeout guard logs a warning and forces listening if AI audio never clears.
- [ ] Validate lifecycle behavior (needs explicit test to ensure background/foreground transitions honor `_aiAudioActive`).

### 6. Tests & Validation
- [x] Unit tests (`test/services/auto_listening_coordinator_guard_test.dart`) cover the guard, retry, timeout, and feature flag behaviors.
- [ ] Regression + lifecycle device validation still pending (initial voice start, chat→voice during TTS, voice→chat→voice idle, auto-mode toggles, background/foreground).
- [ ] Manual device test (SM S938U1) verifying the mic never reopens until Maya finishes speaking.

### 7. Cleanup & Docs
- [x] `midsession.md` updated with the new coordinator-driven guard/states.
- [x] Dead code removed from `VoiceSessionBloc` and `VoiceService`.
- [ ] Document coordinator states/guard expectations in a central reference (e.g., README or architecture doc).

## Risks / Considerations
- Ensure coordinator changes don’t break Gemini Live recordings or other voice modes.
- Verify welcome message flow and AppLifecycle muting/unmuting still work with the new guard.
- Watch for potential deadlocks if the veto never returns true (add logging/timeouts at the coordinator level instead of the bloc).

## Definition of Done
- AutoListening never transitions into `listening`/`userSpeaking` while `isTtsActive || audioPlayerManager.isPlaybackActive`.
- `VoiceSessionBloc` no longer tracks pending auto-enable flags; the logic lives in one place (coordinator).
- Tests and docs updated to reflect the new architecture.

## Remaining Fix
- **Scope aiAudio subscription to a session**: Ensure `SessionScopeManager` (or the owning facade) provisions a fresh `AutoListeningCoordinator` for each voice session so `_aiAudioActiveStream` is disposed on teardown and cannot replay stale values when the user re-enters voice mode.
- **Reset coordinator audio state synchronously**: Inside `AutoListeningCoordinator.reset()` immediately call `_invalidateVadGeneration()`, set `_aiAudioActive = false`, clear `_autoModeAwaitingAiSilence`, and emit `false` to the controller so observers learn the guard is idle before the next mode switch.
- **Force playback/TTS emit false during tear-down**: Update `VoiceService.resetTTSState()` and `AudioPlayerManager.lightweightReset()` to push `false` into their playback/TTS streams before debouncers shut down. This guarantees the combineLatest stream settles to false prior to disposal.
- **Gate callbacks by generation**: Increment a `voiceSessionGeneration` every time the coordinator is rebuilt and have `VoiceService`/`AudioPlayerManager` ignore callbacks from older generations so no lingering audio events can flip `_aiAudioActive` after reset.
- **Validate without bandaid delays**: Keep `_aiAudioActive` as the single authority inside `enableAutoMode()` and rely on the synchronous reset + scoped subscriptions instead of adding artificial `Future.delayed` waits in the bloc.
- **Test coverage**: Extend `test/services/auto_listening_coordinator_guard_test.dart` with a chat→voice bounce scenario that asserts `_aiAudioActive` clears on reset and `enableAutoMode()` proceeds directly to `listeningForVoice` without hitting the 10-second timeout. Follow up with manual QA reproducing the user flow (voice → chat during TTS → voice) to confirm no `[GUARD] AI audio timeout hit` logs.

## Final Small Fix (done)
- **Graceful auto-mode disable**: When chat mode tears down, delay `_setAutoModeEnabled(false)` until `_stopListeningAndRecording()` finishes and `_isRecordingActive`, `_isVadActive`, and `_aiAudioActive` are all false. This keeps VAD callbacks valid while the mic stack winds down and prevents the coordinator from ignoring live speech events mid-switch.
  - Implementation detail: add a `_pendingDisableCompleter` (or similar) so `disableAutoMode()` marks a pending disable, triggers `_stopListeningAndRecording()`, and only resolves once the coordinator observes complete shutdown—then call `_setAutoModeEnabled(false)` and `_forceAiAudioIdle()`.
  - Call sites: reuse this helper from the chat→voice reset path (VoiceSessionBloc/VoiceService) so mode switches await the graceful shutdown future before invoking the next `enableAutoMode()`.

## Final Fix (done)
- **Mandatory awaiting of graceful disable**: Ensure every teardown path (VoiceSessionBloc lifecycle handlers, chat→voice reset, app pause) awaits the `disableAutoMode()` future so the coordinator can finish `_stopListeningAndRecording()` + `_waitForAiAudioSilence()` before any `reset()` runs. Never fire-and-forget the disable helper.
- **Shared pending future**: `disableAutoMode()` must reuse a single `_pendingDisableCompleter` so concurrent callers share the same promise. Subsequent calls should await the existing future instead of starting overlapping teardowns.
- **Explicit targets**: `_onEndSession`, lifecycle pause/hidden handlers, chat→voice prep, and VoiceModeFacade teardown must `await voiceService.disableAutoMode()` before invoking coordinator resets or destroying the session scope.
- **Lifecycle race testing**: Add a bloc-level test that simulates `AppLifecycleState.paused` while `AutoListeningCoordinator` is in `userSpeaking`, and assert the bloc doesn’t reset/disable until the graceful disable future completes. This catches the backgrounding race we’re seeing on device.

## Delay Rollback Plan
- While the temporary "Getting Maya ready" delay is in place, only the chat→voice branch of `VoiceSessionBloc._onSwitchMode` changes: we emit a loading state, wait 3 seconds, then call `_prepareForVoiceMode`.
- To revert, delete the delay logic and the associated UI flag/spinner wiring so the branch behaves exactly as before (immediate `_prepareForVoiceMode`).
- Remove any logging or localization strings added for the loading message and ensure the UI goes back to toggling instantly.

## another last fix attemped, but still didnt fix race yet
When audio playback completes, just_audio transitions through these states:

1. `playing=true`, `processingState=ready` (actively playing)
2. `playing=false`, `processingState=ready` ← UNGUARDED WINDOW (~20-50ms)
3. `playing=false`, `processingState=completed` (fully finished)

In state #2, the audio has stopped playing but hasn't fully completed yet. The previous `isRealTimePlaybackActive` implementation only checked:
- `playing` (false in state #2)
- `ProcessingState.loading` (not applicable)
- `ProcessingState.buffering` (not applicable)

So it returned `false` during this transition window, allowing `onProcessingComplete()` to start VAD before the audio was truly done.

**The fix:**

Updated `isRealTimePlaybackActive` (`audio_player_manager.dart:686-690`):

```
bool get isRealTimePlaybackActive =>
    _audioPlayer.playing ||
    _audioPlayer.processingState == ProcessingState.loading ||
    _audioPlayer.processingState == ProcessingState.buffering ||
    _audioPlayer.processingState == ProcessingState.ready; // ← NEW: catches transition state
```

Now the guard blocks listening during all audio-active states, including the brief transition window where `playing=false` but `processingState=ready`.

**Changes made**

1. `audio_player_manager.dart:690` – Added `ProcessingState.ready` check.
2. `auto_listening_coordinator_guard_test.dart:709-759` – Added test for `playing=false`, `processingState=ready` scenario.

## Quiet window guard (done)
- Actual device logs (SM S938U1) show just_audio briefly flips back to `playing=true`/`processingState=ready` after we sample the state, so AutoListeningCoordinator thinks audio is idle even though playback is still cleaning up.
- Next fix: require a continuous 150 ms "quiet window" where `_aiAudioActive`, `VoiceService.isTtsActive`, and `AudioPlayerManager.isRealTimePlaybackActive` are all false before `_startListeningAfterDelay`, `_executeListeningStart`, or `_startListening` proceed.
- Implementation detail: add a `_waitForQuietAudioWindow()` helper that polls the real-time playback state every 15 ms (timeout ~2 s). If we never get a quiet window we mark `_autoModeEnabledDuringAiAudio` and keep the guard engaged instead of launching VAD immediately.
- Goal: prevent VAD from opening during the just_audio ready bounce without reintroducing arbitrary fixed delays.


## Single Fix Strategy (reverted this this))
- Root cause: AutoListening restarts before the next TTS stream begins, so sampling `isRealTimePlaybackActive` misses the future playback spike. We need an explicit handshake so the next AI response cannot start until the mic is ready.
- Fix plan:
  1. Add a `ttsGeneration` completer in `AutoListeningCoordinator`. When `stopListening()` runs for TTS start, set `_aiAudioActive = true` and create a new completer. Only after `_startListeningAfterDelay` finishes (i.e., the coordinator reaches `listening` or `listeningForVoice`) do we complete the completer and emit `_aiAudioActive = false`.
  2. Expose `awaitQuietResume(int generation)` on the coordinator. VoiceService calls this right before launching the next playback; it suspends until the completer resolves or a timeout triggers, keeping `_aiAudioActive` true the entire time.
  3. Propagate the generation/token through VoiceService + AudioPlayerManager (e.g., reuse the token in `enableAutoModeWhenPlaybackCompletes`). Before starting the new TTS stream, call `awaitQuietResume(currentGeneration)` so playback never starts while the guard is still reopening.
  4. Leave the quiet-window logic as a belt-and-suspenders check, but treat the handshake as the primary gate; if the handshake waits longer than ~2 s, log `[GUARD] resume handshake timeout` and keep `_aiAudioActive` true so VAD never reopens.
- Learnings: The ready-state spike wasn’t the culprit—the race existed because we opened listening before the next AI audio arrived. Polling player state can’t predict future playback; regimented generation-based handshakes are the only safe fix. Always couple mic state with playback tokens so TTS can’t preempt the guard.
- Additional safeguard: serialize TTS starts in `VoiceService` by checking `_ttsQueueDepth`/`_pendingTtsGeneration`. If another handshake is in flight, log `"[TTS] Waiting for previous TTS handshake to complete"` and await the existing future before requesting playback so multiple TTS streams can’t race for the same resume signal.

## Chat→Voice Replay Guard (reverted - this was totally fucked up)
- Hypothesis: During chat→voice switches, we replay Maya’s last text as TTS before the live conversation starts. The replay finishes quickly, triggers `onProcessingComplete()`, and the coordinator reopens VAD while the *next* (real) TTS is already en route. Result: Maya listens to her own voice.
- Plan:
  1. Treat the chat→voice replay as active AI speech instead of “processing done” (skip `onProcessingComplete()` for that path or keep `_aiAudioActive` true until the first real reply starts).
  2. Optionally add an explicit “replay mode” flag so AutoListeningCoordinator ignores `processing → idle` transitions triggered by the replay.
  3. Remove the replay entirely if UX allows, so voice mode always starts fresh instead of echoing the last text response.
- Goal: ensure the handshake stays engaged until the first real voice-mode TTS completes, preventing Maya from hearing herself when switching modes.

## Chat→Voice Replay Guard (didnt work - reverted)
- Latest device logs still show Maya speaking before AutoListening shuts down. Even if the replay isn’t audible, the first voice-mode reply starts while auto mode is already listening, so Maya records herself.
- Next fix attempt: keep auto mode enabled (so the mic opens immediately), but set a `pendingFirstVoiceReply` flag during the chat→voice switch. When the first `updateTTSSpeakingState(true)` fires after the switch, immediately flip `_aiAudioActive = true` so AutoListening re-enters `aiSpeaking` before playback starts. Clear the flag once that first reply begins.
- Goal: Maya still listens right after you tap voice mode, but the moment she starts talking the mic is force-closed, eliminating self-recording without delaying the initial listen state.

Next Steps
we’ve bolted so many guard layers (auto-mode flags, replay tags, quiet windows, handshake stubs) that it’s now
  hard to reason about what actually controls the mic. Instead of one deterministic flow, we have three or four overlapping
  ones, so debugging is painful.

  Recommendation

  - Collapse to a single authority for “is Maya speaking?” Right now _aiAudioActive, _pendingFirstVoiceReply, welcome flags,
  and _autoModeEnabledDuringAiAudio all try to represent the same fact. Pick one (e.g., _aiAudioActive sourced directly from
  updateTTSSpeakingState) and delete the rest. AutoListening should only look at that value plus isTtsActive.
  - Move chat→voice replay logic into one place (e.g., VoiceService.startVoiceMode()), so toggling doesn’t fire
  PlayWelcomeMessage, EnableAutoMode, and startListening() simultaneously. If we still need the replay, enqueue it through the
  same TTS path as normal replies but set forceAiSpeaking=true so the coordinator never reopens in-between.
  - Add an integration-style test harness (even a simple script) that mimics “chat → voice → user speaks → AI responds.” That
  way we can iterate without pushing to device every time.

  I’d start by ripping out the redundant flags in VoiceService/AutoListeningCoordinator and funneling every “AI is speaking”
  signal through updateTTSSpeakingState. Once that’s the single source of truth, we can reason cleanly about when to reopen
  the mic—and future debugging stays tractable. Let me know when you’re ready to take that leap and I’ll help restructure it
  carefully.