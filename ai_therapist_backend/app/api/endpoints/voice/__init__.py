"""
Voice API endpoints package.

Aggregates all sub-routers and re-exports key symbols for backward compatibility.
"""
from fastapi import APIRouter

from .streaming import router as streaming_router, websocket_streaming_tts
from .tts import router as tts_router, websocket_tts
from .gemini_live import router as gemini_live_router, websocket_gemini_live
from .transcription import router as transcription_router
from .health import router as health_router, ping_endpoint

from .security import WebSocketSecurityValidator, JWTSecurityManager, jwt_security
from .rate_limiter import TextInputRateLimiter, text_rate_limiter
from .connection import ConnectionManager, connection_manager

# Aggregated router
router = APIRouter()
router.include_router(health_router)
router.include_router(transcription_router)
router.include_router(streaming_router)
router.include_router(tts_router)
router.include_router(gemini_live_router)

# Re-export llm_manager so existing test imports work
from app.services.llm_manager import llm_manager

__all__ = [
    "router",
    # Endpoint functions
    "websocket_streaming_tts",
    "websocket_tts",
    "websocket_gemini_live",
    "ping_endpoint",
    # Classes
    "WebSocketSecurityValidator",
    "JWTSecurityManager",
    "TextInputRateLimiter",
    "ConnectionManager",
    # Singletons
    "jwt_security",
    "text_rate_limiter",
    "connection_manager",
    "llm_manager",
]
