# Gemini Live Duplex Integration Plan

Goal: allow the app to run Gemini Live in full duplex mode (audio in → audio out) while preserving the existing three-stage pipeline for other providers. The mode should remain configurable via `llm_config.py` so we can switch between Gemini duplex and the traditional transcription + LLM + TTS stack without code changes.

## 1. Configuration Toggle
- [x] Add `GOOGLE_LIVE_MODE` flag in `llm_config.py` with `tts_only`/`duplex` options.
- [x] Propagate the flag through `LLMManager` so the live pipeline activates correctly.

## 2. Backend Architecture
### a. Session Lifecycle
- [x] Create `GeminiLiveSession` in `llm_manager.py` wrapping `genai.Client.aio.live.connect()`.
- [x] Maintain bidirectional audio exchange and surface Gemini text events to the rest of the stack.
- [ ] Implement heartbeat/reconnect handling and zombie-session detection (still pending; currently we just close on failure).
- [ ] Integrate per-user context tracking with analytics/memory layers (session metadata is available but not persisted/logged yet).

### b. Audio Input Handling
- [x] Add `/ws/gemini/live` WebSocket endpoint for microphone streaming.
- [x] Forward incoming PCM chunks to `GeminiLiveSession.send_audio_chunk(...)` and tie session teardown to socket lifecycle.
- [ ] Wire session/user IDs into analytics for full observability (pending alongside lifecycle analytics work).

### c. Audio Output Streaming
- [x] Stream Gemini `inline_data` responses back over the same WebSocket as binary frames.
- [x] Emit structured text events (`model_text`, `turn_complete`) for UI consumption.
- [ ] Normalize audio formats so Gemini Opus output is converted (or correctly flagged) before playback; current implementation assumes WAV and will mislabel Opus streams.

### d. Text/History Integration
- [x] Map Gemini Live textual outputs to the app’s message model and expose incremental/final updates via bloc events.
- [x] Add `GEMINI_LIVE_INCREMENTAL_TRANSCRIPTS` guardrail flag.
- [ ] Persist Gemini transcripts to memory/analytics like the legacy path (pending).

### e. Fallback / Hybrid Mode
- [ ] Implement automatic fallback to the legacy Groq + LLM + TTS chain when the Live session fails (pending; errors surface but do not re-route today).

## 3. Frontend Architecture
- [x] When duplex mode is enabled, `VoiceSessionBloc` / `VoiceService` connect to `/ws/gemini/live` and stream microphone PCM in real time.
- [x] Replace transcription polling with Gemini Live text events and update chat UI incrementally.
- [x] Feed Gemini audio chunks into the existing `LiveTtsAudioSource` / jitter-buffer path for playback.
- [x] Attach backend-provided session IDs to bloc state for debugging.
- [ ] Handle hybrid fallback flows in the bloc/service so legacy pipeline resumes if Gemini disconnects unexpectedly.
- [ ] Update `LiveTtsAudioSource` to accept multiple MIME types (or expect normalized WAV) to prevent format mismatches when switching providers.

## 4. Error Handling & Recovery
- [ ] Add reconnection logic and user-facing retry prompts when the live socket drops.
- [ ] Record analytics/metrics for session start/stop, audio bytes, and latency for Gemini Live.
- [ ] Log transcript mismatches/duplicates similar to Groq pipeline and track zombie sessions.

## 5. Testing Strategy
- [x] Unit tests for `GeminiLiveSession` covering audio/text event parsing and send/close mechanics.
- [ ] Integration tests covering the full WebSocket round-trip (`streaming_pipeline` harness) once fallback/recovery is in place.
- [ ] Manual QA scripts for mic/speaker/chat edge cases (still pending formal write-up/execution).

## 6. Rollout Steps
1. ✅ Introduce the config flag and underlying session class.
2. ✅ Implement the new WebSocket endpoint and mobile streaming logic (behind the flag).
3. ✅ Integrate with the frontend so QA can opt into Gemini Live duplex mode.
4. ☐ Add monitoring dashboards for latency/errors (waiting on analytics hooks).
5. ☐ Flip the default to `duplex` for Gemini Live users after validation.

This approach keeps the legacy transcription/LLM/TTS stack untouched for OpenAI/Groq while letting us opt into Gemini Live’s native speech interface by flipping a single config value. Checklist items marked ☐ remain to be completed before the feature can graduate from gated QA to broader rollout.
