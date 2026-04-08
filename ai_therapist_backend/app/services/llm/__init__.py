"""
app.services.llm — Strategy-pattern LLM provider framework.

Re-exports the public API so that ``from app.services.llm import llm_manager``
works as expected.
"""

from app.services.llm.manager import LLMManager, llm_manager, _groq_stt_client, transcribe_groq  # noqa: F401
from app.services.llm.providers.google_provider import GeminiLiveSession  # noqa: F401

__all__ = [
    "LLMManager",
    "llm_manager",
    "_groq_stt_client",
    "transcribe_groq",
    "GeminiLiveSession",
]
