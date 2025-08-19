# Improvements Plan for AI Therapist App

This document lists recommended actions to harden the app, prevent regressions, and improve perceived speed and reliability. Each item includes the rationale, expected impact, and concrete guidance for a new engineer.

## Quick summary (Top wins)
- Do not dispose app‑scoped singletons during session end; reset/stop instead
- Route enable/disable listening through Bloc events so state stays consistent
- Make the mic toggle fully reactive and guard re‑arming with `isMicEnabled`
- Align recording to mono 48 kHz to reduce resampling and file size
- Keep OPUS rollout behind a flag, with WAV fallback; sustain in‑memory playback
- Reduce noisy logs and avoid redundant wake‑lock toggles
- Remove vendored SDKs from git to speed everything up

---

## 1) Architecture & lifecycle

### 1.1 App‑scoped singletons: never dispose on session end
- Status: Completed (2025-08-15)
- **Problem**: Disposing app‑scoped services (e.g., `WebSocketAudioManager`, TTS) in session teardown marks them permanently disposed, breaking subsequent sessions.
- **Actions**:
  - In app‑scoped coordinators (e.g., `VoiceSessionCoordinator`), replace `dispose()` calls for shared services with:
    - End active session / disconnect
    - `stopAudio()` / `reset...()` as appropriate
  - Only dispose these services on app shutdown.
- **Files**: `lib/services/voice_session_coordinator.dart`, service DI modules.
- **Impact**: Prevents "has been disposed" bad states on second session; reduces cold‑start overhead.

### 1.2 Single ownership of session teardown
- Status: Completed (2025-08-15)
- **Problem**: Multiple layers attempt to stop audio/VAD/recording, yielding duplicate "already stopped" logs and edge timing issues.
- **Actions**:
  - Centralize teardown in `VoiceSessionBloc` end‐session handler.
  - Call idempotent methods (`tryStopRecording()`, `DisableAutoMode`) once; avoid calling service-level stops from multiple places.
- **Files**: `lib/blocs/voice_session_bloc.dart`, `lib/services/session_scope_manager.dart`.
- **Impact**: Simpler teardown, fewer races and warnings.

---

## 2) State consistency (Bloc ↔ services)

### 2.1 Route listening state through Bloc events
- Status: Completed (2025-08-15)
- **Problem**: Bloc state (`isAutoListeningEnabled`) can drift from `AutoListeningCoordinator.autoModeEnabled` when services are called directly.
- **Actions**:
  - Use `EnableAutoMode` and `DisableAutoMode` events so the Bloc updates its own state and instructs the service/coordinator.
  - Avoid calling `voiceService.disableAutoMode()` directly from random places; dispatch the event instead.
- **Files**: `lib/blocs/voice_session_bloc.dart` (handlers for `EnableAutoMode`/`DisableAutoMode`).
- **Impact**: Eliminates false "already active, skipping" paths that block re-arming.

### 2.2 Mic toggle (mute/unmute) behavior
- Status: Completed (2025-08-15)
- **Problem**: Unmute may not re‑enable auto mode due to stale flags or in‑flight TTS.
- **Actions**:
  - On mute: `add(DisableAutoMode())`, then `tryStopRecording()` (idempotent). Bloc sets `isAutoListeningEnabled=false`.
  - On unmute: If voice mode & TTS idle & not recording → `add(EnableAutoMode())`. Else set a defer flag so re‑arm happens after TTS completion.
  - In TTS completion handler, re‑check `state.isMicEnabled` before enabling.
- **Files**: `lib/screens/widgets/voice_controls_panel.dart` (button), `lib/blocs/voice_session_bloc.dart`.
- **Impact**: Predictable mic UX without races.

---

## 3) Concurrency & timing

### 3.1 Atomic reset gating
- Status: Completed (2025-08-15)
- **Problem**: Mid‑reset TTS/playback starts can be canceled or misrouted.
- **Actions**:
  - Preserve the existing "atomic reset completer" pattern around audio resets (player + TTS + VAD). Await before starting TTS (e.g., welcome message).
- **Files**: `lib/blocs/voice_session_bloc.dart` (atomic reset guard).
- **Impact**: Eliminates "request cancelled by reset" problems.

### 3.2 VAD worker stop timeout (500ms)
- **Context**: You already handle timeout gracefully.
- **Optional tuning**:
  - Check recording state first; skip waiting if not recording.
  - If repeated, consider shortening the await path for known idle states.
- **Files**: `lib/services/enhanced_vad_manager.dart`, `lib/services/auto_listening_coordinator.dart`.
- **Impact**: Fewer timeout logs; slightly faster teardown.

---

## 4) Audio pipeline & streaming

### 4.1 WAV header modification warnings
- Status: Completed (2025-08-15)
- **Observation**: Media3 WavExtractor warning appears, but playback is fine.
- **Actions**:
  - Keep support for streaming‑friendly headers untouched by default (no rewrite) to reduce warnings.
  - If some devices regress, gate the rewrite behind a feature flag and enable only for those devices.
- **Files**: `lib/services/simple_tts_service.dart` (streaming path and header logic), `AudioFormatNegotiator`.
- **Impact**: Cleaner logs, unchanged audio behavior.

### 4.2 OPUS rollout with WAV fallback
- **Goal**: Better bandwidth and startup latency.
- **Actions**:
  - Use the existing rollout knobs (e.g., `opusRolloutPercentage`) to enable OPUS for a subset of devices.
  - Keep WAV as fallback on header/format errors.
  - Collect TTFB and completion metrics per format.
- **Files**: `AudioFormatNegotiator`, `simple_tts_service.dart`.
- **Impact**: Gradual speed/perf improvements with low risk.

### 4.3 In‑memory playback as default
- Status: Completed (pre-existing; confirmed on 2025-08-15)
- **Status**: Already implemented; keep it the default path.
- **Actions**:
  - Fall back to file‑based playback only on errors.
  - Ensure temp file cleanup is consistent (handled in `AudioPlayerManager`).
- **Files**: `simple_tts_service.dart`, `audio_player_manager.dart`.
- **Impact**: Lower I/O, faster playback start.

---

## 5) Recording configuration

### 5.1 Align recording settings to RNNoise
- Status: Completed (2025-08-19)
- **Problem**: RNNoise operates at 48 kHz; recording paths sometimes use 44.1 kHz and 2 channels.
- **Actions**:
  - Prefer mono 48 kHz for mic capture to avoid resampling; reduces CPU and file size.
  - If device constraints force 44.1 kHz, do a single resample step in one place rather than multiple implicit conversions.
- **Files**: `lib/services/audio_recording_service.dart`, `lib/services/recording_manager.dart`, `enhanced_vad_manager.dart`.
- **Impact**: Less CPU, lower latency, smaller files.

---

## 6) WebSocket & networking

### 6.1 Connection management
- **Guidelines**:
  - Close WS session on session end; reuse connection on quick restarts when viable to reduce dial‑ups.
  - Backoff reconnection on repeated failures.
  - Keep keep‑alive pings; update `lastUsed` timestamps when reusing channels.
- **Files**: `lib/services/websocket_audio_manager.dart`.
- **Impact**: More robust streaming; lower connection overhead.

---

## 7) UI & state wiring

### 7.1 Mic button reactivity
- **Problem**: Using `context.read(...).state.isMicEnabled` won’t rebuild the button on state changes.
- **Action**: Drive the mic icon with a `BlocSelector` or `BlocBuilder` keyed to `isMicEnabled`.
- **Files**: `lib/screens/widgets/voice_controls_panel.dart`.
- **Impact**: Correct, responsive toggle UI.

### 7.2 Wake‑lock de‑duplication
- Status: Completed (2025-08-15)
- **Status**: You added async checks to avoid redundant toggles; keep this pattern.
- **Files**: `lib/screens/chat_screen.dart`.
- **Impact**: Less UI/framework churn.

---

## 8) Logging & performance hygiene

### 8.1 Throttle or suppress noisy logs
- **Targets**:
  - Duplicate state changes in `AudioPlayerManager` (already muted)
  - Unified TTS logs while auto mode is disabled (already reduced)
  - Firebase App Check placeholder errors (configure/suppress in release)
- **Actions**:
  - Use throttled debug prints (`debugPrintThrottledCustom`) or lower log level.
  - Gate extremely verbose logs behind a debug flag.
- **Impact**: Lower CPU/battery usage; cleaner logs.

---

## 9) Testing & observability

### 9.1 Add characterization tests for lifecycles
- **Scenarios**:
  - Session end/start loops without disposing app‑scoped singletons
  - Mic mute/unmute while TTS is playing; re‑arm after TTS completion only if mic enabled
  - VAD worker stop timeout path (ensures app stays responsive)
- **Frameworks**: Flutter unit tests for Bloc; integration tests for key flows.

### 9.2 Metrics & alerts
- **Keep**: TTS TTFB and playback duration metrics.
- **Add**: Alerting for repeated reconnection failures or repeated VAD timeouts.

---

## 10) Repository hygiene

### 10.1 Remove vendored SDKs / binaries from git
- **Problem**: Large vendor trees (`flutter/`, `google-cloud-sdk/`) in repo slow down every operation.
- **Actions**:
  - Move them out of the repo; install via tooling/scripts.
  - Add `.gitignore` rules for SDKs, build artifacts, and credentials.
- **Impact**: Faster clone, CI, and local dev.

---

## 11) Security & privacy

### 11.1 Secrets handling
- **Problem**: Plaintext key files (e.g., "Groq API key.txt") risk accidental commits.
- **Actions**:
  - Move secrets to `.env` files or OS keychains; add to `.gitignore`.
  - Mask secrets in logs; never output keys or headers.
- **Impact**: Reduced risk of key leakage.

---

## Rollout plan (safe sequence)
1) State & lifecycle (Sections 1–2): fix singleton disposal, route auto‑mode through Bloc, finalize mic toggle behavior
2) Logging cleanups (Section 8): mute noisy logs in debug, suppress in release
3) Recording alignment (Section 5): switch to 48 kHz mono where supported
4) Audio pipeline tweaks (Section 4): keep WAV default; begin OPUS rollout at low percentage; monitor metrics
5) Repo hygiene & secrets (Sections 10–11)

---

## References (key files)
- Bloc: `lib/blocs/voice_session_bloc.dart`, `lib/blocs/voice_session_state.dart`, `lib/blocs/voice_session_event.dart`
- Coordinators & services: `lib/services/voice_session_coordinator.dart`, `lib/services/auto_listening_coordinator.dart`, `lib/services/audio_recording_service.dart`, `lib/services/recording_manager.dart`, `lib/services/simple_tts_service.dart`, `lib/services/websocket_audio_manager.dart`, `lib/services/audio_player_manager.dart`
- UI: `lib/screens/widgets/voice_controls_panel.dart`, `lib/screens/chat_screen.dart`
