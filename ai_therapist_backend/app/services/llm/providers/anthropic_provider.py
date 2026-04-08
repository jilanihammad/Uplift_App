"""
Anthropic (Claude) provider.

Handles chat completion and streaming via the Anthropic Python SDK.
"""

import logging
import traceback
from typing import Optional, List, Dict, Any, AsyncGenerator

import anthropic

from app.core.llm_config import LLMConfig, ModelConfig
from app.services.llm.base_provider import BaseProvider

# Phase 2 circuit-breaker decorators
try:
    from app.core.resilience import anthropic_chat, anthropic_streaming
except ImportError:
    def _noop(fn):
        return fn
    anthropic_chat = anthropic_streaming = _noop

logger = logging.getLogger(__name__)


class AnthropicProvider(BaseProvider):
    """Provider for Anthropic Claude models."""

    def __init__(self) -> None:
        self._client: Optional[anthropic.AsyncAnthropic] = None

    def _get_client(self, config: ModelConfig) -> anthropic.AsyncAnthropic:
        if not self._client:
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError(f"API key not found for {config.api_key_env}")
            self._client = anthropic.AsyncAnthropic(api_key=api_key)
        return self._client

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
            client = self._get_client(config)

            # Anthropic format: system is a separate param, not in messages
            messages: List[Dict[str, str]] = []
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            messages.append({"role": "user", "content": message})

            if not system_prompt and user_info:
                from app.services.llm.manager import _build_system_prompt
                system_prompt = _build_system_prompt(user_info)

            params = config.default_params.copy()
            params.update(kwargs)
            params.pop("model", None)

            response = await client.messages.create(
                model=config.model_id,
                system=system_prompt if system_prompt else "You are a helpful AI assistant.",
                messages=messages,
                **params,
            )

            return response.content[0].text

        except Exception as e:
            logger.error("Error generating Anthropic response: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # Streaming
    # ------------------------------------------------------------------

    @anthropic_streaming
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
            client = self._get_client(config)

            messages: List[Dict[str, str]] = []
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            messages.append({"role": "user", "content": message})

            if not system_prompt and user_info:
                from app.services.llm.manager import _build_system_prompt
                system_prompt = _build_system_prompt(user_info)

            params = config.default_params.copy()
            params.update(kwargs)
            params.pop("model", None)

            async with client.messages.stream(
                model=config.model_id,
                system=system_prompt if system_prompt else "You are a helpful AI assistant.",
                messages=messages,
                **params,
            ) as stream:
                async for text in stream.text_stream:
                    yield text

        except Exception as e:
            logger.error("Error streaming Anthropic response: %s", e)
            logger.error(traceback.format_exc())
            raise
