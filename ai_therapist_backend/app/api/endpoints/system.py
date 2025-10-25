"""System metadata endpoints."""

from fastapi import APIRouter

from app.core.llm_config import LLMConfig

router = APIRouter()


@router.get("/tts-config")
async def get_tts_configuration() -> dict[str, object]:
    """Expose the active text-to-speech configuration for client consumption."""
    return LLMConfig.get_tts_config()
