# Listening Animation Plan

1. **Locate the Animation Trigger**
   - Find the widget/controller responsible for the listening Lottie (likely in `chat_screen.dart` or a shared widget).
   - Note what it currently listens to (AutoListeningCoordinator state, custom flags, etc.).

2. **Expose the Simple Signal**
   - Confirm `VoiceSessionState` already exposes `isListening` and is updated in `_onStartListening` / `_onStopListening`.
   - Decide whether any other UI flags (e.g., `isVoicePipelineReady`) should also influence the animation.

3. **Wire the UI to `isListening`**
   - Update the animation widget to depend solely on `state.isListening`.
   - When `isListening == true`, play the Lottie; when `false`, stop/reset it.
   - Remove legacy listeners tied to AutoListeningCoordinator state names.

4. **Handle Transition Edge Cases**
   - Ensure the widget rebuilds or receives callbacks whenever `isListening` changes (via `BlocBuilder`, `Selector`, or equivalent).
   - Add optional debouncing in the widget if needed to avoid flicker, rather than relying on coordinator timing quirks.

5. **Clean Up Old Hooks**
   - Remove obsolete subscriptions or handlers watching `listeningForVoice`, `aiSpeaking`, etc., and replace their usage with `isListening` where appropriate.
   - Verify no other UI element relies on the removed streams; refactor them if necessary.

6. **Validate In-App**
   - Start a fresh session and confirm the animation starts right after the welcome TTS when `isListening` becomes true.
   - Switch to chat and back; confirm the animation pauses/resumes purely based on `isListening`.
   - Run through a normal voice conversation to ensure the animation stays in sync whenever the mic is active.
