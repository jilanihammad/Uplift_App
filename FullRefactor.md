# Full Refactor Plan – Voice Pipeline Stabilization

This document lays out the end-to-end plan to eliminate the persisting race conditions by restructuring the voice pipeline into a single authoritative controller, decomposing the legacy singleton services, and simplifying state ownership. Execute the phases sequentially; each phase has clear success criteria, risks, and mitigations.

---

## Guiding Principles
1. **Single Source of Truth** – The voice pipeline must expose one authoritative state machine; UI and services consume it rather than duplicating flags.
2. **Per-Session Isolation** – All audio/LLM resources are scoped to a session instance; no more global singletons with cross-session state.
3. **Deterministic Transitions** – Every transition (Listening → Speaking, etc.) is event-driven with logged guards, not implicit timers sprinkled across layers.
4. **Progressive Enablement** – Each phase keeps the app functional, guarded by feature flags until validated.

---

## Phase 0 – Preparation & Safety Net ✅
1. **Freeze Current Behavior**
   - Snapshot logs for the known race flows (voice↔chat toggles, mic mute, welcome TTS) so you can compare later.
   - Capture baseline test runs: `flutter test`, targeted integration tests, backend smoke tests.
2. **Document Entry Points**
   - Trace who calls `enableAutoMode`, `disableAutoMode`, `_startListening`, `_resumeDeferredVoiceAutoMode` and list them in a quick table.
3. **Feature Flag Hook**
   - Add a top-level flag `voicePipelineControllerEnabled` in `FeatureFlags` so new code can be rolled out gradually.

**Risks**: Missing a critical entry point before refactor.
**Mitigation**: Log every AutoListeningCoordinator public call with stack traces temporarily; review before continuing.

---

## Phase 1 – Introduce `VoicePipelineController` ✅
**Goal**: Encapsulate the voice session finite-state machine (FSM) without changing current behavior.

> **Scope note**: Treat this controller as an evolution of the existing `VoiceSessionCoordinator`. Reuse its lifecycle hooks and streams where possible so we do **not** end up with two orchestration layers. The intent is to consolidate behavior under the new controller and later delete the coordinator once feature-flag rollout succeeds.

### 1.1 Create Controller Skeleton
- File: `lib/services/pipeline/voice_pipeline_controller.dart`.
- Expose:
  ```dart
  enum VoicePipelinePhase { idle, greeting, listening, recording, transcribing, speaking, cooldown }

  class VoicePipelineSnapshot {
    final VoicePipelinePhase phase;
    final bool micMuted;
    final bool autoModeEnabled;
    final int generation;
    const VoicePipelineSnapshot({...});
  }

  class VoicePipelineController {
    final Stream<VoicePipelineSnapshot> snapshots;
    VoicePipelineSnapshot get current;

    Future<void> startSession(VoiceSessionConfig config);
    Future<void> enterGreeting(AudioPlan plan);
    Future<void> armListening({String context});
    Future<void> onUserSpeechCaptured(String path);
    Future<void> onAiResponse(Stream<AudioChunk> chunkStream);
    Future<void> teardown();
  }
  ```
Internally, keep a `StateMachine<VoicePipelinePhase>` that enforces valid transitions.

### 1.2 Bridge Existing Services
- Inject the existing `VoiceService`, `AutoListeningCoordinator`, `AudioPlayerManager`, `RecordingManager`, and `VoiceSessionCoordinator` (for transition helpers) into the controller constructor. The controller simply proxies to them while emitting snapshots; no new orchestration layer should be created.
- Add guard methods (`_ensurePhase(expected)`) to serialize TTS start/stop vs listening restarts.

### 1.3 Concurrency Model
- All public controller methods enqueue work onto a dedicated single-threaded executor (the bloc’s event loop is sufficient) to guarantee in-order processing.
- Asynchronous callbacks (TTS stream events, recorder notifications) must `add` a controller task instead of mutating state directly; the controller serializes them and increments a `generation` counter when a phase completes.
- Document this sequencing with a quick diagram (welcome greeting → speech capture → AI response) so future contributors understand where races are ruled out.

### 1.4 Wire Logging & Metrics
- Every transition logs `prevPhase -> nextPhase (reason)` so future debugging points to the controller.

**Risks**: Controller accidentally duplicates state causing event storms.
**Mitigation**: Initially pipe controller snapshots from the existing bloc state (read-only) while `voicePipelineControllerEnabled` is false; no writes happen yet.

---

## Phase 2 – BLoC Integration (Read-Only → Authoritative) ✅
**Goal**: `VoiceSessionBloc` reads pipeline state instead of tracking its own parallel flags.

### 2.1 Replace Derived Flags
- Subscribe to `VoicePipelineController.snapshots` inside the bloc constructor.
- Map snapshot fields to UI state:
  ```dart
  _pipelineSub = pipeline.snapshots.listen((snap) {
    add(UpdatePipelineState(snapshot: snap));
  });
  ```
- Handler `UpdatePipelineState` sets `isListening`, `isRecording`, `ttsStatus`, `isMicControlGuarded`, etc., based purely on the snapshot.

### 2.2 Remove Redundant Fields
- Delete `_micControlGuardDepth`, `_welcomeAutoModeArmed`, `_modeGeneration` once equivalent info comes from the controller.
- `VoiceSessionState` shrinks: keep only UI-specific booleans (dialogs, timers) and reference `snap.phase` for pipeline data.

### 2.3 UI Wiring
- `VoiceControlsPanel` now consumes `snapshot.micMuted` and `snapshot.phase` to show availability; no more ad-hoc guards.

### 2.4 Exit Criteria
- Feature flag on/off produces identical metrics for: (a) mic-toggle latency, (b) time from AI speech end to listening resume, (c) number of unexpected auto-mode disables (tracked via telemetry counter added in Phase 0).
- Integration tests `integration_test/voice_session_toggle_test.dart` and `..._welcome_test.dart` pass with the flag in both positions.

**Risks**: Event ordering differences could regress UI (e.g., amplitude updates).
**Mitigation**: During rollout, keep legacy flags in state but mark them `@deprecated` and assert they match the snapshot to detect drifts.

---

## Phase 3 – Break Apart `VoiceService` ✅
**Goal**: Replace the singleton with scoped components and inject them into the controller without exploding the surface area.

### 3.1 Define Interfaces
- Start with a simple `VoicePipelineDependencies` struct that holds the existing concrete classes:
  ```dart
  class VoicePipelineDependencies {
    final RecordingManager recording;
    final AudioPlayerManager playback;
    final TherapyService therapy;
    final AutoListeningCoordinator autoListening;
  }
  ```
- Once behavior is stable, graduate those fields into interfaces for longer-term flexibility:
  - `lib/services/voice_pipeline/audio_capture.dart`
  ```dart
  abstract class AudioCapture {
    Stream<AmplitudeSample> get amplitude;
    Future<String> startRecording();
    Future<void> stopRecording();
  }
  ```
- `lib/services/voice_pipeline/audio_playback.dart`
  ```dart
  abstract class AudioPlayback {
    Stream<PlaybackEvent> get events;
    Future<int> play(TtsStream stream);
    Future<void> stop(int token);
  }
  ```
- `lib/services/voice_pipeline/ai_gateway.dart`
  ```dart
  abstract class AiGateway {
    Future<TtsStream> requestResponse(Transcript transcript);
  }
  ```

### 3.2 Provide Implementations
- Wrap existing `RecordingManager`, `AudioPlayerManager`, `TherapyService` logic into these implementations.
- Remove global static `VoiceService._instance`; provide a factory that builds a scoped controller bundle per session.

### 3.3 Dependency Injection
- Update `service_locator.dart` so `VoiceSessionBloc` asks for a `VoicePipelineControllerFactory` instead of `VoiceService`. During the transition the factory can still wrap the legacy singleton, but per-session instantiation becomes the only public API.

**Risks**: Session leaks (unreleased audio resources).
**Mitigation**: `VoicePipelineController.teardown()` disposes the concrete implementations; add `debugPrint` warnings if not called.

---

## Phase 4 – Ownership of Mic & Auto-Mode ✅ (controller path live; timing polish ongoing)
**Goal**: Controller solely manages mic mute, auto-mode enablement, and guards.

### 4.1 Remove Direct Calls
- Delete bloc/UI calls to `voiceService.enable/disableAutoMode` and `_autoListeningCoordinator` APIs.
- The controller’s transitions (`enterGreeting`, `armListening`, `cooldown`) internally call the capture/playback interfaces as needed.

### 4.2 Simplify Toggle Event
- `ToggleMicMute` now sends `pipeline.toggleMic()`.
- Controller implementation:
  ```dart
  Future<void> toggleMic() async {
    final nextMuted = !_state.micMuted;
    _state = _state.copyWith(micMuted: nextMuted);
    if (nextMuted) {
      await _capture.stopRecording();
      await _autoMode.disable();
    } else {
      await _autoMode.enable();
      await armListening(context: 'user-unmute');
    }
    _emit();
  }
  ```

**Risks**: Auto-mode edge cases (e.g., welcome guard) reappear if not encoded.
**Mitigation**: Represent such guards as explicit pipeline phases like `cooldown` with timers managed by the controller instead of free-form booleans.

---

## Phase 5 – Retire Legacy Components ⏳ (in progress)
**Goal**: Delete unused code paths so future fixes stay simple.

1. Remove `AutoListeningCoordinator` once its logic is absorbed.
2. Delete `voice_service.dart` except for the minimal DI wrapper that builds the new sub-services.
3. Prune documentation files describing phased migrations (Phase 6, etc.) and replace with a single diagram of the new pipeline.

**Risks**: Hidden dependencies (tests/mocks) referencing old classes.
**Mitigation**: Grep for class names before deletion; provide migration shims exporting typedefs if third-party code references them.

---

## Phase 6 – Testing & Rollout ⏳ (pending)
1. **Unit Tests**
   - Add FSM tests verifying illegal transitions throw.
   - Mocked capture/playback tests for timing (welcome message, repeated toggles).
2. **Integration Tests**
   - Extend `integration_test/voice_session_*` to cover: rapid chat↔voice toggles, mic mute/unmute while AI speaks, and welcome TTS completion.
3. **Manual soak**
   - Run `soak_test.js` or equivalent scenario for 30-minute session with voice pipeline enabled.
4. **Feature Flag Rollout & Telemetry**
   - Ship with `voicePipelineControllerEnabled = false` by default.
   - Emit telemetry for every `VoicePipelinePhase` transition (duration, guard hit counts) and mic-toggle latency so parity can be measured.
   - Toggle on internal builds, monitor the telemetry dashboards plus crash/error rates, then enable for everyone once stable.

**Risks**: New regressions in non-primary platforms (desktop, web).
**Mitigation**: Keep the old path hidden behind the flag for one release; maintain telemetry counters comparing both implementations.

---

## Risk Matrix (Summary)
| Phase | Risk | Mitigation |
|-------|------|------------|
| 0 | Missed entry points causing regressions | Instrument and review logs before refactor |
| 1 | Controller duplicates state causing loops | Start in passive mirror mode under feature flag |
| 2 | UI desync due to new event ordering | Keep legacy fields temporarily and assert parity |
| 3 | Resource leaks from new DI | Add teardown asserts and integration tests |
| 4 | Mic/auto-mode edge cases resurface | Model guards as explicit phases, not ad-hoc timers |
| 5 | Deleting classes breaks tests/tools | Search references, add shims until consumers migrate |
| 6 | Platform-specific regressions | Stage rollout via feature flag and gather metrics |

---

## Deliverables Checklist
- [x] `VoicePipelineController` + snapshot stream
- [x] Bloc wired to controller snapshots
- [x] Audio/AI services split into injectables
- [x] Mic/auto-mode logic centralized (controller-driven)
- [ ] Legacy coordinators removed
- [ ] Comprehensive test suite + feature-flag rollout plan

Follow this plan to converge on a deterministic voice pipeline architecture and permanently eliminate the recurring race conditions.
