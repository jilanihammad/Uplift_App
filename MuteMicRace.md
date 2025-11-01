# Welcome TTS Mic Toggle Guard

## 1. Context
- Crashes only occur when the user taps the mute/mic toggle during the initial welcome TTS playback.
- After the welcome clip, the regular streaming path works fine, so we want a minimal fix: disable the mic toggle during the welcome track and re-enable it once playback completes.

## 2. Implementation Plan

### Step 1 – Extend Bloc State
- File: `lib/blocs/voice_session_state.dart`
- Add a new `bool isMicToggleEnabled` (default `true`).
- Update factory constructors, `copyWith`, `props`/`hashCode`, and serialization if present.

### Step 2 – Emit State Changes Around Welcome Playback
- File: `lib/blocs/voice_session_bloc.dart`
  1. In the welcome start path (`_playWelcomeMessage` / `WelcomeMessageRequested` handler):
     - Emit `state.copyWith(isMicToggleEnabled: false)` right before calling `updateTTSSpeakingState(true)`.
  2. In the completion callback and all error/cleanup branches:
     - Await `tts.stop()` / playback completion future, then emit `isMicToggleEnabled = true` (optionally debounce ~100 ms to cover ExoPlayer race).
  3. Ensure any abort/cancel handler (`_stopWelcomeMessage`, etc.) also re-enables the flag.

### Step 3 – Guard the UI Button
- Files: `lib/screens/widgets/voice_controls.dart`, `voice_controls_panel.dart`.
  - Use `state.isMicToggleEnabled ? _handleMicPress : null` for the mute button.
  - Consider subtle UI feedback (reduced opacity / tooltip) while disabled.

### Step 4 – Guard the Event Handler
- In the bloc handler reacting to the mute-toggle event, place `if (!state.isMicToggleEnabled) return;` as the first line—before any logging or side-effects—to ensure backend code never runs while the guard is active.

### Step 5 – Hot-Reload Safety
- In the hosting screen’s `initState` (or when constructing the bloc), explicitly reset the flag to `true` so a mid-TTS hot reload doesn’t leave the toggle permanently disabled during development.

### Step 6 – Verify Interactions with TTS State
- Confirm `updateTTSSpeakingState()` and other auto-listening logic remain independent of the new flag so that once TTS finishes, the toggle is free to re-enable.

### Step 7 – Update Tests
- Adjust any state snapshots or widget tests to include the new flag default.
- Add a focused test verifying the welcome flow disables then re-enables the flag after completion/error.

### Step 8 – QA Checklist
1. Launch app fresh → confirm mic toggle is disabled during welcome TTS and tapping no longer crashes.
2. Wait for completion → verify the toggle re-enables immediately after playback stops.
3. Trigger a normal session afterward → ensure the mic toggle works as before.
4. Exercise failure/skip paths → verify the toggle always returns to enabled.
5. Hot reload mid-welcome (dev only) → ensure the toggle resumes enabled state.

## 3. Notes & Follow-ups
- The change avoids touching the main streaming pipeline; only the welcome clip is gated.
- If the welcome flow is later refactored into the unified pipeline, revisit or remove this guard.
- Monitor logs after rollout for any remaining welcome-related exceptions.
