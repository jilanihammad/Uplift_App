# TTS Playback Race Condition Guard

## 1. Background
- Issue: When a new TTS stream starts before the previous one finishes, `AudioPlayerManager` reuses the same player/audio source.
- Leftover callbacks from the previous stream fire after the new playback spins up.
- Those stale completions call `VoiceService.updateTTSSpeakingState(false)`, resetting state while the new stream is still active.
- Result: VAD/listening flips out of sync; UI sometimes restarts playback or ignores transitions.

## 2. High-Level Solution
Introduce a monotonically increasing **playback token** that identifies the active TTS stream. All player callbacks must present the current token before they touch session state. Stale callbacks are silently ignored.

## 3. Implementation Steps

### 3.1 Inspect Current Flow
- Files: `lib/services/audio_player_manager.dart`, `lib/services/voice_service.dart`, `lib/services/live_tts_audio_source.dart`.
- Identify where playback starts (`startLiveTtsPlayback`, `playLiveStream`) and where completions propagate (`_handleProcessingState`, `_onPlayerComplete`, `LiveTtsAudioSource` delegates).

### 3.2 Add Playback Token Tracking
1. Add to `AudioPlayerManager`:
   ```dart
   int _activePlaybackToken = 0;
   int _bumpPlaybackToken() => ++_activePlaybackToken;
   ```
2. When starting a new live stream, call `_bumpPlaybackToken()` and capture the returned token (`final playbackToken = _bumpPlaybackToken();`). Store it alongside the request ID (map or struct).
3. Log the token for observability (`logger.debug("[TTS] Promoted playback token $playbackToken for $streamId")`).

### 3.3 Thread Token Through Player Callbacks
- When registering listeners (processing state, play/pause, completion futures), close over `playbackToken`.
- At the top of each callback:
  ```dart
  if (playbackToken != _activePlaybackToken) {
    logger.debug('[TTS] Ignoring stale callback for token $playbackToken');
    return;
  }
  ```
- Only the active token continues with existing logic (state updates, VoiceService calls, resource disposal).

### 3.4 Update `LiveTtsAudioSource`
- Extend `playFromSource` / `attach` to accept the token.
- Inside source-level callbacks (`onPlaybackCompleted`, `onStreamClosed`), forward the token to `AudioPlayerManager`. Perform the same equality check before invoking higher-level handlers.

### 3.5 Guard `VoiceService`
1. Track the last accepted token:
   ```dart
   int? _currentPlaybackToken;
   ```
2. Add an optional parameter to `updateTTSSpeakingState`:
   ```dart
   Future<void> updateTTSSpeakingState(bool isSpeaking, {int? playbackToken})
   ```
3. At entry:
   ```dart
   if (playbackToken != null && playbackToken != _currentPlaybackToken) {
     logger.debug('[VoiceService] Ignoring stale state update for token $playbackToken');
     return;
   }
   if (isSpeaking) _currentPlaybackToken = playbackToken;
   ```
4. Ensure `AudioPlayerManager` always passes the active token; manual UI toggles can omit it (treated as always valid).

### 3.6 Update Call Sites & Tests
- Replace existing `updateTTSSpeakingState(...)` calls in `AudioPlayerManager` with `updateTTSSpeakingState(..., playbackToken: playbackToken)`.
- Adjust or add tests to assert that:
  - The first stream’s completion does nothing once a second stream is active.
  - The current stream still flips state correctly.
- Optional: Add an integration test to simulate overlapping TTS responses using mocks.

### 3.7 Validate
1. `flutter test` (or targeted service tests) to ensure no regressions.
2. Manual QA: trigger back-to-back prompts to generate overlapping TTS responses. Confirm logs show stale callbacks ignored and the UI remains responsive.
3. Verify mic interruptions still work: start a stream, stop it manually, ensure the token guard accepts the true completion and resumes listening.

## 4. Optional Enhancements
- Add a `Duration` timeout for tokens so they auto-reset if the player hard-crashes without sending completion.
- Expose the current token in debug logs or diagnostics UI to aid troubleshooting.
- Combine with a playback lock if additional serialization is ever needed; tokens remain the primary guard.

## 5. Rollout Checklist
1. Implement guards and run tests.
2. Smoke-test on device (debug build).
3. Build a release APK/AAB and re-test quick overlap scenarios.
4. Monitor TTS completion logs in staging for any remaining “state already false” messages—there should be none.
