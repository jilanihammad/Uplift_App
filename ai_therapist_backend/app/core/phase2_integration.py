"""
Phase 2 Integration: Circuit Breaker + Provider Fallback

This module provides decorators and utilities to integrate Phase 2 optimizations
into the existing LLM manager without major refactoring.
"""

import functools
import asyncio
import logging
from typing import Callable, Any, AsyncGenerator

from app.core.circuit_breaker import circuit_breaker, PROVIDER_CONFIGS
from app.core.phase2_provider_fallback import get_smart_provider_fallback, stream_with_smart_fallback
from app.core.llm_config import ModelType, ModelProvider
from app.core.observability import record_counter, log_info

logger = logging.getLogger(__name__)


def with_circuit_breaker(provider: str, operation: str = ""):
    """
    Decorator to add circuit breaker protection to LLM methods.
    
    Args:
        provider: Provider name (e.g., "openai", "groq", "anthropic")
        operation: Operation type (e.g., "chat", "tts", "streaming")
    """
    def decorator(func: Callable) -> Callable:
        # Create circuit breaker name
        breaker_name = f"{provider}_{operation}_{func.__name__}" if operation else f"{provider}_{func.__name__}"
        
        # Get provider config or use default
        breaker_config = PROVIDER_CONFIGS.get(provider, PROVIDER_CONFIGS.get("default"))
        
        # Apply circuit breaker decorator
        @circuit_breaker(breaker_name, breaker_config)
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            # Record circuit breaker call
            record_counter(
                "circuit_breaker",
                "calls_total",
                labels={"provider": provider, "operation": operation, "method": func.__name__}
            )
            
            return await func(*args, **kwargs)
        
        return wrapper
    return decorator


def with_smart_fallback(model_type: ModelType):
    """
    Decorator to add smart provider fallback to streaming methods.
    
    This wraps streaming methods to automatically fallback to alternative
    providers if the primary provider fails.
    """
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def wrapper(*args, **kwargs) -> AsyncGenerator:
            try:
                # Try the original function first
                async for chunk in func(*args, **kwargs):
                    yield chunk
            except Exception as e:
                # If original fails, try smart fallback
                logger.warning(f"Primary provider failed, attempting fallback: {e}")
                
                async for chunk in stream_with_smart_fallback(
                    model_type, 
                    func, 
                    *args, 
                    **kwargs
                ):
                    yield chunk
        
        return wrapper
    return decorator


def with_provider_monitoring(provider: ModelProvider, model_type: ModelType):
    """
    Decorator to add provider health monitoring to methods.
    
    This tracks provider performance and updates health metrics
    for use in smart fallback decisions.
    """
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            import time
            start_time = time.time()
            
            try:
                result = await func(*args, **kwargs)
                
                # Record success metrics
                duration_ms = (time.time() - start_time) * 1000
                fallback = get_smart_provider_fallback()
                await fallback._record_success(provider, model_type, duration_ms)
                
                return result
                
            except Exception as e:
                # Record failure metrics
                duration_ms = (time.time() - start_time) * 1000
                fallback = get_smart_provider_fallback()
                await fallback._record_failure(provider, model_type, type(e).__name__, duration_ms)
                
                raise
        
        return wrapper
    return decorator


def create_circuit_breaker_decorators():
    """
    Create circuit breaker decorators for all major LLM operations.
    
    This provides a convenient way to get all the decorators needed
    for comprehensive circuit breaker protection.
    """
    return {
        # OpenAI decorators
        "openai_chat": with_circuit_breaker("openai", "chat"),
        "openai_streaming": with_circuit_breaker("openai", "streaming"),
        "openai_tts": with_circuit_breaker("openai", "tts"),
        
        # Groq decorators
        "groq_chat": with_circuit_breaker("groq", "chat"),
        "groq_streaming": with_circuit_breaker("groq", "streaming"),
        "groq_transcription": with_circuit_breaker("groq", "transcription"),
        
        # Anthropic decorators
        "anthropic_chat": with_circuit_breaker("anthropic", "chat"),
        "anthropic_streaming": with_circuit_breaker("anthropic", "streaming"),
        
        # Google decorators
        "google_chat": with_circuit_breaker("google", "chat"),
        "google_streaming": with_circuit_breaker("google", "streaming"),
        
        # Smart fallback decorators
        "llm_fallback": with_smart_fallback(ModelType.LLM),
        "tts_fallback": with_smart_fallback(ModelType.TTS)
    }


# Global decorator registry
CIRCUIT_BREAKER_DECORATORS = create_circuit_breaker_decorators()


def get_decorator(name: str):
    """Get a circuit breaker decorator by name."""
    return CIRCUIT_BREAKER_DECORATORS.get(name)


# Convenience decorators for common use cases
openai_chat = CIRCUIT_BREAKER_DECORATORS["openai_chat"]
openai_streaming = CIRCUIT_BREAKER_DECORATORS["openai_streaming"] 
openai_tts = CIRCUIT_BREAKER_DECORATORS["openai_tts"]

groq_chat = CIRCUIT_BREAKER_DECORATORS["groq_chat"]
groq_streaming = CIRCUIT_BREAKER_DECORATORS["groq_streaming"]
groq_transcription = CIRCUIT_BREAKER_DECORATORS["groq_transcription"]

anthropic_chat = CIRCUIT_BREAKER_DECORATORS["anthropic_chat"]
anthropic_streaming = CIRCUIT_BREAKER_DECORATORS["anthropic_streaming"]

google_chat = CIRCUIT_BREAKER_DECORATORS["google_chat"]
google_streaming = CIRCUIT_BREAKER_DECORATORS["google_streaming"]

llm_fallback = CIRCUIT_BREAKER_DECORATORS["llm_fallback"]
tts_fallback = CIRCUIT_BREAKER_DECORATORS["tts_fallback"]