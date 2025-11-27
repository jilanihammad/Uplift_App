# Voice Pipeline Takeover Plan

## Overview
We must hand full responsibility for recording, VAD, mic mute, and auto-mode rearm to the `VoicePipelineController` when `voicePipelineControllerAuthoritative` is true. The legacy `AutoListeningCoordinator` must be completely bypassed in that mode. This plan is broken into five stages; complete each in order and verify before moving on.

---

## Stage 0 – Safety Net
1. Ensure `voicePipelineControllerAuthoritative` flag exists and can be flipped without a rebuild (`FeatureFlags`).
2. Add a `debugPrint` banner during bloc initialization showing which path is active so logs are unambiguous.
3. Confirm we still have the legacy callbacks wired (`_wireAutoListeningCallbacks`) even when authoritative is enabled; this serves as a fallback while Stage 1–3 changes land.

---

## Stage 1 – Gate Legacy Code Behind Flag
**Goal:** AutoListeningCoordinator runs only when the flag is false.

1. **Bloc Changes (`voice_session_bloc.dart`)**
   - Wrap `_wireAutoListeningCallbacks`, `_clearAutoListeningCallbacks`, `_syncEnhancedVADWorker`, `_safeVoiceService.initializeAutoListening`, `_safeVoiceService.resetAutoListening`, `_triggerListening()` legacy branch, etc., with `if (_useLegacyAutoListening)` checks.
   - During `_prepareForVoiceMode`, skip legacy resets (RNNoise, ALS reset) when `_pipelineControlsAutoMode` is true; only run `audioPlayerManager.lightweightReset()` and `resetTTSState()`.

2. **VoiceService Changes (`voice_service.dart`)**
   - Early-return from `initializeAutoListening()` and `resetAutoListening()` when `_controllerAutoModeEnabled` is true.
   - Ensure `setAutoListeningRecordingCallback`/`setAutoListeningTtsActivityStream` also do nothing in controller mode.

3. **VoiceSessionCoordinator (`voice_session_coordinator.dart`)**
   - Wrap `enableAutoMode()/disableAutoMode()` by checking `VoiceService.controllerAutoModeEnabled`; log and return if controller owns auto-mode.

4. **Feature Flag wiring**
   - Ensure `voicePipelineControllerAuthoritative` defaults to false in production builds until the takeover is complete; use `SharedPreferences` to flip it for internal QA.

**Verification:**
- With flag off, logs should still show `AutoListeningCoordinator` behavior (legacy fallback).
- With flag on, ALS reset logs should disappear; only controller logs remain.

---

## Stage 2 – Controller Owns Recording/VAD
**Goal:** Controller starts/stops recording, schedules VAD, and reports completion; ALS is not touched even in fallback.

1. **VoicePipelineController Interfaces**
   - Extend `AudioCapture` interface with `Future<void> startListening()`, `Future<void> stopListening()` (or explicit VAD hooks) if needed; or create a `VADController` abstraction.
   - Add methods on `VoicePipelineController`:
     - `Future<void> requestStartRecording({String reason})`
     - `Future<void> requestStopRecording({String reason})`
     - `Future<void> requestStartListening()` / `requestStopListening()` if VAD needs explicit control.
     - Ensure `_handleRecordingComplete` already emits snapshots and invokes bloc callback (done).

2. **RecordingManagerAudioCapture**
   - Wire through to actual `RecordingManager.startRecording()`/`stopRecording()`.
   - If VAD start/stop requires separate logic, add a `VadController` dependency to `VoicePipelineDependencies` (wrapping `EnhancedVADManager`).

3. **VoiceService**
   - When `_controllerRecordingEnabled` is true, skip `_audioRecordingService.startRecording()`/`stopRecording()` in the legacy path; rely on controller requests instead.
   - Expose `startControllerRecording()`/`stopControllerRecording()` helpers if the bloc still needs to call through VoiceService.

4. **Dependency Injection (`service_locator.dart` / `SessionScopeManager`)**
   - When building `VoicePipelineDependencies`, pass concrete implementations for new interfaces (capture, playback, AI gateway, VAD control).

5. **VoiceSessionBloc**
   - During `_prepareForVoiceMode`, after welcome guard, call `_voicePipelineController?.requestStartListening()` and `requestStartRecording()` instead of `_safeVoiceService.triggerListening()` when controller active.
   - On cleanup, call `requestStopRecording()` + `requestStopListening()` before tearing down the controller.

**Verification:**
- Controller logs should show explicit `requestStartRecording`/`requestStopRecording` transitions.
- ALS should not print any VAD or recording transitions when flag is on.

---

## Stage 3 – Bloc State & UI Simplification
**Goal:** Bloc state is driven entirely by controller snapshots; legacy ALS fields removed.

1. Remove `isAutoListeningEnabled`, `isVoicePipelineReady`, `_modeGeneration`, `_welcomeAutoModeArmed`, `_micControlGuardDepth` when `_pipelineControlsAutoMode` is true; eventually delete them entirely.
2. `_onVoicePipelineSnapshotUpdated` already maps phase → `isListening`/`isRecording`/`isAiSpeaking`; ensure UI widgets (voice controls, animations) rely solely on these fields.
3. Mic toggle (`_onToggleMicMute`) should call `VoicePipelineController.toggleMic()` and stop gating on legacy guard state.
4. Update unit/widget tests to reflect the new single source of truth.

**Verification:**
- Logs should no longer show `_guardMicControl` messages when controller active.
- VoiceControlsPanel should respond instantly to controller snapshots.

---

## Stage 4 – Delete Legacy Path (Controller Default)
**Goal:** Controller path becomes default; ALS code removed (or isolated behind deprecated flag).

1. Remove `AutoListeningCoordinator` import/usage from `VoiceService`, `VoiceSessionBloc`, `VoiceSessionCoordinator`, DI modules.
2. Delete `AutoListeningCoordinator` file if no longer referenced (keep only for fallback releases if necessary).
3. Remove the flag checks; controller becomes the only implementation.
4. Clean up documentation (`FullRefactor.md`, `voice_service_api_contract.md`, etc.) to reflect new architecture.

**Verification:**
- Search for `AutoListeningCoordinator` should return zero functional references (only historical docs/tests if needed).
- Smoke tests (welcome, chat↔voice, mute/unmute) should pass on controller-only path.

---

## Stage 5 – Validation & Cleanup
1. **Testing**
   - Run `flutter test` suites, especially voice integration tests.
   - Manual QA: chat→voice toggle, welcome, rapid mic toggles, long-session soak.
2. **Telemetry**
   - Confirm controller emits phase transitions and mic-toggle latency parity metrics.
   - Verify no `AutoListeningCoordinator` logs remain when the flag is on.
3. **Docs**
   - Update `takeover.md` (this doc) with completion status.
   - Refresh `FullRefactor.md` deliverables table.

---

## Appendix – File Touch List
- `lib/blocs/voice_session_bloc.dart`
- `lib/blocs/voice_session_state.dart`
- `lib/services/voice_service.dart`
- `lib/services/pipeline/voice_pipeline_controller.dart`
- `lib/services/pipeline/audio_capture.dart`
- `lib/services/pipeline/voice_pipeline_dependencies.dart`
- `lib/services/recording_manager.dart`
- `lib/services/voice_session_coordinator.dart`
- `lib/services/auto_listening_coordinator.dart` (delete/retire in Stage 4)
- `lib/di/service_locator.dart`
- `lib/screens/chat_screen.dart`
- `lib/utils/feature_flags.dart`
- Tests: `test/services/...`, `integration_test/...`

