"""
DeepSeek provider (legacy support).

Uses the OpenAI-compatible REST API via httpx.
"""

import logging
import traceback
from typing import Optional, List, Dict, Any, AsyncGenerator

from app.core.llm_config import LLMConfig, ModelConfig
from app.services.llm.base_provider import BaseProvider

logger = logging.getLogger(__name__)


class DeepSeekProvider(BaseProvider):
    """Provider for DeepSeek models (OpenAI-compatible REST)."""

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
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError("DeepSeek API key not found")

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

            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }
            payload = {"model": config.model_id, "messages": messages, **params}

            from app.core.http_client_manager import get_http_client_manager
            http_manager = get_http_client_manager()
            client = http_manager.get_client("openai")
            await client.start()

            response = await client.post(
                f"{config.base_url}/chat/completions",
                headers=headers,
                json=payload,
            )
            response.raise_for_status()
            result = response.json()
            return result["choices"][0]["message"]["content"]

        except Exception as e:
            logger.error("Error generating DeepSeek response: %s", e)
            logger.error(traceback.format_exc())
            raise

    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        # DeepSeek doesn't have a dedicated streaming implementation in the
        # original code; fall back to non-streaming.
        result = await self.generate(message, context, system_prompt, user_info, config, **kwargs)
        yield result
