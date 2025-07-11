"""
AIService Stub for Safe Migration

This stub replaces the deprecated AIService class to provide clear error messages
for any remaining imports while the migration to LLMManager is completed.

This file will be removed after the migration is fully complete and all references
have been updated to use the unified LLMManager.
"""

import logging
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class AIService:
    """
    Deprecated AIService stub that provides clear migration guidance.
    
    This class has been replaced with the unified LLMManager for better
    performance, reliability, and maintainability.
    """
    
    def __init__(self, *args, **kwargs):
        """
        Raises ImportError with clear migration instructions.
        """
        error_message = (
            "AIService has been deprecated and replaced with LLMManager.\n"
            "Please update your imports to use:\n"
            "  from app.services.llm_manager import llm_manager\n"
            "\n"
            "Migration guide:\n"
            "- ai_service.generate_response() → llm_manager.generate_response()\n"
            "- ai_service.text_to_speech() → llm_manager.text_to_speech()\n"
            "- ai_service.transcribe_audio() → llm_manager.transcribe_audio()\n"
            "\n"
            "See backendRefactor.md for complete migration guide."
        )
        
        logger.error(f"AIService deprecated usage attempted: {error_message}")
        raise ImportError(error_message)
    
    def __getattr__(self, name: str) -> Any:
        """
        Intercept any attribute access to provide migration guidance.
        """
        error_message = (
            f"AIService.{name} is deprecated. Use LLMManager instead.\n"
            "Import with: from app.services.llm_manager import llm_manager\n"
            "Then use: llm_manager.{name}()"
        )
        
        logger.error(f"AIService.{name} deprecated usage attempted")
        raise ImportError(error_message)
    
    def __call__(self, *args, **kwargs) -> Any:
        """
        Intercept any attempt to call the service as a function.
        """
        error_message = (
            "AIService() is deprecated. Use LLMManager instead.\n"
            "Import with: from app.services.llm_manager import llm_manager"
        )
        
        logger.error("AIService() deprecated usage attempted")
        raise ImportError(error_message)


# Provide clear error for common import patterns
def get_ai_service() -> None:
    """
    Deprecated factory function for AIService.
    """
    error_message = (
        "get_ai_service() is deprecated. Use LLMManager instead.\n"
        "Import with: from app.services.llm_manager import llm_manager"
    )
    
    logger.error("get_ai_service() deprecated usage attempted")
    raise ImportError(error_message)


# Legacy module-level instance that might be imported
ai_service = AIService()