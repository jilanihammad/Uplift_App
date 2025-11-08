# Double Race Condition Fix Plan

## Issue A: Duplicate Auto-Mode Waits per TTS Cycle

### Symptoms
- Logs show `enableAutoModeWhenPlaybackCompletes` called twice for the same playback token.
- `_stopListeningAndRecording` (and VAD generation) run multiple times while TTS is still starting.

### Fix Steps
1. Allow only **one** call to `enableAutoModeWhenPlaybackCompletes` per TTS cycle.
   - Remove early invocations (e.g., from bloc/coordinator). The sole trigger should be the playback-token callback (`AudioPlayerManager.onPlaybackToken`).
2. Guarantee the helper always receives the actual token.
   - Inside the callback, set `_currentPlaybackToken = token` and immediately call `enableAutoModeWhenPlaybackCompletes(playbackToken: token)`.
   - Add an early return in the helper if `playbackToken` is null.
3. Protect against accidental re-entry.
   - Keep a small latch (e.g., store active token in a set and skip if we’ve already scheduled it) so retries don’t queue up another wait.
4. Validate in logs that each playback token produces exactly one “enableAutoModeWhenPlaybackCompletes” entry, one VAD shutdown, and one auto-mode rearm.

## Issue B: Auto Mode Disabled During Voice Mode Switch

### Symptoms
- After switching to voice mode, `_startListening()` logs “external trigger ignored – auto mode disabled”.
- Reset sequence (`AutoListeningCoordinator.reset`) sets auto mode to false even for partial reset.

### Fix Steps
1. Tweak reset so partial resets do **not** clear auto mode.
   - Either add a parameter (e.g., `preserveAutoMode`) or guard `_setAutoModeEnabled(false)` when `fullReset == false`.
2. In the voice-mode prep flow (VoiceSessionBloc / VoiceModeFacade):
   - Call the reset first.
   - Immediately re-enable auto mode (`voiceService.enableAutoMode()`).
   - Then kick off `_triggerListening()`.
3. Verify that after the switch, `_autoModeEnabled` remains true and auto mode begins listening.
4. Regression test: welcome TTS + voice switch + chat switch; confirm no “auto mode disabled” warnings and Maya listens as expected.

Following these steps eliminates both the double-scheduled auto-mode wait and the voice-mode auto-mode drop.

## Tuesday Issue

1. Remove the `isInitialGreetingPlayed` guard inside `_resumeDeferredVoiceAutoMode`; it prevents auto-mode from re-arming when returning to voice mid-session.
2. Add a bloc-level `_welcomeAutoModeArmed` flag (default `false`).
3. Set `_welcomeAutoModeArmed = true` right after the welcome TTS completes and `_resumeDeferredVoiceAutoMode()` is queued.
4. Gate `_resumeDeferredVoiceAutoMode` with `if (!_welcomeAutoModeArmed) return;` while keeping the existing playback/TTS idle checks.
5. Leave chat↔voice switch logic untouched so the standard three-second mic guard still applies.
