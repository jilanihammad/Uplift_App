# Gemini TTS Integration Playbook

Goal: let the backend decide which TTS provider is active (OpenAI, Gemini, etc.) and have the Flutter client adapt automatically. Changing `app/core/llm_config.py` should be the only lever required to flip providers, models, or voices.

---

## 1. Publish the active TTS configuration from the backend

**Files**: `app/core/llm_config.py`, `app/services/llm_manager.py`, `app/api/endpoints/system.py` (or whichever router exposes system metadata)

1. In `app/core/llm_config.py` confirm that `ACTIVE_TTS_PROVIDER`, `ACTIVE_TTS_MODEL`, `DEFAULT_TTS_VOICE`, and the Google/OpenAI `ModelConfig` entries carry the voice, sample rate, and response format inside `default_params`.
2. Add a helper that exposes the currently active settings as JSON-ready data:
   ```python
   @classmethod
   def get_tts_config(cls) -> dict[str, Any]:
       config = cls.get_active_model_config(ModelType.TTS)
       default_params = config.default_params if config else {}

       return {
           "provider": cls.ACTIVE_TTS_PROVIDER.value,
           "model": (cls.ACTIVE_TTS_MODEL or (config.model_id if config else None)),
           "voice": default_params.get("voice", cls.DEFAULT_TTS_VOICE),
           "sample_rate_hz": default_params.get("sample_rate_hz", 24000),
           "audio_encoding": default_params.get("audio_encoding", "LINEAR16"),
           "response_format": default_params.get("response_format", "wav"),
           "supports_streaming": bool(config.supports_streaming if config else False),
       }
   ```
3. Wire a FastAPI route such as `@router.get("/system/tts-config")` that simply returns `LLMConfig.get_tts_config()` (wrap in your `ApiResponse` helper if needed).
4. Hit the endpoint locally (`uvicorn main:app --reload` then `curl http://localhost:8000/system/tts-config`) to confirm the payload matches the values in `llm_config.py`.
5. When deploying, verify Cloud Run logs print the provider/model/voice at startup so you know the container picked up the latest config.

---

## 2. Fetch (and cache) the config in Flutter before opening TTS

**Files**: `ai_therapist_app/lib/data/datasources/remote/api_client.dart`, `ai_therapist_app/lib/services/config_service.dart`, `ai_therapist_app/lib/config/llm_config.dart`

1. Extend `ApiClient` with a `Future<TtsConfigDto> fetchTtsConfig()` helper that performs a GET against `/system/tts-config`.
2. Add a small `TtsConfigDto` model in Dart mirroring the JSON fields (`provider`, `model`, `voice`, `sampleRateHz`, `audioEncoding`, `responseFormat`, `supportsStreaming`).
3. Update your `ConfigService` (or create a dedicated `TtsConfigProvider`) to call `fetchTtsConfig()` after authentication and on app resume. Cache the result in memory and optionally persist it via `SharedPreferences`.
4. Provide a synchronous accessor (`TtsConfig get currentTtsConfig`) so `VoiceService`, `AudioGenerator`, and any WebSocket code can read the latest values without awaiting a network call on the critical path.

---

## 3. Remove hardcoded voices/providers in the client and servers

**Client**
- In `lib/config/llm_config.dart`, introduce runtime override fields (for example `static LLMProvider? _overrideTtsProvider`) so the public getters return backend-provided values when available and fall back to baked-in defaults otherwise.
- When the config service receives the backend payload, call a new `LLMConfig.applyRemoteTtsConfig(TtsConfig config)` to update provider/model/voice/sample-rate.
- Audit `lib/services/audio_generator.dart`, `lib/services/simple_tts_service.dart`, and any WebSocket payload builders to ensure they read from `LLMConfig.activeTTSProvider`, `LLMConfig.activeTTSVoice`, etc., rather than literals like `"charlie"`.

**Backend**
- In `_google_generate_tts_bytes` (and equivalent OpenAI helpers) ensure the voice defaults to `LLMConfig.DEFAULT_TTS_VOICE` unless the client explicitly asks for another voice.
- Confirm the WebSocket handshake in `app/api/endpoints/voice.py` does not override the backend default with stale values; if the client omits `voice`, the backend should inject the configured one.

Once this is done, both sides are reading from the same source: the backend publishes it, the client consumes it dynamically.

---

## 4. Keep `llm_config.py` as the single source of truth

1. Whenever you need to switch providers/models/voices, update `ACTIVE_TTS_PROVIDER`, `ACTIVE_TTS_MODEL`, `DEFAULT_TTS_VOICE`, and any format hints in `app/core/llm_config.py`.
2. Commit the change, redeploy the backend (use `gcloud builds submit --no-cache ...` if you want to ensure fresh layers), and watch for the startup log that prints the active TTS configuration.
3. The Flutter app will pull the new values the next time it refreshes the config service or restarts; no additional mobile release is required.
4. Keep `testTTS.py` handy for local smoke testing—run `python3 testTTS.py --api-key $GOOGLE_API_KEY --text "Hello" --voice kore` to confirm the backend settings still produce the expected 24 kHz PCM before pushing to production.

---

## Optional safeguards

- Add a pytest that asserts `/system/tts-config` matches `LLMConfig.get_tts_config()` so CI fails if someone forgets to update the endpoint.
- Emit the TTS config in the WebSocket "hello" message so the client logs which provider/voice each session uses.
- If you later allow user-selectable voices, use the same endpoint to publish the allowed voice list per provider.
