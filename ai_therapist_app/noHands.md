# Hands-Free Voice Mode Implementation Plan (noHands.md)

## Goal
Enable fully natural, hands-free voice therapy sessions in the AI Therapist app, so the user can converse with Maya without pressing the "Talk" button. The system should:
- Prevent self-listening (no mic input during TTS)
- Automatically listen after TTS ends (no delay)
- Accurately detect user speech (VAD tuning)
- Provide clear visual/audio feedback for all states
- Always allow switching to text mode
- For testing: keep the "Talk" button until the final step

---

## Implementation Steps

### 1. **Prevent Self-Listening**
- [x] **Mute/disable microphone input while Maya (TTS) is speaking**
  - Ensure VAD, mic, and recorder are fully disabled during TTS playback.
  - Confirm this is handled in `AutoListeningCoordinator` and `VoiceService`.
  - Add debug logs to verify no audio input is active during TTS.
  - **Add a small buffer (50-100ms) after TTS ends before reactivating the mic.**
    - *Why:* Prevents edge cases where TTS might still be finishing but the mic turns on too soon, ensuring no overlap between TTS and listening.
  - **Tested:** Logs confirm that VAD and recording are stopped during TTS, and only resume after a 75ms buffer. No overlap or race conditions observed. ✅

### 2. **Automatic Listening (VAD)**
- [ ] **Start VAD/listening immediately after TTS finishes**
  - Remove or minimize any delay after TTS ends (currently 300ms in `AutoListeningCoordinator`).
  - **Use an event listener or callback from the TTS engine to trigger VAD, rather than a fixed delay.**
    - *Why:* This makes the transition smoother and more precise, avoiding any hardcoded timing assumptions.
  - Add debug logs to confirm timing.

### 3. **VAD Tuning**
- [ ] **Tune VAD sensitivity for accurate speech detection**
  - Expose VAD sensitivity/threshold as a parameter (in code or via UI slider).
  - Test and adjust to filter out background noise but reliably detect user speech.
  - **If Flutter's built-in VAD struggles with noisy environments, consider integrating a machine learning-based VAD (e.g., via a library or API).**
    - *Why:* Therapy sessions might happen in varied settings, and better accuracy could improve the user experience.
  - Document recommended settings.

### 4. **Visual & Audio Feedback**
- [ ] **Add clear indicators for all states**
  - Show animated icons or color changes for:
    - AI Speaking (TTS)
    - Listening (VAD active)
    - User Speaking (recording)
  - Optionally, play a subtle sound cue when listening starts.
  - **Accessibility:**
    - Use high-contrast colors or patterns for color-blind users.
    - Make the sound cue configurable (on/off) in settings.
    - *Why:* Accessibility is key in a therapy app, and some users might find sound cues disruptive.
  - Update `chat_screen.dart` UI accordingly.

### 5. **Keep Toggle for Text Mode**
- [ ] **Ensure user can always switch to text mode**
  - Keep the "Switch to Chat Mode" button visible in voice mode.
  - Test switching between modes during a session.

### 6. **Remove "Talk" Button (Final Step)**
- [ ] **Remove the "Talk" button from UI in auto mode**
  - Only after all above steps are tested and verified.
  - If user disables auto mode, show the "Talk" button for manual control.
  - Update documentation and UI.

---

## Testing Notes
- For development/testing, keep the "Talk" button visible until Step 6 is complete.
- Mark each step as `[x]` when implemented and tested.
- Add notes or issues found during testing under each step.

---

## Progress Tracking
- [x] Step 1: Prevent Self-Listening
- [ ] Step 2: Automatic Listening
- [ ] Step 3: VAD Tuning
- [ ] Step 4: Visual & Audio Feedback
- [ ] Step 5: Keep Text Mode Toggle
- [ ] Step 6: Remove "Talk" Button (only after all above are complete)

---

**Update this file as you implement and test each step.** 