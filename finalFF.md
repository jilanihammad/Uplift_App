# Voice Mode Reentry Mic Guard

## Background
Switching from chat mode back into voice mode spins up the voice pipeline (auto-listening, VAD, recorder). During that warm-up window the mute toggle becomes re-enabled before the system is fully ready, letting the user tap it and triggering a crash. The welcome-flow fix already works; we now need an analogous guard for voice mode reentry.

## Fix Plan

### 1. Track voice-mode boot state
- Add a `bool isVoicePipelineReady` (or reuse the existing auto-mode signals) in `VoiceSessionState`. Default to `false` when switching into voice mode; set to `true` once auto mode settles into a listening state.

### 2. Disable the toggle during reentry
- In the bloc handler that switches to voice mode (`_onSwitchMode`, the branch that transitions from chat → voice), emit `isMicToggleEnabled: false` and `isVoicePipelineReady: false` before any asynchronous setup begins.
- Also ensure `_beginSessionIfNeeded` keeps the toggle disabled while services initialize.

### 3. Re-enable after auto-listening settles
- Listen for the first `AutoListeningState.listening`/`listeningForVoice` event (i.e., when VAD is active and ready to record). At that point emit `isMicToggleEnabled: true` and `isVoicePipelineReady: true`.
  * Implementation detail: hook into the existing auto-mode completion callback (`_enableAutoModeIfGenerationMatches`) or wherever `_sessionManager` updates to listening state.

### 4. Guard the toggle event
- Keep the existing early-return in `_onToggleMicMute` but update the condition to check both `!state.isMicToggleEnabled` and `!state.isVoicePipelineReady`; log when we ignore the event for clarity.

### 5. UI already respects the flag
- `voice_controls_panel.dart` uses `state.isMicToggleEnabled`, so no UI changes needed. Ensure it keeps referencing the new state field for readiness.

### 6. QA
1. Start a session, switch to chat, then back to voice while the pipeline spins up; mute button should stay disabled until Maya flips to listening, then re-enable automatically.
2. Confirm mid-session toggling still works once ready, and welcome flow remains unaffected.
3. Test hot reload and repeated mode flips to ensure the flag always recovers.

By tying the toggle to the auto-mode readiness state, we close the race without touching the steady-state pipeline.

## Next Steps
1. Add bloc wiring: subscribe to `autoListening.stateStream` inside `VoiceSessionBloc` (after the coordinator is resolved in `_onStartSession`) and map `AutoListeningState.listening` or `listeningForVoice` to `add(const StartListening())`, while mapping teardown states (`aiSpeaking`, `processing`, `idle`) to `add(const StopListening())`; place the subscription near existing audio/recording listeners and store it for disposal.
2. Cover recording edge: in the same subscription, when the coordinator reports `userSpeaking` transitioning to `processing`, ensure we emit a `StopListening` once `_stopRecording` fires so the guard mirrors actual mic availability; log the transitions so we can trace readiness flips during debugging.
3. Update state guard: after the new events are dispatched, verify `_onStartListening` and `_onStopListening` set `isAutoListeningEnabled` and `isVoicePipelineReady` appropriately and include debug prints to confirm the events are received from the coordinator stream rather than UI buttons.
4. Clean up lifecycle: cancel the new subscription inside the bloc’s `close()` method (alongside `_recordingStateSub` etc.) to avoid memory leaks, and ensure the subscription is refreshed whenever a new session scope is created.
5. Validate behavior: run the chat→voice reentry workflow on device, confirm the mute control re-enables immediately after the pipeline settles, then repeat the welcome flow to ensure the initial greeting still lifts the guard at the proper time; capture logs to prove the Start/Stop events fire as expected.
