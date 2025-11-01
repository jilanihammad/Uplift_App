# Welcome Mic Toggle Guard – Final Fix Plan

## Objective
Close the race window that allows the mic mute button to be pressed during the welcome TTS by disabling the toggle before any asynchronous work begins and ensuring it is always re-enabled afterward, without touching the broader audio pipeline.

## Steps

### 1. Disable the toggle as early as possible
- **File:** `lib/blocs/voice_session_bloc.dart`
- In `_onInitialMoodSelected`, emit `state.copyWith(isMicToggleEnabled: false)` right before enqueuing `PlayWelcomeMessage`. This ensures the flag flips as soon as we schedule the welcome audio.

### 2. Reorder `_onPlayWelcomeMessage`
- At the very top of `_onPlayWelcomeMessage`, add:
  ```dart
  if (!state.isMicToggleEnabled) return;
  emit(state.copyWith(isMicToggleEnabled: false));
  ```
  This immediately locks the toggle and short-circuits unexpected re-entry.
- Keep the rest of the logic inside a `try { … } finally { emit(state.copyWith(isMicToggleEnabled: true)); }` wrapper so the flag always returns to `true`.

### 3. Maintain existing behaviour
- Retain the current `catch` block for logging and `errorMessage`, but remove any direct manipulation of `isMicToggleEnabled`; the `finally` handles restoration.
- Do not modify `updateTTSSpeakingState`, the TTS token logic, auto-listening flow, or Live TTS streaming—the guard purely affects UI enablement during the welcome clip.

### 4. UI already respects the flag
- `voice_controls_panel.dart` disables the mute button when `isMicToggleEnabled` is false, so no additional UI changes are required.

### 5. Validation
- Manual QA:
  1. Start a new session; confirm the mute button greys out immediately when the welcome audio is scheduled.
  2. Tap the button during welcome playback—no crash should occur.
  3. Confirm the button re-enables once the welcome finishes or errors out.
  4. Ensure later (non-welcome) TTS runs still allow muting as before.
