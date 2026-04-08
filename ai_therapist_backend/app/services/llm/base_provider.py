"""
Abstract base class for LLM providers.

Defines the interface that all providers must implement, plus shared
retry logic and error-handling utilities.
"""

import logging
from abc import ABC, abstractmethod
from typing import Optional, List, Dict, Any, AsyncGenerator

logger = logging.getLogger(__name__)


class BaseProvider(ABC):
    """Base class for all LLM provider implementations."""

    @abstractmethod
    async def generate(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: Any,
        **kwargs,
    ) -> str:
        """Generate a non-streaming chat response.

        Args:
            message: The user's message.
            context: Conversation history.
            system_prompt: System-level instructions.
            user_info: Additional user metadata.
            config: The active ``ModelConfig`` for this provider.
            **kwargs: Extra parameters forwarded to the underlying API.

        Returns:
            The model's text response.
        """

    @abstractmethod
    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: Any,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        """Stream a chat response chunk-by-chunk.

        Yields:
            Text fragments as they arrive from the model.
        """
        # Make this a valid async generator even though it's abstract
        yield ""  # pragma: no cover

    # ------------------------------------------------------------------
    # Optional capabilities -- providers override only what they support
    # ------------------------------------------------------------------

    async def tts(self, text: str, output_file: str, tts_config: Any, **kwargs) -> Any:
        """Convert *text* to speech. Override in providers that support TTS."""
        raise NotImplementedError(f"{self.__class__.__name__} doesn't support TTS")

    async def stream_tts(self, text: str, tts_config: Any, **kwargs) -> AsyncGenerator[str, None]:
        """Stream TTS audio as base64-encoded chunks."""
        raise NotImplementedError(f"{self.__class__.__name__} doesn't support streaming TTS")
        yield ""  # pragma: no cover — make it a valid async generator

    async def transcribe(self, audio_file_path: str, transcription_config: Any, **kwargs) -> str:
        """Transcribe an audio file. Override in providers that support STT."""
        raise NotImplementedError(f"{self.__class__.__name__} doesn't support transcription")

    # ------------------------------------------------------------------
    # Shared helpers available to all providers
    # ------------------------------------------------------------------

    @staticmethod
    def _prepare_chat_messages(
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        build_system_prompt_fn=None,
    ):
        """Build OpenAI-style chat message list (shared across providers).

        Returns:
            Tuple of (messages list, final system prompt string).
        """
        messages: List[Dict[str, str]] = []
        final_system_prompt = system_prompt

        if final_system_prompt:
            messages.append({"role": "system", "content": final_system_prompt})
        elif user_info and build_system_prompt_fn:
            final_system_prompt = build_system_prompt_fn(user_info)
            messages.append({"role": "system", "content": final_system_prompt})

        if context:
            for msg in context:
                role = "user" if msg.get("isUser", False) else "assistant"
                messages.append({"role": role, "content": msg.get("content", "")})

        messages.append({"role": "user", "content": message})

        return messages, final_system_prompt or system_prompt
