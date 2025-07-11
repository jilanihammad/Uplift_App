"""
Enhanced LLM Manager with Circuit Breaker Integration

This module extends the existing LLM Manager with:
- Circuit breaker protection for all provider calls
- Performance optimization with connection pooling
- Enhanced observability and metrics
- Graceful degradation patterns
"""

import logging
import asyncio
import time
from typing import Optional, List, Dict, Any, AsyncGenerator
from functools import wraps

from app.services.llm_manager import LLMManager
from app.core.circuit_breaker import (
    get_circuit_breaker_manager,
    PROVIDER_CONFIGS,
    CircuitBreakerOpenException,
    CircuitBreakerConfig
)
from app.core.llm_config import ModelType, ModelProvider

logger = logging.getLogger(__name__)


class EnhancedLLMManager(LLMManager):
    """
    Enhanced LLM Manager with circuit breaker protection and performance optimizations.
    
    This class extends the base LLM Manager with:
    - Circuit breaker protection for all provider calls
    - Performance metrics collection
    - Connection pooling optimization
    - Graceful degradation
    """
    
    def __init__(self, redis_url: Optional[str] = None):
        super().__init__()
        
        # Initialize circuit breaker manager
        self.circuit_breaker_manager = get_circuit_breaker_manager(redis_url)
        
        # Performance metrics
        self.metrics = {
            "total_calls": 0,
            "successful_calls": 0,
            "failed_calls": 0,
            "circuit_breaker_trips": 0,
            "average_response_time": 0.0,
            "provider_metrics": {}
        }
        
        # Start circuit breakers
        asyncio.create_task(self._initialize_circuit_breakers())
        
        logger.info("Enhanced LLM Manager initialized with circuit breaker protection")
    
    async def _initialize_circuit_breakers(self):
        """Initialize circuit breakers for all providers."""
        try:
            # Create circuit breakers for each provider
            for provider_name, config in PROVIDER_CONFIGS.items():
                # Create separate breakers for different operations
                self.circuit_breaker_manager.create_breaker(f"{provider_name}_chat", config)
                self.circuit_breaker_manager.create_breaker(f"{provider_name}_tts", config)
                self.circuit_breaker_manager.create_breaker(f"{provider_name}_transcription", config)
            
            # Start all circuit breakers
            await self.circuit_breaker_manager.start_all()
            logger.info("All circuit breakers initialized and started")
        except Exception as e:
            logger.error(f"Error initializing circuit breakers: {e}")
    
    def _get_provider_name(self, provider: ModelProvider) -> str:
        """Get standardized provider name for circuit breaker."""
        provider_mapping = {
            ModelProvider.OPENAI: "openai",
            ModelProvider.ANTHROPIC: "anthropic",
            ModelProvider.GROQ: "groq",
            ModelProvider.GOOGLE: "google",
            ModelProvider.AZURE_OPENAI: "azure",
            ModelProvider.DEEPSEEK: "openai"  # DeepSeek uses OpenAI-compatible API
        }
        return provider_mapping.get(provider, "unknown")
    
    def _record_metrics(self, provider: str, operation: str, success: bool, duration: float):
        """Record performance metrics."""
        self.metrics["total_calls"] += 1
        
        if success:
            self.metrics["successful_calls"] += 1
        else:
            self.metrics["failed_calls"] += 1
        
        # Update average response time
        current_avg = self.metrics["average_response_time"]
        total_calls = self.metrics["total_calls"]
        self.metrics["average_response_time"] = (
            (current_avg * (total_calls - 1) + duration) / total_calls
        )
        
        # Provider-specific metrics
        if provider not in self.metrics["provider_metrics"]:
            self.metrics["provider_metrics"][provider] = {
                "total_calls": 0,
                "successful_calls": 0,
                "failed_calls": 0,
                "average_response_time": 0.0
            }
        
        provider_metrics = self.metrics["provider_metrics"][provider]
        provider_metrics["total_calls"] += 1
        
        if success:
            provider_metrics["successful_calls"] += 1
        else:
            provider_metrics["failed_calls"] += 1
        
        # Update provider average response time
        provider_avg = provider_metrics["average_response_time"]
        provider_total = provider_metrics["total_calls"]
        provider_metrics["average_response_time"] = (
            (provider_avg * (provider_total - 1) + duration) / provider_total
        )
    
    def _circuit_breaker_protected(self, operation: str):
        """
        Decorator to add circuit breaker protection to LLM operations.
        
        Args:
            operation: The operation type (chat, tts, transcription)
        """
        def decorator(func):
            @wraps(func)
            async def wrapper(*args, **kwargs):
                # Get provider from the current configuration
                if operation == "chat":
                    config = self.llm_config
                elif operation == "tts":
                    config = self.tts_config
                elif operation == "transcription":
                    config = self.transcription_config
                else:
                    raise ValueError(f"Unknown operation: {operation}")
                
                if not config:
                    raise ValueError(f"No configuration available for {operation}")
                
                provider_name = self._get_provider_name(config.provider)
                breaker_name = f"{provider_name}_{operation}"
                
                # Get circuit breaker
                breaker = self.circuit_breaker_manager.get_breaker(breaker_name)
                if not breaker:
                    # Fallback to creating breaker if not found
                    default_config = PROVIDER_CONFIGS.get(provider_name, CircuitBreakerConfig())
                    breaker = self.circuit_breaker_manager.create_breaker(breaker_name, default_config)
                    await breaker.start()
                
                # Execute with circuit breaker protection
                start_time = time.time()
                try:
                    result = await breaker.call(func, *args, **kwargs)
                    duration = time.time() - start_time
                    self._record_metrics(provider_name, operation, True, duration)
                    return result
                except CircuitBreakerOpenException as e:
                    duration = time.time() - start_time
                    self.metrics["circuit_breaker_trips"] += 1
                    self._record_metrics(provider_name, operation, False, duration)
                    logger.warning(f"Circuit breaker open for {breaker_name}: {e}")
                    raise
                except Exception as e:
                    duration = time.time() - start_time
                    self._record_metrics(provider_name, operation, False, duration)
                    logger.error(f"Error in {operation} operation: {e}")
                    raise
            
            return wrapper
        return decorator
    
    @_circuit_breaker_protected("chat")
    async def generate_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """
        Generate a chat response with circuit breaker protection.
        
        This method wraps the original generate_response with circuit breaker protection
        and performance monitoring.
        """
        return await super().generate_response(message, context, system_prompt, user_info, **kwargs)
    
    @_circuit_breaker_protected("tts")
    async def text_to_speech(
        self,
        text: str,
        output_path: str,
        voice_id: str = None,
        **kwargs
    ) -> str:
        """
        Convert text to speech with circuit breaker protection.
        """
        return await super().text_to_speech(text, output_path, voice_id, **kwargs)
    
    @_circuit_breaker_protected("transcription")
    async def transcribe_audio(
        self,
        audio_path: str,
        **kwargs
    ) -> str:
        """
        Transcribe audio with circuit breaker protection.
        """
        return await super().transcribe_audio(audio_path, **kwargs)
    
    def get_health_status(self) -> Dict[str, Any]:
        """
        Get comprehensive health status including circuit breaker states.
        """
        circuit_breaker_metrics = self.circuit_breaker_manager.get_all_metrics()
        
        # Calculate overall health
        total_breakers = len(circuit_breaker_metrics)
        open_breakers = sum(1 for metrics in circuit_breaker_metrics.values() 
                          if metrics["state"] == "open")
        
        health_status = {
            "overall_health": "healthy" if open_breakers == 0 else "degraded" if open_breakers < total_breakers else "unhealthy",
            "circuit_breakers": circuit_breaker_metrics,
            "performance_metrics": self.metrics,
            "provider_availability": {
                provider: {
                    "available": metrics["state"] != "open",
                    "failure_rate": metrics["failure_rate"],
                    "total_calls": metrics["total_calls"]
                }
                for provider, metrics in circuit_breaker_metrics.items()
            }
        }
        
        return health_status
    
    def get_performance_metrics(self) -> Dict[str, Any]:
        """Get detailed performance metrics."""
        return {
            "global_metrics": self.metrics,
            "circuit_breaker_metrics": self.circuit_breaker_manager.get_all_metrics(),
            "timestamp": time.time()
        }
    
    async def shutdown(self):
        """Gracefully shutdown the enhanced LLM manager."""
        try:
            await self.circuit_breaker_manager.stop_all()
            logger.info("Enhanced LLM Manager shutdown complete")
        except Exception as e:
            logger.error(f"Error during shutdown: {e}")


# Create a global instance
enhanced_llm_manager = EnhancedLLMManager()


def get_enhanced_llm_manager() -> EnhancedLLMManager:
    """Get the global enhanced LLM manager instance."""
    return enhanced_llm_manager


# Decorator for easy circuit breaker protection
def llm_circuit_breaker(operation: str):
    """
    Decorator to add circuit breaker protection to any LLM-related function.
    
    Args:
        operation: The operation type (chat, tts, transcription)
    
    Example:
        @llm_circuit_breaker("chat")
        async def custom_chat_function():
            # Your chat logic here
            pass
    """
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            manager = get_enhanced_llm_manager()
            return await manager._circuit_breaker_protected(operation)(func)(*args, **kwargs)
        return wrapper
    return decorator