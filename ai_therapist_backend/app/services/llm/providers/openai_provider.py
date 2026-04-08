"""
OpenAI + Azure OpenAI provider.

Handles chat completion, streaming, TTS (WAV and OPUS), and transcription
for providers that expose an OpenAI-compatible API surface.
"""

import base64
import logging
import os
import traceback
import time
from typing import Optional, List, Dict, Any, AsyncGenerator

from openai import OpenAI

from app.core.llm_config import LLMConfig, ModelType, ModelProvider, ModelConfig
from app.utils.audio_path import ensure_wav
from app.services.llm.base_provider import BaseProvider

# Phase 2 circuit-breaker decorators (no-ops when unavailable)
try:
    from app.core.resilience import (
        openai_chat, openai_streaming, openai_tts,
    )
except ImportError:
    def _noop(fn):
        return fn
    openai_chat = openai_streaming = openai_tts = _noop

logger = logging.getLogger(__name__)


class OpenAIProvider(BaseProvider):
    """Provider for OpenAI and Azure OpenAI APIs."""

    def __init__(self) -> None:
        self._openai_client: Optional[OpenAI] = None

    # ------------------------------------------------------------------
    # Client helpers
    # ------------------------------------------------------------------

    @staticmethod
    def get_client(config: ModelConfig) -> OpenAI:
        """Create a new OpenAI client for the given configuration."""
        api_key = LLMConfig.get_api_key(config)
        if not api_key:
            raise ValueError(f"API key not found for {config.api_key_env}")
        if config.provider == ModelProvider.AZURE_OPENAI:
            return OpenAI(
                api_key=api_key,
                base_url=f"{config.base_url}/openai/deployments/{config.model_id}",
                default_headers={
                    "api-version": config.default_params.get("api_version", "2024-02-15-preview")
                },
            )
        return OpenAI(api_key=api_key, base_url=config.base_url)

    # ------------------------------------------------------------------
    # Chat completion
    # ------------------------------------------------------------------

    async def generate(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> str:
        try:
            client = self.get_client(config)

            messages, _sys = self._prepare_chat_messages(
                message, context, system_prompt, user_info
            )

            params = config.default_params.copy()
            params.update(kwargs)
            params.pop("model", None)

            completion = client.chat.completions.create(
                model=config.model_id,
                messages=messages,
                **params,
            )

            return completion.choices[0].message.content

        except Exception as e:
            logger.error("Error generating OpenAI-compatible response: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # Streaming
    # ------------------------------------------------------------------

    @openai_streaming
    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        try:
            client = self.get_client(config)

            messages: List[Dict[str, str]] = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            elif user_info:
                from app.services.llm.manager import _build_system_prompt
                system_prompt = _build_system_prompt(user_info)
                messages.append({"role": "system", "content": system_prompt})
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            messages.append({"role": "user", "content": message})

            params = config.default_params.copy()
            params.update(kwargs)
            params["stream"] = True
            params.pop("model", None)

            stream = client.chat.completions.create(
                model=config.model_id,
                messages=messages,
                **params,
            )

            for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    yield chunk.choices[0].delta.content

        except Exception as e:
            logger.error("Error streaming OpenAI-compatible response: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # TTS (file save)
    # ------------------------------------------------------------------

    async def tts(self, text: str, output_file: str, tts_config: ModelConfig, **kwargs) -> Any:
        if not tts_config:
            raise ValueError("TTS configuration not available")

        try:
            import openai as _openai_mod
            logger.info("OpenAI SDK at TTS call: version=%s from %s", _openai_mod.__version__, _openai_mod.__file__)
        except Exception:
            pass

        try:
            client = self.get_client(tts_config)
            params = tts_config.default_params.copy()
            params.update(kwargs)
            params.pop("model", None)

            voice = kwargs.get("voice")
            response_format = kwargs.get("response_format")
            if voice:
                params["voice"] = voice
            if response_format:
                params["response_format"] = response_format
            else:
                response_format = params.get("response_format", "mp3")

            response = client.audio.speech.create(
                model=tts_config.model_id,
                input=text,
                **params,
            )

            audio_bytes = response.content if hasattr(response, "content") else response.read()
            with open(output_file, "wb") as f:
                f.write(audio_bytes)
            logger.info("Audio saved to: %s (%d bytes)", output_file, len(audio_bytes))

            return base64.b64encode(audio_bytes).decode("utf-8")
        except Exception as e:
            logger.error("Error in OpenAI text-to-speech: %s", e)
            logger.error(traceback.format_exc())
            return ""

    # ------------------------------------------------------------------
    # Streaming TTS
    # ------------------------------------------------------------------

    async def stream_tts(self, text: str, tts_config: ModelConfig, **kwargs) -> AsyncGenerator[str, None]:
        """Stream TTS audio as base64-encoded chunks (WAV or OPUS)."""
        if not tts_config:
            raise ValueError("TTS configuration not available")

        voice = kwargs.pop("voice", None)
        response_format = kwargs.pop("response_format", None) or "wav"
        opus_params = kwargs.pop("opus_params", None)

        if response_format in ("opus", "ogg_opus"):
            async for chunk in self._stream_opus(text, tts_config, voice=voice, **kwargs):
                yield chunk
        else:
            async for chunk in self._stream_wav(text, tts_config, voice=voice, response_format=response_format, **kwargs):
                yield chunk

    async def _stream_wav(self, text: str, tts_config: ModelConfig, *, voice=None, response_format="wav", **kwargs):
        client = self.get_client(tts_config)

        params = tts_config.default_params.copy()
        params.update(kwargs)
        if voice:
            params["voice"] = voice
        if response_format:
            params["response_format"] = response_format
        else:
            response_format = params.get("response_format", "mp3")
        params.pop("model", None)

        try:
            logger.info(
                "OpenAI TTS: Starting MP3 streaming for text='%s...' (length: %d chars), voice=%s, format=%s",
                text[:50], len(text), params["voice"], response_format,
            )

            total_chunks = 0
            total_bytes = 0
            first_chunk_logged = False

            tts_args = LLMConfig.DEFAULT_TTS_ARGS.copy()
            tts_args["input"] = text
            voice_param = params.get("voice") or tts_args["voice"]
            tts_args["voice"] = voice_param
            tts_args["response_format"] = response_format or "mp3"

            with client.audio.speech.with_streaming_response.create(**tts_args) as response:
                if response.status_code != 200:
                    raise Exception(f"TTS streaming failed: {response.status_code}")

                logger.info(
                    "Starting streaming: format=%s, status=%d, text='%s...'",
                    tts_args["response_format"], response.status_code, text[:60],
                )

                first_chunk_t0 = time.perf_counter()

                for idx, chunk in enumerate(response.iter_bytes(chunk_size=16384)):
                    if chunk:
                        if idx == 0:
                            logger.info("FIRST-CHUNK LATENCY: %.1f ms", (time.perf_counter() - first_chunk_t0) * 1000)

                        total_chunks += 1
                        total_bytes += len(chunk)

                        if not first_chunk_logged:
                            first_16_bytes = chunk[:16].hex() if len(chunk) >= 16 else chunk.hex()
                            logger.info("TTS stream opened (%s codec, %d-byte first chunk)", response_format, len(chunk))
                            logger.debug("First chunk header (hex): %s", first_16_bytes)
                            _validate_audio_chunk(chunk, response_format or "wav")
                            first_chunk_logged = True

                        b64_chunk = base64.b64encode(chunk).decode("utf-8")
                        from app.core.config import settings
                        if settings.VERBOSE_AUDIO_CHUNKS:
                            logger.debug("OpenAI TTS: WAV chunk %d, size=%d bytes", total_chunks, len(chunk))
                        yield b64_chunk

            logger.info(
                "OpenAI TTS: MP3 completed - generated %d chunks, %d total bytes for text: '%s...'",
                total_chunks, total_bytes, text[:50],
            )

        except Exception as e:
            logger.error("OpenAI TTS WAV streaming error: %s", e)
            logger.error(traceback.format_exc())
            raise

    async def _stream_opus(self, text: str, tts_config: ModelConfig, *, voice=None, **kwargs):
        if not tts_config:
            raise ValueError("TTS configuration not available")

        try:
            logger.info("Starting direct OPUS streaming: text='%s...' (length: %d chars), voice=%s", text[:50], len(text), voice)

            client = self.get_client(tts_config)

            params = tts_config.default_params.copy()
            params.update(kwargs)
            if voice:
                params["voice"] = voice
            params["response_format"] = "opus"

            from app.core.config import settings
            use_new_streaming = settings.OPENAI_TTS_STREAM

            logger.info("Attempting OPUS streaming from OpenAI (stream_flag=%s, will_use_streaming=%s)...", settings.OPENAI_TTS_STREAM, use_new_streaming)

            params.pop("model", None)

            total_chunks = 0
            total_bytes = 0

            if use_new_streaming:
                try:
                    start_time = time.time()

                    logger.info(
                        "Starting streaming: format=%s, model=%s, voice=%s, text='%s...'",
                        params.get("response_format", "default"),
                        tts_config.model_id,
                        params["voice"],
                        text[:60],
                    )

                    tts_args = LLMConfig.DEFAULT_TTS_ARGS.copy()
                    tts_args.update({"input": text, "voice": params["voice"], "response_format": "opus"})

                    with client.audio.speech.with_streaming_response.create(**tts_args) as response:
                        logger.info("NEW STREAMING: Response object created, iterating chunks...")
                        first_chunk_time = None
                        first_chunk_t0 = time.perf_counter()

                        for idx, chunk in enumerate(response.iter_bytes()):
                            if chunk:
                                if idx == 0:
                                    logger.info("FIRST-CHUNK LATENCY: %.1f ms", (time.perf_counter() - first_chunk_t0) * 1000)
                                total_chunks += 1
                                total_bytes += len(chunk)

                                if total_chunks == 1:
                                    first_chunk_time = time.time()
                                    ttfb_ms = (first_chunk_time - start_time) * 1000
                                    logger.info("NEW STREAMING TTFB: %.1fms (target: 150-300ms)", ttfb_ms)
                                    try:
                                        from app.core.performance_monitor import record_latency
                                        record_latency("openai_tts_ttfb", ttfb_ms, True, streaming_method="new", format="opus")
                                    except Exception:
                                        pass
                                    _validate_audio_chunk(chunk, "opus")

                                b64_chunk = base64.b64encode(chunk).decode("utf-8")
                                if settings.VERBOSE_AUDIO_CHUNKS:
                                    logger.debug("NEW STREAMING chunk %d, size=%d bytes", total_chunks, len(chunk))
                                yield b64_chunk

                    logger.info("NEW STREAMING completed: %d chunks, %d total bytes", total_chunks, total_bytes)
                    return

                except Exception as streaming_error:
                    logger.error("NEW STREAMING failed, falling back to legacy: %s", streaming_error)
                    logger.error(traceback.format_exc())
                    use_new_streaming = False

            if not use_new_streaming:
                start_time = time.time()

                tts_args = LLMConfig.DEFAULT_TTS_ARGS.copy()
                tts_args["input"] = text
                voice_param = params.get("voice") or tts_args["voice"]
                tts_args["voice"] = voice_param
                tts_args["response_format"] = "opus"

                with client.audio.speech.with_streaming_response.create(**tts_args) as response:
                    if response.status_code != 200:
                        raise Exception(f"OpenAI OPUS streaming failed: {response.status_code}")

                    logger.info("LEGACY STREAMING: Direct OPUS stream started, status=%d", response.status_code)
                    first_chunk_time = None

                    for chunk in response.iter_bytes(chunk_size=4096):
                        if chunk:
                            total_chunks += 1
                            total_bytes += len(chunk)

                            if total_chunks == 1:
                                first_chunk_time = time.time()
                                logger.info("TTS stream opened (opus codec, %d-byte first chunk)", len(chunk))
                                first_16_bytes = chunk[:16].hex() if len(chunk) >= 16 else chunk.hex()
                                logger.info("First OPUS chunk header (hex): %s", first_16_bytes)
                                ttfb_ms = (first_chunk_time - start_time) * 1000
                                logger.info("LEGACY STREAMING TTFB: %.1fms (baseline: 700-1200ms)", ttfb_ms)
                                try:
                                    from app.core.performance_monitor import record_latency
                                    record_latency("openai_tts_ttfb", ttfb_ms, True, streaming_method="legacy", format="opus")
                                except Exception:
                                    pass
                                _validate_audio_chunk(chunk, "opus")

                            b64_chunk = base64.b64encode(chunk).decode("utf-8")
                            from app.core.config import settings as _settings
                            if _settings.VERBOSE_AUDIO_CHUNKS:
                                logger.debug("LEGACY STREAMING chunk %d, size=%d bytes", total_chunks, len(chunk))
                            yield b64_chunk

            logger.info("Direct OPUS streaming completed: %d chunks, %d total bytes", total_chunks, total_bytes)

        except Exception as e:
            logger.error("OPUS streaming error: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    async def transcribe(self, audio_file_path: str, transcription_config: ModelConfig, **kwargs) -> str:
        if not transcription_config:
            raise ValueError("Transcription configuration not available")

        try:
            if not os.path.exists(audio_file_path):
                raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

            client = self.get_client(transcription_config)

            params = transcription_config.default_params.copy()
            params.update(kwargs)
            params.pop("model", None)

            with open(audio_file_path, "rb") as audio_file:
                transcript = client.audio.transcriptions.create(
                    model=transcription_config.model_id,
                    file=audio_file,
                    **params,
                )

            return transcript.text

        except Exception as e:
            logger.error("Error in OpenAI transcription: %s", e)
            logger.error(traceback.format_exc())
            raise


# ------------------------------------------------------------------
# Module-level audio validation helpers (shared with manager)
# ------------------------------------------------------------------

def _validate_audio_chunk(chunk: bytes, response_format: str) -> None:
    if response_format == "opus":
        _validate_ogg_header(chunk)
    elif response_format == "wav":
        _validate_wav_header(chunk)


def _validate_ogg_header(chunk: bytes) -> None:
    if len(chunk) < 16:
        logger.debug("OPUS chunk validation: chunk too small (%d bytes)", len(chunk))
        return
    if chunk.startswith(b"OggS"):
        logger.debug("OPUS validation: Valid OGG container header found")
        if len(chunk) >= 27:
            version = chunk[4]
            page_type = chunk[5]
            logger.debug("OPUS validation: OGG version=%d, page_type=%d", version, page_type)
            if page_type & 0x02:
                logger.debug("OPUS validation: Beginning-of-stream page detected")
            else:
                logger.debug("OPUS validation: Continuation page")
    else:
        logger.debug("OPUS validation: Expected OGG header, got: %s", chunk[:8].hex())


def _validate_wav_header(chunk: bytes) -> None:
    if len(chunk) < 12:
        logger.debug("WAV chunk validation: chunk too small (%d bytes)", len(chunk))
        return
    if chunk.startswith(b"RIFF") and b"WAVE" in chunk[:12]:
        logger.debug("WAV validation: Valid RIFF/WAVE header found")
    else:
        logger.debug("WAV validation: Expected RIFF/WAVE header, got: %s", chunk[:12].hex())
