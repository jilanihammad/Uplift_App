"""
Groq provider.

Chat completion and streaming use the OpenAI-compatible API surface.
Transcription uses the Groq STT endpoint with the module-level
``transcribe_groq`` coroutine.
"""

import logging
import traceback
from pathlib import Path
from typing import Optional, List, Dict, Any, AsyncGenerator

from app.core.llm_config import LLMConfig, ModelType, ModelConfig
from app.services.llm.base_provider import BaseProvider
from app.services.llm.providers.openai_provider import OpenAIProvider

# Phase 2 circuit-breaker decorators
try:
    from app.core.phase2_integration import groq_chat, groq_streaming, groq_transcription
except ImportError:
    def _noop(fn):
        return fn
    groq_chat = groq_streaming = groq_transcription = _noop

logger = logging.getLogger(__name__)


class GroqProvider(BaseProvider):
    """Provider for Groq (OpenAI-compatible API + custom STT)."""

    def __init__(self) -> None:
        # Re-use OpenAI provider for chat / streaming (same wire format)
        self._openai_compat = OpenAIProvider()

    async def generate(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> str:
        return await self._openai_compat.generate(
            message, context, system_prompt, user_info, config, **kwargs,
        )

    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        async for chunk in self._openai_compat.stream(
            message, context, system_prompt, user_info, config, **kwargs,
        ):
            yield chunk

    # ------------------------------------------------------------------
    # Transcription (Groq-specific STT endpoint)
    # ------------------------------------------------------------------

    async def transcribe(self, audio_file_path: str, transcription_config: ModelConfig, **kwargs) -> str:
        if not transcription_config:
            raise ValueError("Transcription configuration not available")
        api_key = LLMConfig.get_api_key(transcription_config)
        if not api_key:
            raise ValueError("Groq API key not found")

        # Import the module-level retry-wrapped coroutine
        from app.services.llm.manager import transcribe_groq
        return await transcribe_groq(
            audio_path=Path(audio_file_path),
            model=transcription_config.model_id,
            api_key=api_key,
        )
