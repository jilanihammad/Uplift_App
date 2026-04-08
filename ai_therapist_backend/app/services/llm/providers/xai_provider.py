"""
xAI (Grok) provider.

Uses the official xAI SDK when available, falling back to REST via httpx.
"""

import logging
import traceback
from typing import Optional, List, Dict, Any, AsyncGenerator

import httpx

from app.core.llm_config import LLMConfig, ModelConfig
from app.services.llm.base_provider import BaseProvider
from app.services.llm.providers.openai_provider import OpenAIProvider

try:
    from xai import AsyncClient as XAIAsyncClient
except ImportError:
    XAIAsyncClient = None

logger = logging.getLogger(__name__)


class XAIProvider(BaseProvider):
    """Provider for xAI Grok models."""

    def __init__(self) -> None:
        self._xai_client = None
        # Streaming uses OpenAI-compatible wire format
        self._openai_compat = OpenAIProvider()

    def _get_xai_client(self, config: ModelConfig):
        if XAIAsyncClient is None:
            raise RuntimeError("xAI SDK is not installed. Add 'xai-sdk' to requirements.")
        if not self._xai_client:
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError(f"API key not found for {config.api_key_env}")
            self._xai_client = XAIAsyncClient(api_key=api_key, base_url=config.base_url)
        return self._xai_client

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
        api_key = LLMConfig.get_api_key(config)
        if not api_key:
            raise ValueError("XAI_API_KEY not configured")

        messages, _sys = self._prepare_chat_messages(
            message, context, system_prompt, user_info,
        )

        params = config.default_params.copy()
        params.update(kwargs)
        params.pop("model", None)

        payload: Dict[str, Any] = {"model": config.model_id, "messages": messages}
        payload.update(params)

        # Try SDK first
        if XAIAsyncClient is not None:
            try:
                sdk_client = self._get_xai_client(config)
                sdk_response = await sdk_client.chat.completions.create(**payload)
                sdk_choices = getattr(sdk_response, "choices", None)
                if sdk_choices:
                    first_choice = sdk_choices[0]
                    message_obj = getattr(first_choice, "message", None)
                    content = (
                        message_obj.get("content")
                        if isinstance(message_obj, dict)
                        else getattr(message_obj, "content", None)
                    )
                    if content:
                        return content
            except AttributeError:
                logger.warning("xAI SDK interface differs; falling back to REST")
            except Exception as exc:
                logger.warning("xAI SDK call failed (%s); falling back to REST", exc)

        # REST fallback
        url = f"{config.base_url.rstrip('/')}/chat/completions"
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(url, headers=headers, json=payload)
                response.raise_for_status()
                data = response.json()

            choices = data.get("choices", [])
            if not choices:
                raise ValueError(f"No choices returned from Grok: {data}")
            content = choices[0].get("message", {}).get("content")
            if not content:
                raise ValueError(f"No content found in Grok response: {choices[0]}")
            return content

        except httpx.HTTPStatusError as exc:
            logger.error("Grok API error: status=%s body=%s", exc.response.status_code, exc.response.text)
            raise
        except Exception as exc:
            logger.error("Unexpected Grok API failure: %s", exc)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # Streaming (OpenAI-compatible)
    # ------------------------------------------------------------------

    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        # Grok uses OpenAI-compatible streaming
        async for chunk in self._openai_compat.stream(
            message, context, system_prompt, user_info, config, **kwargs,
        ):
            yield chunk
