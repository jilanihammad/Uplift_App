"""
Backwards-compatibility shim.

The real implementation now lives in ``app.services.llm``.  This file
ensures that every existing ``from app.services.llm_manager import ...``
continues to work without changes.
"""

# Re-export everything from the new location
from app.services.llm.manager import *            # noqa: F401,F403
from app.services.llm.manager import (            # noqa: F401  — explicit names for star-import gaps
    LLMManager,
    llm_manager,
    _groq_stt_client,
    transcribe_groq,
    _build_system_prompt,
)
from app.services.llm.providers.google_provider import GeminiLiveSession  # noqa: F401
