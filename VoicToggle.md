# Voice Mode Toggle Stabilization

The goal is to serialize the chat → voice hand-off so the audio player reset, TTS reset, and auto-listening enablement no longer race each other. Keeping this fix tightly scoped prevents regressions in the steady-state audio pipeline.

## Implementation Plan

1. **Review Current Sequence**  
   Walk through the voice-mode branch in `VoiceSessionBloc._onSwitchMode` to document the present order of `lightweightReset()`, `resetTTSState()`, `autoListeningCoordinator.reset()`, and `enableAutoMode()`. Note which calls are awaited and where we emit `isMicToggleEnabled: false` / `isVoicePipelineReady: false`.

2. **Add a Serial `prepareForVoiceMode` Helper**  
   Create a private async helper inside the bloc to orchestrate the transition. The helper should:
   - Emit the guarded state (`micToggleEnabled=false`, `voicePipelineReady=false`, `isAutoListeningEnabled=false`).
   - Await `_safeVoiceService.getAudioPlayerManager().lightweightReset()`.
   - Await `_safeVoiceService.resetTTSState()` (wrap in `Future.sync` if currently synchronous for clarity).
   - Await `_safeVoiceService.autoListeningCoordinator.reset()` if it returns a `Future`; otherwise wrap in a microtask so ordering stays explicit.
   - Re-establish any AutoListening subscriptions that get torn down by the reset (cancel existing, recreate once reset completes).
   - Add `await Future.delayed(const Duration(milliseconds: 100))` to let the underlying streams settle.

3. **Defer Auto Mode Enablement**  
   Move the existing `await _safeVoiceService.enableAutoMode()` (and `_triggerListening()`) to the end of the helper so they run only after the reset sequence finishes. Before enabling, re-check `state.isVoiceMode` to guard against rapid re-toggles.

4. **Restore Pipeline Readiness**  
   Once `enableAutoMode()` resolves, emit updated state: `isAutoListeningEnabled=true`, `isMicToggleEnabled=true`, `isVoicePipelineReady=true`, and `ttsStatus=TtsStatus.idle`. Keep the AutoListening state-stream subscription in place so later transitions still update readiness automatically.

5. **Protect Against Overlap**  
   Introduce an `_isSwitchingToVoiceMode` flag (set true before calling the helper, reset in a `finally`) to prevent re-entrancy if the user flips modes again mid-transition.

6. **Improve Logging**  
   Sprinkle clear `debugPrint` statements around each stage: “voice-mode reset started”, “audio reset complete”, “TTS reset complete”, “auto-listening enabled”, “voice pipeline ready”. These markers make it obvious in logs that the serialized order is holding.

7. **Regression Pass**  
   After wiring the helper, exercise chat→voice toggles on-device. Confirm the mic button remains disabled until the final readiness log and re-enables reliably. Verify the welcome flow, mid-session toggles, and TTS playback still behave as before. Run `flutter test` where possible.

## Optional Hardening Tweaks

- **Mounted / isClosed guard** – Before emitting the final ready state, ensure the bloc is still active and in voice mode (e.g., `if (isClosed || !state.isVoiceMode) return;`). This prevents stale emits when the user pivots back to chat mid-transition.
- **Completer-backed gating** – Replace the simple `_isSwitchingToVoiceMode` boolean with a `Completer<void>` so other handlers can `await` the readiness future if needed (`if (_voiceSwitchCompleter?.isCompleted == false) await _voiceSwitchCompleter!.future;`).
- **Adjustable settle delay** – If RNNoise/VAD startup logs still show timeouts on-device, bump the post-reset delay to ~150–200 ms; otherwise keep it minimal to avoid unnecessary latency.
- **State-aware re-enable** – When you unlock the mic toggle, confirm the coordinator has actually reached `AutoListeningState.listening` (or `listeningForVoice`) so the UI reflects real readiness instead of only elapsed time.

## Deferred Auto-Enable Fix

1. **Audit current flow** – Map where `_prepareForVoiceMode` invokes `enableAutoMode()` and how `_deferAutoMode`/`_waitForTtsCompletion()` are used so we know the existing triggers.
2. **Introduce pending flag** – Add a private boolean (e.g., `_pendingVoiceModeAutoEnable`) that is set whenever we switch to voice while TTS is still active, and cleared on session teardown.
3. **Gate auto-mode in helper** – After audio/TTS reset completes inside `_prepareForVoiceMode`, check `isTtsActive` or the audio manager’s playing state. If TTS is still running, skip `enableAutoMode()`, set the pending flag, and log; otherwise proceed as today.
4. **Resume on TTS completion** – In `TtsStateChanged(false)` (or equivalent), if the flag is set and we’re still in voice mode, call a helper that performs `enableAutoMode()`, clears the flag, and triggers listening if appropriate.
5. **Cleanup** – Reset the flag in chat-mode entry, session end, and error cleanup paths to avoid stray re-enables.
6. **Verify on device** – Toggle chat→voice while TTS is playing; ensure the recorder waits until playback fully stops and that the welcome guard still works.

## Race Condition Fix #3

1. **Audit idle signals** – Confirm `_prepareForVoiceMode` sets `_pendingVoiceModeAutoEnable` whenever TTS is active or the audio player is still playing, and note where `isVoicePipelineReady` gets emitted. Trace every call to `_resumeDeferredVoiceAutoMode()` (TTS state, audio playback, prep `finally`).
2. **Wait for both idle events** – In `_resumeDeferredVoiceAutoMode`, return early unless `_pendingVoiceModeAutoEnable` is true and both `!isTtsActive` **and** `!audioPlayerManager.isPlaying`. Only then call `enableAutoMode()` and log the resume.
3. **Unlock mic on listening** – After the deferred enable completes, rely on the AutoListening state stream to set `isMicToggleEnabled` / `isVoicePipelineReady` once the coordinator enters `listening` or `listeningForVoice`. If necessary, add a guard in that listener to check that the deferred flag is clear before unlocking.
4. **TTS/Audio callbacks** – Adjust `TtsStateChanged(false)` and the audio playback handler so they call the helper but let it exit early unless both idle conditions are met. Log when the helper keeps waiting, to ease debugging.
5. **Cleanup safety** – Reset `_pendingVoiceModeAutoEnable` on chat-mode entry, session end, and error cleanup so no deferred resume fires later.
6. **On-device verification** – Toggle chat→voice during long TTS playback and confirm VAD waits until audio finishes and the mic re-enables only after the coordinator reports `listening`.

## Race Condition Fix #4

1. **Preserve welcome flag** – Stop resetting `isInitialGreetingPlayed` when re-entering voice mode so mid-session toggles keep the handshake state intact.
2. **Unlock mic on coordinator readiness** – Update `_onStartListening` to infer readiness from the last AutoListening state (listening/listeningForVoice) plus the welcome flag, while `_onStopListening` continues to guard the mic.
3. **Defer auto-mode until both idle** – Ensure `_resumeDeferredVoiceAutoMode` only runs `enableAutoMode()` after both `!isTtsActive` and `!audioPlayerManager.isPlaying` are true, logging when it’s still waiting.
4. **Fire the helper from idle callbacks** – Invoke the helper from `TtsStateChanged(false)` and `AudioPlaybackStateChanged(false)` so the deferred resume re-evaluates whenever TTS or audio playback finishes draining.
5. **Reset the flag on teardown** – Keep clearing `_pendingVoiceModeAutoEnable` on chat entry, cleanup, and bloc close so no deferred enable leaks into other modes.
6. **Regression pass** – On device, flip chat→voice during long TTS replies; confirm the mic re-enables only after real idle, and the welcome flow still behaves as expected.

## Race Condition Fix #5

1. **Locate TTS state ingress** – Focus on `lib/services/voice_service.dart:updateTTSSpeakingState`, the single point dispatching `startListening()`/`stopListening()`. Confirm no other call sites bypass it.
2. **Add playback mutex** – Introduce a private `_stateLock` (`Object`) plus `_ttsActive`/`_recordingActive` booleans. Wrap the body of `updateTTSSpeakingState` in `synchronized(_stateLock, () async { ... })` (or an equivalent Completer queue) so only one transition mutates state at a time.
3. **Guard duplicate edges** – Inside the lock, short-circuit if `_ttsActive == isSpeaking` and the playback token is unchanged. Record the active token so stale completions are ignored without re-arming the mic.
4. **Coordinate mic stop-before-play** – When `isSpeaking` flips `true`, set `_ttsActive = true`, call `tryStopRecording()` (await), then invoke `autoListeningCoordinator.stopListening()` so recording is fully down before playback begins.
5. **Gate listening restart** – When `isSpeaking` flips `false`, clear `_ttsActive` and conditionally call `autoListeningCoordinator.startListening()` only if voice mode is still active, the service is not muted or ending, and no bloc-level deferral flag is set. Expose a lightweight getter so the bloc can signal pending deferrals; log and exit early when the guard fails.
6. **UI mic disable hook** – Surface a read-only `isTtsActive` getter/stream driven by `_ttsActive` so `TextInputBar` (and any other UI) can disable its mic button whenever playback is in progress. Ensure chat mode continues to skip TTS entirely.
7. **Lifecycle cleanup** – Reset `_ttsActive`, `_recordingActive`, and release any pending lock waiters during session teardown (`_forceSessionCleanup`, `close`) to avoid sticky “lock held” states when rebuilding the bloc.
8. **Logging and verification** – Add debug prints upon lock entry/exit, mic stop, and guarded starts. Reproduce the prior race (toggle modes mid-TTS); verify logs show serialized transitions and that `startListening()` only fires after playback completes. Re-run chat flows, welcome greeting, and long TTS responses to confirm no regressions.
9. **Production readiness add-ons** – Document the shared-state contract between chat/voice, expose an `isTransitioning` guard so neither side sends new work mid-switch, split the session façade into base/voice interfaces to avoid stubbed voice methods in chat, and wrap session start/stop with try/catch rollback so partial inits tear down cleanly.
