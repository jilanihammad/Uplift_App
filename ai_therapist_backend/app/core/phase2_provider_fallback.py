"""
Phase 2: Circuit Breaker + Smart Provider Fallback

This module implements Phase 2 optimizations for the speed-first backend plan:
1. Circuit breaker integration for all LLM providers
2. Smart provider fallback chain (OpenAI → Groq → Anthropic → Google)
3. Latency-based provider selection 
4. Error rate tracking per provider
5. Automatic failover with minimal latency impact

Target: 99.9% availability with <50ms failover overhead
"""

import asyncio
import logging
import time
from typing import Dict, List, Optional, Any, Tuple, AsyncGenerator
from dataclasses import dataclass, field
from enum import Enum
import json

from app.core.circuit_breaker import (
    get_circuit_breaker_manager, 
    CircuitBreakerConfig,
    CircuitBreakerOpenException,
    PROVIDER_CONFIGS
)
from app.core.observability import record_latency, record_counter, log_info, log_error, log_warning
from app.core.llm_config import LLMConfig, ModelProvider, ModelType

logger = logging.getLogger(__name__)


class ProviderPriority(Enum):
    """Provider priority levels for fallback chain."""
    PRIMARY = 1
    SECONDARY = 2
    TERTIARY = 3
    QUATERNARY = 4
    LAST_RESORT = 5


@dataclass
class ProviderHealth:
    """Health metrics for a provider."""
    provider: ModelProvider
    available: bool = True
    avg_latency_ms: float = 0.0
    error_rate: float = 0.0
    circuit_breaker_state: str = "closed"
    last_success_time: Optional[float] = None
    last_failure_time: Optional[float] = None
    consecutive_failures: int = 0
    total_requests: int = 0
    successful_requests: int = 0


@dataclass
class FallbackConfig:
    """Configuration for provider fallback behavior."""
    # Fallback chain configuration
    llm_fallback_chain: List[ModelProvider] = field(default_factory=lambda: [
        ModelProvider.OPENAI,      # Primary - reliable, good latency
        ModelProvider.GROQ,        # Secondary - very fast when available
        ModelProvider.ANTHROPIC,   # Tertiary - reliable backup
        ModelProvider.GOOGLE       # Quaternary - last resort
    ])
    
    tts_fallback_chain: List[ModelProvider] = field(default_factory=lambda: [
        ModelProvider.OPENAI,      # Primary - best quality
        ModelProvider.GOOGLE,      # Secondary - good alternative
        ModelProvider.AZURE_OPENAI # Tertiary - if configured
    ])
    
    # Latency thresholds for provider selection
    max_acceptable_latency_ms: float = 1000.0  # 1 second
    prefer_fast_provider_threshold_ms: float = 500.0  # Switch to faster provider if available
    
    # Error handling
    max_consecutive_failures: int = 3
    provider_timeout_ms: float = 5000.0  # 5 seconds per provider attempt
    
    # Circuit breaker integration
    use_circuit_breakers: bool = True
    circuit_breaker_configs: Dict[ModelProvider, CircuitBreakerConfig] = field(default_factory=dict)
    
    def __post_init__(self):
        # Use pre-configured circuit breaker settings if not provided
        if not self.circuit_breaker_configs:
            self.circuit_breaker_configs = {
                ModelProvider.OPENAI: PROVIDER_CONFIGS["openai"],
                ModelProvider.GROQ: PROVIDER_CONFIGS["groq"],
                ModelProvider.ANTHROPIC: PROVIDER_CONFIGS["anthropic"],
                ModelProvider.GOOGLE: PROVIDER_CONFIGS["google"],
                ModelProvider.AZURE_OPENAI: PROVIDER_CONFIGS.get("azure", PROVIDER_CONFIGS["default"])
            }


class SmartProviderFallback:
    """
    Smart provider fallback system with circuit breaker integration.
    
    This class implements intelligent provider selection based on:
    - Circuit breaker states
    - Current latency metrics
    - Error rates
    - Provider availability
    """
    
    def __init__(self, config: FallbackConfig = None):
        self.config = config or FallbackConfig()
        self.provider_health: Dict[ModelProvider, ProviderHealth] = {}
        self.circuit_breaker_manager = get_circuit_breaker_manager()
        
        # Initialize provider health tracking
        self._initialize_provider_health()
        
    def _initialize_provider_health(self):
        """Initialize health tracking for all providers."""
        all_providers = list(ModelProvider)
        for provider in all_providers:
            self.provider_health[provider] = ProviderHealth(provider=provider)
    
    async def get_best_provider(
        self, 
        model_type: ModelType,
        prefer_speed: bool = True
    ) -> Tuple[ModelProvider, str]:
        """
        Get the best available provider based on current health metrics.
        
        Returns:
            Tuple of (provider, reason) where reason explains the selection
        """
        # Get appropriate fallback chain
        if model_type == ModelType.LLM:
            fallback_chain = self.config.llm_fallback_chain
        elif model_type == ModelType.TTS:
            fallback_chain = self.config.tts_fallback_chain
        else:
            # For other types, try to get configured provider
            config = LLMConfig.get_active_model_config(model_type)
            if config:
                return config.provider, "configured_provider"
            raise ValueError(f"No fallback chain for model type: {model_type}")
        
        # Check providers in order
        available_providers = []
        
        for provider in fallback_chain:
            health = self.provider_health[provider]
            
            # Check if provider is configured
            if not self._is_provider_configured(provider, model_type):
                continue
            
            # Check circuit breaker state
            if self.config.use_circuit_breakers:
                breaker_state = await self._get_circuit_breaker_state(provider, model_type)
                health.circuit_breaker_state = breaker_state
                
                if breaker_state == "open":
                    logger.debug(f"Provider {provider} circuit breaker is open, skipping")
                    continue
            
            # Check error rate
            if health.error_rate > 0.5:  # >50% error rate
                logger.debug(f"Provider {provider} has high error rate: {health.error_rate:.1%}")
                continue
            
            # Add to available providers
            available_providers.append((provider, health))
        
        if not available_providers:
            # All providers are down, try the primary anyway
            primary = fallback_chain[0]
            logger.warning(f"All providers unavailable, attempting primary: {primary}")
            return primary, "all_providers_down_using_primary"
        
        # Select based on strategy
        if prefer_speed and len(available_providers) > 1:
            # Sort by latency and pick fastest
            available_providers.sort(key=lambda x: x[1].avg_latency_ms)
            fastest = available_providers[0]
            
            # Only switch if significantly faster
            primary = available_providers[0] if available_providers[0][0] in fallback_chain[:2] else available_providers[0]
            if fastest[1].avg_latency_ms < primary[1].avg_latency_ms - 100:  # 100ms threshold
                return fastest[0], f"fastest_provider_latency_{fastest[1].avg_latency_ms:.0f}ms"
        
        # Default: return first available in priority order
        selected = available_providers[0]
        return selected[0], f"primary_available_latency_{selected[1].avg_latency_ms:.0f}ms"
    
    def _is_provider_configured(self, provider: ModelProvider, model_type: ModelType) -> bool:
        """Check if a provider is configured for the given model type."""
        try:
            # Check if we have API key for this provider
            configs = LLMConfig.get_provider_configs(provider)
            for config in configs:
                if config.model_type == model_type:
                    api_key = LLMConfig.get_api_key(config)
                    return api_key is not None and api_key != ""
            return False
        except Exception:
            return False
    
    async def _get_circuit_breaker_state(self, provider: ModelProvider, model_type: ModelType) -> str:
        """Get current circuit breaker state for a provider."""
        try:
            breaker_name = f"{provider.value}_{model_type.value}"
            breaker = self.circuit_breaker_manager.get_breaker(breaker_name)
            
            if breaker:
                metrics = breaker.get_metrics()
                return metrics.get("state", "closed")
            
            return "closed"  # No breaker = assumed closed
        except Exception as e:
            logger.debug(f"Error getting circuit breaker state: {e}")
            return "unknown"
    
    async def execute_with_fallback(
        self,
        model_type: ModelType,
        primary_func,
        *args,
        **kwargs
    ) -> Any:
        """
        Execute a function with automatic provider fallback.
        
        This wraps any LLM/TTS function call with intelligent fallback.
        """
        fallback_chain = (
            self.config.llm_fallback_chain if model_type == ModelType.LLM 
            else self.config.tts_fallback_chain
        )
        
        last_exception = None
        attempted_providers = []
        
        for i, provider in enumerate(fallback_chain):
            if not self._is_provider_configured(provider, model_type):
                continue
            
            attempted_providers.append(provider)
            start_time = time.time()
            
            try:
                # Log attempt
                await log_info(
                    "provider_fallback",
                    f"Attempting {model_type.value} call with provider {provider.value}",
                    provider=provider.value,
                    attempt=i+1,
                    total_providers=len(fallback_chain)
                )
                
                # Set provider override for this attempt
                original_provider = self._override_provider(model_type, provider)
                
                try:
                    # Execute with timeout
                    result = await asyncio.wait_for(
                        primary_func(*args, **kwargs),
                        timeout=self.config.provider_timeout_ms / 1000.0
                    )
                    
                    # Success! Update metrics
                    duration_ms = (time.time() - start_time) * 1000
                    await self._record_success(provider, model_type, duration_ms)
                    
                    return result
                    
                finally:
                    # Restore original provider
                    self._restore_provider(model_type, original_provider)
                    
            except asyncio.TimeoutError:
                duration_ms = (time.time() - start_time) * 1000
                await self._record_failure(provider, model_type, "timeout", duration_ms)
                last_exception = TimeoutError(f"Provider {provider.value} timed out after {duration_ms:.0f}ms")
                
            except CircuitBreakerOpenException as e:
                # Circuit breaker is open, move to next provider immediately
                await self._record_failure(provider, model_type, "circuit_breaker_open", 0)
                last_exception = e
                
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                await self._record_failure(provider, model_type, type(e).__name__, duration_ms)
                last_exception = e
                
                # Log the error
                await log_warning(
                    "provider_fallback",
                    f"Provider {provider.value} failed, trying next",
                    provider=provider.value,
                    error=str(e),
                    duration_ms=duration_ms
                )
        
        # All providers failed
        await log_error(
            "provider_fallback",
            f"All providers failed for {model_type.value}",
            attempted_providers=[p.value for p in attempted_providers],
            last_error=str(last_exception)
        )
        
        raise last_exception or Exception("All providers failed")
    
    async def execute_streaming_with_fallback(
        self,
        model_type: ModelType,
        streaming_func,
        *args,
        **kwargs
    ) -> AsyncGenerator:
        """
        Execute a streaming function with automatic provider fallback.
        
        This is for streaming responses (chat, TTS) with intelligent fallback.
        """
        fallback_chain = (
            self.config.llm_fallback_chain if model_type == ModelType.LLM 
            else self.config.tts_fallback_chain
        )
        
        last_exception = None
        attempted_providers = []
        
        for i, provider in enumerate(fallback_chain):
            if not self._is_provider_configured(provider, model_type):
                continue
            
            attempted_providers.append(provider)
            start_time = time.time()
            first_chunk_time = None
            
            try:
                # Set provider override
                original_provider = self._override_provider(model_type, provider)
                
                try:
                    # Create streaming generator with timeout handling
                    async def timeout_generator():
                        nonlocal first_chunk_time
                        chunk_count = 0
                        
                        async for chunk in streaming_func(*args, **kwargs):
                            if chunk_count == 0:
                                first_chunk_time = time.time()
                                ttfb = (first_chunk_time - start_time) * 1000
                                
                                # Record TTFB
                                record_latency(
                                    f"{model_type.value}_streaming",
                                    "ttfb",
                                    ttfb,
                                    labels={"provider": provider.value}
                                )
                            
                            chunk_count += 1
                            yield chunk
                    
                    # Stream with overall timeout
                    timeout_task = asyncio.create_task(
                        asyncio.sleep(self.config.provider_timeout_ms / 1000.0)
                    )
                    
                    async for chunk in timeout_generator():
                        if timeout_task.done():
                            raise asyncio.TimeoutError(f"Streaming timeout for {provider.value}")
                        yield chunk
                    
                    # Success! Cancel timeout and update metrics
                    timeout_task.cancel()
                    duration_ms = (time.time() - start_time) * 1000
                    await self._record_success(provider, model_type, duration_ms)
                    
                    return  # Successfully completed streaming
                    
                finally:
                    # Restore original provider
                    self._restore_provider(model_type, original_provider)
                    
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                await self._record_failure(provider, model_type, type(e).__name__, duration_ms)
                last_exception = e
                
                # Try next provider
                continue
        
        # All providers failed
        raise last_exception or Exception("All streaming providers failed")
    
    def _override_provider(self, model_type: ModelType, provider: ModelProvider) -> Optional[ModelProvider]:
        """Override the active provider temporarily."""
        # This would integrate with LLMConfig to override the provider
        # For now, return None as placeholder
        return None
    
    def _restore_provider(self, model_type: ModelType, original_provider: Optional[ModelProvider]):
        """Restore the original provider."""
        # This would integrate with LLMConfig to restore the provider
        pass
    
    async def _record_success(self, provider: ModelProvider, model_type: ModelType, duration_ms: float):
        """Record successful provider call."""
        health = self.provider_health[provider]
        
        # Update health metrics
        health.total_requests += 1
        health.successful_requests += 1
        health.consecutive_failures = 0
        health.last_success_time = time.time()
        
        # Update rolling average latency (simple exponential moving average)
        alpha = 0.2  # Smoothing factor
        if health.avg_latency_ms == 0:
            health.avg_latency_ms = duration_ms
        else:
            health.avg_latency_ms = alpha * duration_ms + (1 - alpha) * health.avg_latency_ms
        
        # Update error rate
        health.error_rate = 1.0 - (health.successful_requests / health.total_requests)
        
        # Record metrics
        record_latency(
            "provider_fallback",
            f"{model_type.value}_success",
            duration_ms,
            labels={"provider": provider.value}
        )
        
        record_counter(
            "provider_fallback",
            f"{model_type.value}_requests",
            labels={"provider": provider.value, "status": "success"}
        )
    
    async def _record_failure(self, provider: ModelProvider, model_type: ModelType, 
                            error_type: str, duration_ms: float):
        """Record failed provider call."""
        health = self.provider_health[provider]
        
        # Update health metrics
        health.total_requests += 1
        health.consecutive_failures += 1
        health.last_failure_time = time.time()
        
        # Update error rate
        health.error_rate = 1.0 - (health.successful_requests / health.total_requests)
        
        # Record metrics
        record_latency(
            "provider_fallback",
            f"{model_type.value}_failure",
            duration_ms,
            labels={"provider": provider.value, "error": error_type}
        )
        
        record_counter(
            "provider_fallback",
            f"{model_type.value}_requests",
            labels={"provider": provider.value, "status": "failure", "error": error_type}
        )
    
    def get_provider_health_status(self) -> Dict[str, Any]:
        """Get current health status of all providers."""
        return {
            provider.value: {
                "available": health.available,
                "avg_latency_ms": round(health.avg_latency_ms, 1),
                "error_rate": round(health.error_rate * 100, 1),
                "circuit_breaker_state": health.circuit_breaker_state,
                "consecutive_failures": health.consecutive_failures,
                "total_requests": health.total_requests,
                "success_rate": round(
                    (health.successful_requests / health.total_requests * 100) 
                    if health.total_requests > 0 else 0, 1
                )
            }
            for provider, health in self.provider_health.items()
            if health.total_requests > 0  # Only show providers that have been used
        }
    
    def get_fallback_chains(self) -> Dict[str, List[str]]:
        """Get configured fallback chains."""
        return {
            "llm": [p.value for p in self.config.llm_fallback_chain],
            "tts": [p.value for p in self.config.tts_fallback_chain]
        }


# Global provider fallback instance
_smart_provider_fallback: Optional[SmartProviderFallback] = None


def get_smart_provider_fallback() -> SmartProviderFallback:
    """Get the global smart provider fallback instance."""
    global _smart_provider_fallback
    if _smart_provider_fallback is None:
        _smart_provider_fallback = SmartProviderFallback()
    return _smart_provider_fallback


async def execute_with_smart_fallback(
    model_type: ModelType,
    func,
    *args,
    **kwargs
) -> Any:
    """Execute a function with smart provider fallback."""
    fallback = get_smart_provider_fallback()
    return await fallback.execute_with_fallback(model_type, func, *args, **kwargs)


async def stream_with_smart_fallback(
    model_type: ModelType,
    streaming_func,
    *args,
    **kwargs
) -> AsyncGenerator:
    """Execute a streaming function with smart provider fallback."""
    fallback = get_smart_provider_fallback()
    async for chunk in fallback.execute_streaming_with_fallback(
        model_type, streaming_func, *args, **kwargs
    ):
        yield chunk