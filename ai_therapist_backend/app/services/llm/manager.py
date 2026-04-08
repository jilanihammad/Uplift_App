"""
LLM Manager — thin router that delegates to per-provider strategy classes.

All public API surface (``generate_response``, ``stream_chat_completion``,
``text_to_speech``, ``stream_text_to_speech``, ``transcribe_audio``, etc.)
is preserved 1-for-1 so that callers do not need to change.
"""

import asyncio
import logging
from pathlib import Path
from typing import Any, AsyncGenerator, Dict, Final, List, Optional

from httpx import ConnectTimeout, HTTPStatusError, ReadTimeout, RemoteProtocolError
from tenacity import (
    retry,
    retry_if_exception,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
    wait_random_exponential,
)

from app.core.llm_config import LLMConfig, ModelConfig, ModelProvider, ModelType
from app.utils.audio_path import ensure_wav

# Phase 2 circuit-breaker fallback decorators
try:
    from app.core.phase2_integration import llm_fallback, tts_fallback
    PHASE2_AVAILABLE = True
except ImportError:
    PHASE2_AVAILABLE = False

    def _noop(fn):
        return fn
    llm_fallback = tts_fallback = _noop

# Providers (lazy-imported at class init for clean startup logs)
from app.services.llm.providers.openai_provider import OpenAIProvider
from app.services.llm.providers.anthropic_provider import AnthropicProvider
from app.services.llm.providers.google_provider import GoogleProvider, GeminiLiveSession
from app.services.llm.providers.groq_provider import GroqProvider
from app.services.llm.providers.xai_provider import XAIProvider
from app.services.llm.providers.deepseek_provider import DeepSeekProvider

logger = logging.getLogger(__name__)

# Log Phase 2 status
if PHASE2_AVAILABLE:
    logger.info("Phase 2 circuit breaker integration available")
else:
    logger.warning("Phase 2 circuit breakers not available")

# =============================================================================
# OpenAI SDK version guard (kept from original)
# =============================================================================
try:
    import openai as _openai_mod

    logger.info("OpenAI SDK loaded at import: version=%s from %s", _openai_mod.__version__, _openai_mod.__file__)
    from packaging import version as _pkg_version

    if _pkg_version.parse(_openai_mod.__version__) < _pkg_version.parse("1.85.0"):
        _err = f"OpenAI SDK {_openai_mod.__version__} is too old! Need >= 1.85.0"
        logger.error(_err)
        raise RuntimeError(_err)
except Exception as _e:
    logger.error("Failed to verify OpenAI SDK version: %s", _e)

# =============================================================================
# GROQ STT CLIENT — module-level singleton for connection pooling
# =============================================================================

GROQ_STT_URL: Final = "https://api.groq.com/openai/v1/audio/transcriptions"
MAX_CONCURRENT_STT: Final = 8
STT_TIMEOUT_SECONDS: Final = 5.0

_groq_stt_client: Optional[Any] = None


def _get_groq_stt_client():
    global _groq_stt_client
    if _groq_stt_client is None:
        from app.core.http_client_manager import get_http_client_manager

        http_manager = get_http_client_manager()
        _groq_stt_client = http_manager.get_client("groq")
    return _groq_stt_client


_stt_semaphore = asyncio.Semaphore(MAX_CONCURRENT_STT)


def _is_retryable_stt_error(exc):
    return isinstance(exc, HTTPStatusError) and (
        500 <= exc.response.status_code < 600 or exc.response.status_code == 429
    )


async def _do_post(audio_path: Path, model: str, api_key: str) -> str:
    async def _groq_post():
        with audio_path.open("rb") as f:
            stt_client = _get_groq_stt_client()
            await stt_client.start()
            resp = await stt_client.post(
                GROQ_STT_URL,
                files={"file": ("audio.m4a", f, "audio/mp4")},
                data={"model": model, "temperature": "0.0", "response_format": "verbose_json"},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            resp.raise_for_status()
            data = resp.json()
            text = data.get("text", "").strip()
            if not text:
                raise ValueError(f"Groq response missing 'text': {data}")
            return text

    async with _stt_semaphore:
        try:
            return await asyncio.wait_for(_groq_post(), timeout=STT_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            raise ReadTimeout(f"Groq STT exceeded {STT_TIMEOUT_SECONDS}s hard timeout")


transcribe_groq = retry(
    stop=stop_after_attempt(3),
    wait=wait_random_exponential(multiplier=0.2, max=1.0),
    retry=(
        retry_if_exception(_is_retryable_stt_error)
        | retry_if_exception_type(ReadTimeout)
        | retry_if_exception_type(ConnectTimeout)
        | retry_if_exception_type(RemoteProtocolError)
    ),
    reraise=True,
)(_do_post)


# =============================================================================
# Shared helper: build system prompt (used by providers via deferred import)
# =============================================================================

def _build_system_prompt(user_info: Optional[Dict[str, Any]] = None) -> str:
    base_prompt = """
        You are an AI therapist designed to provide supportive and empathetic conversations to users seeking mental health support. Your primary role is to listen actively to the user. Encourage them to share their thoughts and feelings by asking open-ended questions and providing space for them to express themselves. Show empathy by acknowledging and validating the user's emotions. Use phrases like 'That sounds really tough' or 'I can understand why you feel that way.' Adapt your responses based on the user's input. If they seem to need more support, offer comforting words. If they want to explore solutions, gently guide them towards that. Be prepared to discuss a wide range of mental health topics, including but not limited to depression, anxiety, stress, loneliness, and relationship issues. Recognize when a user's situation might require professional intervention and gently suggest seeking help from a human therapist or counselor. Always remember that you are an AI, not a human therapist. Make this clear to the user and emphasize that while you can provide support, you are not a substitute for professional mental health care. Respect the user's privacy and do not store or share any personal information. Be mindful of cultural differences and avoid making assumptions based on stereotypes. Show respect for the user's background and experiences. Use a warm, friendly, and conversational tone. Avoid jargon or overly technical language unless the user specifically requests it. Guide the conversation gently, ensuring it stays focused on the user's needs. Use techniques like reflective listening and summarizing to show understanding. Be patient and allow the user time to express themselves. Do not rush the conversation or push for quick resolutions. If the user mentions thoughts of self-harm or suicide, respond with immediate concern and strongly encourage them to seek help from a mental health professional or a crisis hotline. Provide resources if possible. Celebrate the user's progress and efforts, even small steps. Use encouraging language to motivate them. Maintain a consistent and caring persona throughout the conversation, so the user feels a sense of continuity and trust

        Guidelines:
        - Respond with empathy and genuine concern
        - Speak less and listen more
        - When the patient, client or customer is crying, let them cry without interrupting them, be kind and patient
        - Ask thoughtful, open-ended questions to deepen understanding
        - Offer reflections and gentle observations
        - Suggest practical strategies when appropriate
        - Maintain professional boundaries
        - Encourage self-care and healthy habits
        - Never give medical advice or replace professional mental health care
        """

    if not user_info:
        return base_prompt

    personalization = []
    if "name" in user_info:
        personalization.append(f"You're speaking with {user_info['name']}.")
    if "assessment" in user_info and user_info["assessment"]:
        assessment = user_info["assessment"]
        if "primary_goal" in assessment:
            personalization.append(f"Their primary therapy goal is {assessment['primary_goal']}.")
        if "challenges" in assessment and assessment["challenges"]:
            challenges = ", ".join(assessment["challenges"])
            personalization.append(f"They're currently dealing with: {challenges}.")
        if "preferred_approach" in assessment:
            approach = assessment["preferred_approach"]
            if approach == "practical":
                personalization.append("They prefer a practical, solution-focused approach.")
            elif approach == "emotional":
                personalization.append("They prefer emotional support and validation.")
            elif approach == "balanced":
                personalization.append("They prefer a balance of practical advice and emotional support.")
    if personalization:
        return base_prompt + "\n\n" + "\n".join(personalization)
    return base_prompt


# =============================================================================
# LLMManager — the public router
# =============================================================================

class LLMManager:
    """
    Unified manager for all LLM operations.  Routes requests to the
    appropriate provider based on the configuration in ``LLMConfig``.
    """

    def __init__(self) -> None:
        try:
            from google import genai as _genai
            logger.info("google-genai runtime version: %s", getattr(_genai, "__version__", "unknown"))
        except Exception as exc:
            logger.warning("Unable to determine google-genai version: %s", exc)

        try:
            from xai import AsyncClient as _XAI  # noqa: F401
            import xai as _xai_mod
            logger.info("xai runtime version: %s", getattr(_xai_mod, "__version__", "unknown"))
        except Exception:
            pass

        self.llm_config = LLMConfig.get_active_model_config(ModelType.LLM)
        self.tts_config = LLMConfig.get_active_model_config(ModelType.TTS)
        self.transcription_config = LLMConfig.get_active_model_config(ModelType.TRANSCRIPTION)

        # Instantiate provider singletons
        self._providers = {
            ModelProvider.OPENAI: OpenAIProvider(),
            ModelProvider.AZURE_OPENAI: OpenAIProvider(),
            ModelProvider.GROQ: GroqProvider(),
            ModelProvider.GROK: XAIProvider(),
            ModelProvider.ANTHROPIC: AnthropicProvider(),
            ModelProvider.GOOGLE: GoogleProvider(),
            ModelProvider.DEEPSEEK: DeepSeekProvider(),
        }

        logger.info("LLMManager initialized with:")
        logger.info("LLM: %s - %s", self.llm_config.provider if self.llm_config else "None", self.llm_config.model_id if self.llm_config else "None")
        logger.info("TTS: %s - %s", self.tts_config.provider if self.tts_config else "None", self.tts_config.model_id if self.tts_config else "None")
        logger.info("Transcription: %s - %s", self.transcription_config.provider if self.transcription_config else "None", self.transcription_config.model_id if self.transcription_config else "None")

    # ------------------------------------------------------------------
    # Provider lookup
    # ------------------------------------------------------------------

    def _get_provider(self, provider: ModelProvider):
        prov = self._providers.get(provider)
        if prov is None:
            raise ValueError(f"Unsupported provider: {provider}")
        return prov

    # ------------------------------------------------------------------
    # Gemini Live Duplex helpers
    # ------------------------------------------------------------------

    def create_gemini_live_session(self, *, user_id=None, metadata=None, live_config=None) -> GeminiLiveSession:
        tts_cfg = self.tts_config or LLMConfig.get_active_model_config(ModelType.TTS)
        return GoogleProvider.create_live_session(
            tts_cfg, user_id=user_id, metadata=metadata, live_config=live_config,
        )

    # ------------------------------------------------------------------
    # Chat completion (non-streaming)
    # ------------------------------------------------------------------

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def generate_response(
        self,
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs,
    ) -> str:
        if not self.llm_config:
            raise ValueError("No LLM configuration available")
        if not LLMConfig.is_model_available(ModelType.LLM):
            raise ValueError("LLM service unavailable - API key not set")

        provider = self._get_provider(self.llm_config.provider)
        return await provider.generate(
            message, context, system_prompt, user_info, self.llm_config, **kwargs,
        )

    # ------------------------------------------------------------------
    # Chat completion (streaming)
    # ------------------------------------------------------------------

    @llm_fallback
    async def stream_chat_completion(
        self,
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        if not self.llm_config:
            raise ValueError("No LLM configuration available")
        if not LLMConfig.is_model_available(ModelType.LLM):
            raise ValueError("LLM service unavailable - API key not set")
        if not self.llm_config.supports_streaming:
            logger.info(
                "Provider %s (%s) does not support streaming. Falling back.",
                self.llm_config.provider, self.llm_config.model_id,
            )
            response = await self.generate_response(message, context, system_prompt, user_info, **kwargs)
            yield response
            return

        provider = self._get_provider(self.llm_config.provider)
        async for chunk in provider.stream(
            message, context, system_prompt, user_info, self.llm_config, **kwargs,
        ):
            yield chunk

    # ------------------------------------------------------------------
    # Text-to-Speech (file save)
    # ------------------------------------------------------------------

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def text_to_speech(
        self,
        text: str,
        output_file: str,
        response_format: Optional[str] = None,
        voice: Optional[str] = None,
        **kwargs,
    ):
        response_format = response_format or "wav"

        if response_format == "wav":
            output_file = ensure_wav(output_file)
        elif response_format == "mp3":
            output_file = output_file if output_file.lower().endswith(".mp3") else f"{output_file}.mp3"
        elif response_format in ("opus", "ogg_opus"):
            output_file = output_file if output_file.lower().endswith(".ogg") else f"{output_file}.ogg"

        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")

        provider = self._get_provider(self.tts_config.provider)
        return await provider.tts(
            text, output_file, self.tts_config,
            voice=voice, response_format=response_format, **kwargs,
        )

    # ------------------------------------------------------------------
    # Text-to-Speech (streaming, yields base64 chunks)
    # ------------------------------------------------------------------

    @tts_fallback
    async def stream_text_to_speech(
        self,
        text: str,
        voice: Optional[str] = None,
        response_format: Optional[str] = None,
        opus_params: Optional[Dict[str, Any]] = None,
        **kwargs,
    ):
        default_format = "wav"
        if (
            self.tts_config
            and self.tts_config.provider == ModelProvider.GOOGLE
            and (self.tts_config.default_params or {}).get("mode", "rest") == "live"
        ):
            default_format = "native"

        response_format = response_format or default_format

        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")

        provider = self._get_provider(self.tts_config.provider)
        async for chunk in provider.stream_tts(
            text,
            self.tts_config,
            voice=voice,
            response_format=response_format,
            opus_params=opus_params,
            **kwargs,
        ):
            yield chunk

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def transcribe_audio(self, audio_file_path: str, **kwargs) -> str:
        if not self.transcription_config:
            raise ValueError("No transcription configuration available")
        if not LLMConfig.is_model_available(ModelType.TRANSCRIPTION):
            raise ValueError("Transcription service unavailable - API key not set")

        provider = self._get_provider(self.transcription_config.provider)
        return await provider.transcribe(audio_file_path, self.transcription_config, **kwargs)

    # ------------------------------------------------------------------
    # Utility methods (kept for backward compatibility)
    # ------------------------------------------------------------------

    def _build_system_prompt(self, user_info: Optional[Dict[str, Any]] = None) -> str:
        return _build_system_prompt(user_info)

    async def test_api(self) -> Dict[str, Any]:
        results = {}
        if self.llm_config:
            try:
                await self.generate_response("Say hello", max_tokens=10, temperature=0.1)
                results["llm"] = {"available": True, "provider": self.llm_config.provider, "model": self.llm_config.model_id, "message": "LLM test successful"}
            except Exception as e:
                results["llm"] = {"available": False, "provider": self.llm_config.provider, "model": self.llm_config.model_id, "error": str(e)}
        else:
            results["llm"] = {"available": False, "error": "No LLM configuration available"}
        if self.tts_config:
            results["tts"] = {
                "available": LLMConfig.is_model_available(ModelType.TTS),
                "provider": self.tts_config.provider,
                "model": self.tts_config.model_id,
                "message": "TTS configuration available" if LLMConfig.is_model_available(ModelType.TTS) else "TTS API key not available",
            }
        else:
            results["tts"] = {"available": False, "error": "No TTS configuration available"}
        if self.transcription_config:
            results["transcription"] = {
                "available": LLMConfig.is_model_available(ModelType.TRANSCRIPTION),
                "provider": self.transcription_config.provider,
                "model": self.transcription_config.model_id,
                "message": "Transcription configuration available" if LLMConfig.is_model_available(ModelType.TRANSCRIPTION) else "Transcription API key not available",
            }
        else:
            results["transcription"] = {"available": False, "error": "No transcription configuration available"}
        return results

    def get_status(self) -> Dict[str, Any]:
        return {
            "model_info": LLMConfig.get_model_info(),
            "configurations": {
                "llm": {
                    "provider": self.llm_config.provider if self.llm_config else None,
                    "model": self.llm_config.model_id if self.llm_config else None,
                    "supports_streaming": self.llm_config.supports_streaming if self.llm_config else False,
                    "available": LLMConfig.is_model_available(ModelType.LLM),
                },
                "tts": {
                    "provider": self.tts_config.provider if self.tts_config else None,
                    "model": self.tts_config.model_id if self.tts_config else None,
                    "supports_streaming": self.tts_config.supports_streaming if self.tts_config else False,
                    "available": LLMConfig.is_model_available(ModelType.TTS),
                },
                "transcription": {
                    "provider": self.transcription_config.provider if self.transcription_config else None,
                    "model": self.transcription_config.model_id if self.transcription_config else None,
                    "available": LLMConfig.is_model_available(ModelType.TRANSCRIPTION),
                },
            },
            "available_providers": {
                "llm": LLMConfig.list_available_providers(ModelType.LLM),
                "tts": LLMConfig.list_available_providers(ModelType.TTS),
                "transcription": LLMConfig.list_available_providers(ModelType.TRANSCRIPTION),
            },
        }


# Create singleton instance
llm_manager = LLMManager()
