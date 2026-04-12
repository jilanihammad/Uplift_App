"""Voice selection helpers used by the TTS processor.

These functions are stateless. ``LLMManager`` owns the canonical voice
list and validates the final choice — these helpers just decide what to
ask for.
"""
from __future__ import annotations

import hashlib
import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)


def voice_seed(conversation_id: str) -> str:
    """Stable 8-char seed derived from the conversation id."""
    seed_input = f"{conversation_id}_voice_consistency"
    return hashlib.md5(seed_input.encode()).hexdigest()[:8]


def select_voice(
    client_voice: Optional[str], conversation_id: Optional[str], llm_manager: Any
) -> str:
    """Return the voice to request from the TTS provider.

    ``conversation_id`` is currently unused but kept on the signature so
    future per-conversation pinning does not change the call sites.
    """
    try:
        if (
            llm_manager
            and hasattr(llm_manager, "tts_config")
            and llm_manager.tts_config
        ):
            default_voice = llm_manager.tts_config.default_params.get("voice", "nova")
        else:
            default_voice = "nova"
        return client_voice if client_voice else default_voice
    except Exception as exc:  # noqa: BLE001
        logger.warning("Error in voice selection: %s, using fallback", exc)
        return "nova"
