# Mid-Session Chat→Voice Plan

## Goal
Prevent duplicate auto-mode activation when switching from chat back to voice mid-session by treating that flow separately from the initial session start (which still needs welcome-TTS guards).

## Steps

1. **Confirm Entry Points**
   - `_prepareForVoiceMode` (voice_session_bloc.dart) is the only place that calls `voiceService.enableAutoMode()` during mode switches.
   - `AutoListeningCoordinator` now owns the "AI silent" guard; the bloc no longer tracks deferred state.

2. **Coordinator Guard Behavior**
   - `AutoListeningCoordinator` watches `_aiAudioActiveStream = combineLatest(TTS speaking, AudioPlayerManager.isPlaying)`.
   - When auto mode is requested while `_aiAudioActive` is true, the coordinator sets `_autoModeEnabledDuringAiAudio`, enters `aiSpeaking`, and refuses every listening/recording entry point until audio clears.
   - Once `_aiAudioActive` flips false, it automatically retries `_startListeningAfterDelay()` (unless auto mode was disabled in between). A 10-second guard timer prevents the mic from staying muted forever.
   - The entire guard can be disabled via `FeatureFlags.coordinatorVoiceGuardEnabled` for safe rollout.

3. **Coordinator States & Transitions**
   - `idle`: Maya is silent and auto mode isn’t recording; safe to start listening.
   - `aiSpeaking`: Maya is speaking or audio playback is active. Coordinator stops VAD/recording and waits for `_aiAudioActive` to clear before transitioning back to `idle/listening`.
   - `listening`: VAD is active and the mic is open; transitions to `userSpeaking` when VAD detects speech.
   - `userSpeaking`: User speech detected, recording in progress; transitions to `processing` when speech ends.
   - `processing`: Coordinator is processing the recorded audio; when complete it returns to `idle` and schedules `_startListeningAfterDelay()` if auto mode remains enabled.
   - `listeningForVoice`: Transitional state while VAD spins up; if it gets stuck for >1s, state resets to `idle` and retries.

3. **Bloc Responsibilities**
   - Mid-session switch simply calls `voiceService.enableAutoMode()` (after stopping playback) and lets the coordinator decide when to listen.
   - Initial welcome flow still uses `_welcomeAutoModeArmed`; once the greeting finishes we dispatch `EnableAutoMode` once and rely on the coordinator to delay if TTS/audio is still active.
   - Chat mode sets `isAutoListeningEnabled = false` and disables auto mode via the service.

4. **Diagnostics & Safety Nets**
   - Logs identify when switches happen and whether `EnableAutoMode` succeeds.
   - Coordinator logs when AI audio becomes active/inactive and when the timeout fires.
   - Manual QA can toggle the guard via the debug drawer.

5. **Validate Scenarios**
   - Initial session start: greeting still gates listening until TTS completes.
   - Chat→voice while idle: auto mode enables immediately; coordinator confirms AI audio is silent and starts listening.
   - Chat→voice while Maya is still talking: coordinator remains in `aiSpeaking` until `_aiAudioActive` clears, then listening restarts exactly once.
   - App lifecycle: backgrounding mid-TTS keeps `_aiAudioActive` true, so listening won't resume until the app returns and audio clears.



## Fixes Attempted But Were Unsuccessful Or Incorrect
1. **Always Wait For Playback Start (v1)**
   - Forced every mid-session switch to set `requiresPlaybackIdle = true`, assuming the AI always had audio pending.
   - Result: listening never re-enabled when no TTS clip existed, leaving the mic off indefinitely.
2. **Conditional Idle Wait Without Queue Awareness (v1.5)**
   - Added conditional checks for `isAiSpeaking`, `isTtsActive`, and `AudioPlayerManager` state, plus a 2 s timeout.
   - Missed the real signal (chat-generated AI responses), so switches with pending chat replies still reopened listening too early and cut off the response.
3. **Replay Chat Replies Via TTS (v2)**
   - Queued text-mode AI responses and synthesized them locally during the next voice-mode switch.
   - Users already saw the reply, so replaying it is redundant and keeps `EnableAutoMode` deferred for no reason; listening re-armed far too late.

## Correction v3
1. **Single Source of Truth**
   - AutoListeningCoordinator enforces the "AI silent" rule using `_aiAudioActiveStream`. When auto mode is requested during AI playback, it stays in `aiSpeaking` and retries once the stream reports idle.
2. **Simple Bloc Flow**
   - `_prepareForVoiceMode` calls `voiceService.enableAutoMode()` once per switch. The coordinator decides when to start listening; the bloc only handles the welcome guard via `_welcomeAutoModeArmed`.
3. **Safety Nets**
   - 10 s timeout in the coordinator logs a warning and forces listening if AI audio never clears.
   - Feature flag (`coordinatorVoiceGuardEnabled`) allows instant rollback during rollout/testing.
4. **Validation Focus**
   - Chat→voice while idle: coordinator sees `_aiAudioActive = false` and starts listening immediately.
   - Chat→voice while TTS playing: coordinator remains in `aiSpeaking` until `_aiAudioActive` clears, then restarts listening once.
   - Lifecycle and regression tests still pending (see MajorRefactor.md work item #6).
