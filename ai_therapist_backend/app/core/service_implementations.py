"""
Service Implementations for Early DI Container

This module provides concrete implementations of the service interfaces
for the early dependency injection container.
"""

import asyncio
import logging
from typing import Dict, Any, Callable, Optional

from app.core.dependency_container import (
    ICircuitBreakerService,
    IObservabilityService,
    IHTTPClientService,
    IWarmupService
)
from app.core.circuit_breaker import get_circuit_breaker_manager
from app.core.observability import observability_manager
from app.core.http_client_manager import get_http_client_manager
from app.core.container_warmup import get_container_warmup

logger = logging.getLogger(__name__)


class CircuitBreakerService(ICircuitBreakerService):
    """Concrete implementation of circuit breaker service."""
    
    def __init__(self):
        self._circuit_breaker_manager = None
        self._initialized = False
        
    async def initialize(self) -> None:
        """Initialize the circuit breaker service."""
        if self._initialized:
            return
        
        self._circuit_breaker_manager = get_circuit_breaker_manager()
        await self._circuit_breaker_manager.start_all()
        self._initialized = True
        
        logger.info("Circuit breaker service initialized")
    
    async def dispose(self) -> None:
        """Dispose of the circuit breaker service."""
        if self._circuit_breaker_manager:
            await self._circuit_breaker_manager.stop_all()
        
        self._initialized = False
        logger.info("Circuit breaker service disposed")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get circuit breaker service health status."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        if not self._circuit_breaker_manager:
            return {"status": "error", "error": "Circuit breaker manager not available"}
        
        metrics = self._circuit_breaker_manager.get_all_metrics()
        
        # Calculate overall health
        total_breakers = len(metrics)
        open_breakers = sum(1 for m in metrics.values() if m["state"] == "open")
        
        return {
            "status": "healthy" if open_breakers == 0 else "degraded",
            "total_breakers": total_breakers,
            "open_breakers": open_breakers,
            "breaker_metrics": metrics
        }
    
    async def call_with_protection(self, provider: str, operation: str, 
                                  func: Callable, *args, **kwargs) -> Any:
        """Call function with circuit breaker protection."""
        if not self._initialized:
            raise RuntimeError("Circuit breaker service not initialized")
        
        breaker_name = f"{provider}_{operation}"
        breaker = self._circuit_breaker_manager.get_breaker(breaker_name)
        
        if not breaker:
            # Create breaker if not exists
            from app.core.circuit_breaker import PROVIDER_CONFIGS, CircuitBreakerConfig
            config = PROVIDER_CONFIGS.get(provider, CircuitBreakerConfig())
            breaker = self._circuit_breaker_manager.create_breaker(breaker_name, config)
            await breaker.start()
        
        return await breaker.call(func, *args, **kwargs)
    
    def get_breaker_status(self, provider: str) -> Dict[str, Any]:
        """Get circuit breaker status for provider."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        metrics = self._circuit_breaker_manager.get_all_metrics()
        provider_metrics = {
            name: data for name, data in metrics.items()
            if name.startswith(f"{provider}_")
        }
        
        return {
            "provider": provider,
            "breakers": provider_metrics,
            "overall_status": "healthy" if all(
                m["state"] != "open" for m in provider_metrics.values()
            ) else "degraded"
        }


class ObservabilityService(IObservabilityService):
    """Concrete implementation of observability service."""
    
    def __init__(self):
        self._observability_manager = None
        self._initialized = False
        
    async def initialize(self) -> None:
        """Initialize the observability service."""
        if self._initialized:
            return
        
        self._observability_manager = observability_manager
        await self._observability_manager.start()
        self._initialized = True
        
        logger.info("Observability service initialized")
    
    async def dispose(self) -> None:
        """Dispose of the observability service."""
        if self._observability_manager:
            await self._observability_manager.stop()
        
        self._initialized = False
        logger.info("Observability service disposed")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get observability service health status."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        if not self._observability_manager:
            return {"status": "error", "error": "Observability manager not available"}
        
        return self._observability_manager.get_health_status()
    
    async def log_event(self, level: str, service: str, message: str, **kwargs) -> None:
        """Log an event."""
        if not self._initialized:
            raise RuntimeError("Observability service not initialized")
        
        await self._observability_manager.log_async(level, service, message, **kwargs)
    
    def record_metric(self, name: str, value: float, labels: Dict[str, str] = None) -> None:
        """Record a metric."""
        if not self._initialized:
            raise RuntimeError("Observability service not initialized")
        
        self._observability_manager.record_metric(name, value, labels)
    
    def get_metrics_summary(self) -> Dict[str, Any]:
        """Get metrics summary."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        return self._observability_manager.metrics_collector.get_metrics_summary()


class HTTPClientService(IHTTPClientService):
    """Concrete implementation of HTTP client service."""
    
    def __init__(self):
        self._http_client_manager = None
        self._initialized = False
        
    async def initialize(self) -> None:
        """Initialize the HTTP client service."""
        if self._initialized:
            return
        
        self._http_client_manager = get_http_client_manager()
        await self._http_client_manager.start_all_clients()
        self._initialized = True
        
        logger.info("HTTP client service initialized")
    
    async def dispose(self) -> None:
        """Dispose of the HTTP client service."""
        if self._http_client_manager:
            await self._http_client_manager.stop_all_clients()
        
        self._initialized = False
        logger.info("HTTP client service disposed")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get HTTP client service health status."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        if not self._http_client_manager:
            return {"status": "error", "error": "HTTP client manager not available"}
        
        return self._http_client_manager.get_health_status()
    
    async def get_client(self, provider: str) -> Any:
        """Get HTTP client for provider."""
        if not self._initialized:
            raise RuntimeError("HTTP client service not initialized")
        
        return self._http_client_manager.get_client(provider)
    
    def get_client_stats(self) -> Dict[str, Any]:
        """Get client statistics."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        return self._http_client_manager.get_all_stats()


class WarmupService(IWarmupService):
    """Concrete implementation of warm-up service."""
    
    def __init__(self):
        self._warmup_manager = None
        self._initialized = False
        
    async def initialize(self) -> None:
        """Initialize the warm-up service."""
        if self._initialized:
            return
        
        self._warmup_manager = get_container_warmup()
        self._initialized = True
        
        logger.info("Warm-up service initialized")
    
    async def dispose(self) -> None:
        """Dispose of the warm-up service."""
        self._initialized = False
        logger.info("Warm-up service disposed")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get warm-up service health status."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        if not self._warmup_manager:
            return {"status": "error", "error": "Warm-up manager not available"}
        
        return {
            "status": "healthy",
            "warmup_status": self._warmup_manager.get_warmup_status()
        }
    
    async def run_warmup(self, config: Any = None) -> Dict[str, Any]:
        """Run warm-up process."""
        if not self._initialized:
            raise RuntimeError("Warm-up service not initialized")
        
        return await self._warmup_manager.run_full_warmup()
    
    def get_warmup_status(self) -> Dict[str, Any]:
        """Get warm-up status."""
        if not self._initialized:
            return {"status": "not_initialized"}
        
        return self._warmup_manager.get_warmup_status()


# Service registration helper
def register_all_services():
    """Register all service implementations with the DI container."""
    from app.core.dependency_container import get_container
    
    container = get_container()
    
    # Register services
    container.register_singleton(ICircuitBreakerService, CircuitBreakerService)
    container.register_singleton(IObservabilityService, ObservabilityService)
    container.register_singleton(IHTTPClientService, HTTPClientService)
    container.register_singleton(IWarmupService, WarmupService)
    
    logger.info("All services registered with DI container")
    
    return container


# Convenience functions for service access
async def get_circuit_breaker_service() -> ICircuitBreakerService:
    """Get circuit breaker service."""
    from app.core.dependency_container import get_service
    return await get_service(ICircuitBreakerService)


async def get_observability_service() -> IObservabilityService:
    """Get observability service."""
    from app.core.dependency_container import get_service
    return await get_service(IObservabilityService)


async def get_http_client_service() -> IHTTPClientService:
    """Get HTTP client service."""
    from app.core.dependency_container import get_service
    return await get_service(IHTTPClientService)


async def get_warmup_service() -> IWarmupService:
    """Get warm-up service."""
    from app.core.dependency_container import get_service
    return await get_service(IWarmupService)