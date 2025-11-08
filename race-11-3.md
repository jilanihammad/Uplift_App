# Race 11/3 Fix Plan

1. Inspect current entrypoints in `lib/services/auto_listening_coordinator.dart` (`_startListening()` and `_startListeningAfterDelay()`) and confirm their call sites and existing guards.
2. Add a single guarded helper (e.g., `_beginListeningIfAllowed({required String context, int? expectedGen})`) that:
   - Returns early if `expectedGen` is provided and does not match the current `_generation` (stale callback).
   - Checks `_ttsActive`, `_autoModeEnabled`, and ensures `_currentState` is either `AutoListeningState.idle` or `AutoListeningState.aiSpeaking`.
   - Logs specific block reasons (`TTS still active`, `auto mode disabled`, `invalid state`, `stale generation`).
   - Performs the state transition (`_updateState(AutoListeningState.listening)`) and calls `_executeListeningStart()` when allowed.
3. Refactor `_startListening()` and `_startListeningAfterDelay()` so they simply delegate to `_beginListeningIfAllowed`, passing distinct `context` strings (e.g., `'direct'` vs `'deferred'`) and retaining any existing scheduling/transition logic around the call.
4. Update debug logging in both methods (and the helper) so each start attempt reports the context and guard outcome; ensure no remaining code path starts VAD/recording without going through the helper.
5. Validate the change: run the welcome TTS flow, a chat→voice toggle, and inspect logs to confirm: (a) deferred starts are blocked while TTS is active, (b) the welcome completion re-arms listening cleanly, and (c) normal voice-mode toggles still re-enable listening after the three-second guard.
