"""
Health check module to monitor service status and ensure the API can respond
regardless of individual service status.
"""

import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def get_health_status():
    """Get the health status of all services"""
    
    health_info = {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "environment": os.environ.get("ENVIRONMENT", "development"),
        "port": os.environ.get("PORT", "8080"),
        "services": {
            "api": "available"
        }
    }
    
    # Check TTS service
    try:
        from app.services.voice_service import voice_service
        if hasattr(voice_service, 'api_key') and voice_service.api_key:
            health_info["services"]["openai_tts"] = "available"
        else:
            health_info["services"]["openai_tts"] = "unavailable - no API key"
    except Exception as e:
        logger.warning(f"TTS service health check failed: {str(e)}")
        health_info["services"]["openai_tts"] = f"unavailable - {str(e)}"
    
    # Check transcription service
    try:
        from app.services.transcription_service import transcription_service
        if hasattr(transcription_service, 'available') and transcription_service.available:
            health_info["services"]["groq_transcription"] = "available"
        else:
            health_info["services"]["groq_transcription"] = "unavailable - not properly initialized"
    except Exception as e:
        logger.warning(f"Transcription service health check failed: {str(e)}")
        health_info["services"]["groq_transcription"] = f"unavailable - {str(e)}"
    
    # Check LLM service
    try:
        from app.core.config import settings
        if settings.GROQ_API_KEY:
            health_info["services"]["groq_llm"] = "available"
        else:
            health_info["services"]["groq_llm"] = "unavailable - no API key"
    except Exception as e:
        logger.warning(f"LLM service health check failed: {str(e)}")
        health_info["services"]["groq_llm"] = f"unavailable - {str(e)}"
    
    return health_info 