# Mic Control Refactor Plan

## 1. Clarify Intent
- Confirm UX expectation: mic button should only toggle recording (`isMicEnabled`) while a separate guard suppresses the button only during critical transitions.
- Document desired behavior for all related flags (`isMicEnabled`, new `isMicControlGuarded`, `isVoicePipelineReady`) to avoid future conflation.

## 2. Audit Current Dependencies
- Trace every read/write of the three flags plus auto-listening callbacks (AutoListeningCoordinator, VAD, lifecycle, UI) to know who depends on which signal.
- Note widgets (VoiceControlsPanel) and services that currently assume `isMicToggleEnabled` mirrors auto-listening readiness.

## 3. Decouple UI Enabled State
- Extend `VoiceSessionState` with `isMicControlGuarded` (default `false`) so UI availability is tracked separately from mute state.
- Update `copyWith`/`props` and migrate UI to rely on the new guard instead of auto-listening booleans.

## 4. Rewire Bloc State Updates
- Limit `_updateListeningState` to listening/pipeline readiness; stop toggling the UI guard there.
- Add helpers (`_guardMicControl()`, `_releaseMicControl()`) and invoke them only during known critical sections (welcome TTS, voice-mode prep, mood selection, VAD sync).
- Keep `isMicEnabled` as the sole truth for mic mute state; no auto-listening flag should flip it.

## 5. Simplify Toggle Logic
- Rewrite `_onToggleMicMute` to honor only the guard + `isMicEnabled`; drop the `isVoicePipelineReady` dependency.
- When muting, still dispatch `DisableAutoMode` but leave the guard untouched so the user can unmute immediately.
- When unmuting, trigger `EnableAutoMode` (or defer) regardless of current auto-listening readiness so the UI stays responsive.

## 6. Adjust Auto-Listening Reactions
- Ensure `_triggerListening`, `_resumeDeferredVoiceAutoMode`, lifecycle handlers, and VAD callbacks no longer suppress the guard unless `_guardMicControl()` is explicitly called.
- After each guarded transition completes, call `_releaseMicControl()` (or `EnsureMicToggleEnabled`) to avoid leaving the UI locked.
- Confirm AutoListeningCoordinator still pauses/resumes recording purely based on `EnableAutoMode`/`DisableAutoMode` so behavior matches today with no performance hit.

## 7. UI Wiring
- Update `VoiceControlsPanel` so the button’s enabled state is derived from `!state.isMicControlGuarded`; keep icon state tied to `state.isMicEnabled`.
- Optionally show a tooltip/snackbar when a guarded button is tapped to reduce user confusion if a guard is active.

## 8. Testing & Verification
1. Bloc unit tests covering the guard helpers plus `ToggleMicMute`, `EnableAutoMode`, and `DisableAutoMode` to ensure the guard releases correctly.
2. Manual script: start session → mute/unmute during welcome TTS, while AI speaks, and mid mode-switch to ensure the guard releases predictably.
3. Smoke test auto-listening (VAD resumes after unmute, pipeline pauses on mute) to confirm no regressions.

## 9. Documentation
- Update inline comments where the new guard is used.
- Add a short developer README section summarizing the new mic-mute behavior and guard rules to prevent future regressions.
