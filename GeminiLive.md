# Gemini Live TTS Integration Playbook

Goal: introduce Google's **gemini-2.5-flash-native-audio-preview-09-2025** model as an optional third TTS backend. The existing OpenAI and Gemini REST paths must keep working with zero changes; flipping providers should remain a configuration-only task (`app/core/llm_config.py`).

---

## 1. Configuration scaffolding

**Files:** `app/core/llm_config.py`, `.env`, Cloud Run env vars, `/system/tts-config`

1. Extend the Google TTS entry so it tracks a `mode` (e.g. `"rest"` vs `"live"`). Add new defaults:
   ```python
   GOOGLE_TTS_MODEL = os.getenv("GOOGLE_TTS_MODEL", "gemini-2.5-flash-preview-tts")
   GOOGLE_TTS_MODE = os.getenv("GOOGLE_TTS_MODE", "rest")  # values: rest | live
   GOOGLE_LIVE_TTS_VOICE = os.getenv("GOOGLE_LIVE_TTS_VOICE", "kore")
   ```
2. In `LLMConfig.get_tts_config()`, include the mode plus the response mime type the client should expect. When `mode == "live"`, advertise the native format (`"audio/ogg; codecs=opus"`, or whatever Google returns).
3. `/system/tts-config` should now emit:
   ```json
   {
     "provider": "google",
     "model": "gemini-2.5-flash-native-audio-preview-09-2025",
     "mode": "live",
     "voice": "kore",
     "mime_type": "audio/ogg; codecs=opus",
     "sample_rate_hz": 24000,
     "supports_streaming": true
   }
   ```
   The mobile app uses this payload to pick a decoder without a code change.

---

## 2. Backend: Live API transport

**Files:** `app/services/llm_manager.py`, possibly `requirements.txt`

1. Keep the existing `_google_stream_tts_chunks` for REST. Add a sibling `_google_live_stream_tts_chunks` that:
   - Creates a `google.genai.live.Client` (or `client.live.*` helper) with the same API key.
   - Starts a live session using `gemini-2.5-flash-native-audio-preview-09-2025` and sends the prompt as the first request (`input.text`, `voice_config`, etc.).
   - Listens for `OutputAudio` events (`event.output_audio.native_audio`) and pushes `bytes` into an asyncio queue so the WebSocket coroutine can yield quickly.
   - Handles session close, heartbeats, and retries similar to the current Google/Groq fallbacks. Important: guard against credential errors so we fall back to OpenAI if the Live API is unavailable.
2. Update `stream_text_to_speech`:
   - Detect the mode from `LLMConfig`. If `mode == "rest"`, run the current logic.
   - If `mode == "live"`, call the new helper and stream the raw Live frames. Do **not** prepend WAV headers—pass through the native format, and include metadata in the WebSocket handshake (`"format": "native"`, `"mime_type": …`).
3. For file-based synthesis (`_google_generate_tts_bytes`), keep the REST path or offer a compatibility fallback (e.g., block until the Live stream completes, concatenate frames, and wrap them in WAV). The smoke test script can choose between live/rest via a CLI flag.
4. Add a dedicated fallback exception so `tts_fallback` can switch providers if the Live session can’t be established.

---

## 3. Flutter client adjustments

No functionality change until you actually switch the backend, but the app must be ready:

1. `LLMConfig.applyRemoteTtsConfig` (Dart) should store `mode`, `mimeType`, and any codec hints.
2. Update `AudioFormatNegotiator` / `SimpleTTSService` to handle `mime_type`:
   - If `mime_type` starts with `audio/wav` -> existing path (PCM)
   - If `audio/ogg; codecs=opus` -> use an in-memory `LockCachingAudioSource` backed by OGG/Opus bytes
   - If you request PCM from Live (possible via config), nothing changes.
3. Ensure the WebSocket handshake includes `"format": "native"` when a non-PCM format is required, so the backend knows not to inject WAV headers.
4. Optional: log the provider/mode on connection so QA can confirm which path is active without digging through backend logs.

---

## 4. Testing strategy

1. **Backend unit/smoke tests**
   - Extend `testTTS.py` with a `--mode live` flag. For live mode, stream to a temporary OGG/Opus file and verify FFprobe metadata (sample rate, codec).
   - Add a pytest that mocks the Live client and asserts `_google_live_stream_tts_chunks` yields decoded bytes promptly.
2. **Integration**
   - Deploy to a staging Cloud Run revision. Hit `/system/tts-config` to confirm it reports `mode: live`.
   - Use the mobile app (no reinstall needed) and watch for earlier playback plus client logs indicating `mime_type` and mode.
3. **Fallbacks**
   - Temporarily revoke the Live API key to make sure the `tts_fallback` decorator kicks us back to OpenAI without crashing the session.

---

## 5. Rollout checklist

1. Merge the backend changes; redeploy staging with `GOOGLE_TTS_MODE=live`.
2. Verify staging logs show `Google Live TTS: received native audio chunk …`.
3. Confirm Flutter logs reflect the new `mimeType` and the player plays without stutters.
4. Once satisfied, promote the revision to production. To return to OpenAI or Gemini REST, flip the `GOOGLE_TTS_MODE`/`ACTIVE_TTS_MODEL` env var and redeploy—no code change required.

With this structure you can toggle between OpenAI, Gemini REST, and Gemini Live entirely through `llm_config.py` (or env overrides), keeping each path isolated while reusing the same WebSocket/Text-to-Speech interfaces the app already understands.
