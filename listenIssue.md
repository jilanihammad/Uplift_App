# Auto-Listening + TTS Race Fixes

## Problem Summary
Recent logs surfaced two intertwined problems:

1. **Premature VAD restart** – `enableAutoModeWhenPlaybackCompletes()` can rearm auto mode while Maya is still speaking because we only wait for a single `false` from the playback stream.
2. **Concurrent shutdown** – When the user switches to chat mode, a pending speech-end timer fires at the same moment, so `_stopRecording()` runs in parallel with mode-switch teardown.

Both issues let RNNoise listen to Maya’s own audio or leave the coordinator in an undefined state.

## Fix Steps

1. **Harden `enableAutoModeWhenPlaybackCompletes()`**
   - Capture the active playback token when scheduling the wait and pass it into the helper.
   - Await `playbackActiveStream.firstWhere((active) => !active)`, then delay an additional ~100 ms so ExoPlayer can settle.
   - After the delay, re-check:
     - `_generation` is unchanged
     - `_ttsActive == false`
     - `_playbackActive == false`
     - No new token has appeared (`_currentPlaybackToken` still matches the one we captured; `_lastPlaybackToken` has not changed unexpectedly)
   - Only call `enableAutoMode()` when *all* checks pass; otherwise log and exit.

2. **Cancel speech-end timers on mode switches**
   - In `AutoListeningCoordinator.disableAutoMode()`, call `_cancelSpeechEndTimer(reason: 'Mode switch to chat')` before flipping `_autoModeEnabled` or triggering shutdown.
   - This prevents the timer from firing mid-transition and invoking `_stopRecording()` twice.

3. **Guard `_startListening()` against active TTS**
   - At the top of `_startListening()`, query `voiceService.isTtsActive` (or `_ttsActive`).
   - If true, log a warning and return immediately; this ensures auto mode never starts while Maya’s audio is still playing, even if another path triggers `_startListening()`.

## Implementation Notes
- Keep the existing playback wait logic, but add the token/generation capture and post-delay validation before enabling auto mode.
- Ensure `_generation` increments whenever a new voice session lifecycle starts so the comparison is meaningful.
- `_cancelSpeechEndTimer` already exists—reuse it with a descriptive reason.
- Don’t block the UI thread; use `await Future.delayed` for the debounce.
- After implementing, exercise both flows: welcome TTS → idle, and voice→chat mode switch. Confirm no VAD activity occurs while TTS is active and no duplicate recording shutdown happens on mode switch.
