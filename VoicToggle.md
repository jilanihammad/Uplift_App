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

Following these steps keeps the change minimal while eliminating the race currently flipping the mic guard.

## Optional Hardening Tweaks

- **Mounted / isClosed guard** – Before emitting the final ready state, ensure the bloc is still active and in voice mode (e.g., `if (isClosed || !state.isVoiceMode) return;`). This prevents stale emits when the user pivots back to chat mid-transition.
- **Completer-backed gating** – Replace the simple `_isSwitchingToVoiceMode` boolean with a `Completer<void>` so other handlers can `await` the readiness future if needed (`if (_voiceSwitchCompleter?.isCompleted == false) await _voiceSwitchCompleter!.future;`).
- **Adjustable settle delay** – If RNNoise/VAD startup logs still show timeouts on-device, bump the post-reset delay to ~150–200 ms; otherwise keep it minimal to avoid unnecessary latency.
- **State-aware re-enable** – When you unlock the mic toggle, confirm the coordinator has actually reached `AutoListeningState.listening` (or `listeningForVoice`) so the UI reflects real readiness instead of only elapsed time.
