"""
High-Performance Circuit Breaker Implementation

This module provides a circuit breaker pattern optimized for minimal latency impact
with per-provider state management and Redis fallback support.

Features:
- Sub-microsecond memory lookups
- Parallel probe execution for half-open states
- Graceful Redis degradation
- Per-provider configuration
- Failure rate-based thresholds
"""

import asyncio
import logging
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, Optional, Callable, Any, Union
import weakref

logger = logging.getLogger(__name__)


class CircuitBreakerState(Enum):
    """Circuit breaker states."""
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


@dataclass
class CircuitBreakerConfig:
    """Configuration for circuit breaker behavior."""
    fail_ratio: float = 0.5  # 50% failure rate threshold
    minimum_calls: int = 20  # Minimum calls before evaluation
    reset_timeout: int = 60  # Seconds to wait before trying half-open
    expected_exceptions: tuple = ()  # Expected exception types
    success_threshold: int = 5  # Successes needed to close from half-open
    
    def __post_init__(self):
        if not (0 <= self.fail_ratio <= 1):
            raise ValueError("fail_ratio must be between 0 and 1")
        if self.minimum_calls < 1:
            raise ValueError("minimum_calls must be at least 1")
        if self.reset_timeout < 1:
            raise ValueError("reset_timeout must be at least 1")


@dataclass
class CircuitBreakerMetrics:
    """Metrics for circuit breaker state."""
    total_calls: int = 0
    failed_calls: int = 0
    success_calls: int = 0
    last_failure_time: float = 0
    consecutive_successes: int = 0
    state_changes: int = 0
    
    @property
    def failure_rate(self) -> float:
        """Calculate current failure rate."""
        if self.total_calls == 0:
            return 0.0
        return self.failed_calls / self.total_calls
    
    def reset_window(self):
        """Reset the metrics window."""
        self.total_calls = 0
        self.failed_calls = 0
        self.success_calls = 0
        self.consecutive_successes = 0


class StateStore(ABC):
    """Abstract base class for circuit breaker state storage."""
    
    @abstractmethod
    async def get_state(self, key: str) -> Optional[Dict[str, Any]]:
        """Get circuit breaker state."""
        pass
    
    @abstractmethod
    async def set_state(self, key: str, state: Dict[str, Any]) -> None:
        """Set circuit breaker state."""
        pass


class MemoryStateStore(StateStore):
    """In-memory state store with high performance."""
    
    def __init__(self):
        self.store: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()
    
    async def get_state(self, key: str) -> Optional[Dict[str, Any]]:
        """Get state from memory - sub-microsecond operation."""
        return self.store.get(key)
    
    async def set_state(self, key: str, state: Dict[str, Any]) -> None:
        """Set state in memory."""
        async with self._lock:
            self.store[key] = state


class RedisStateStore(StateStore):
    """Redis-backed state store with fallback to memory."""
    
    def __init__(self, redis_url: Optional[str] = None):
        self.redis_client = None
        self.memory_fallback = MemoryStateStore()
        self.redis_available = False
        
        if redis_url:
            try:
                import redis.asyncio as redis
                self.redis_client = redis.from_url(redis_url)
                self.redis_available = True
                logger.info("Redis circuit breaker state store initialized")
            except Exception as e:
                logger.warning(f"Redis unavailable, using memory fallback: {e}")
                self.redis_available = False
    
    async def get_state(self, key: str) -> Optional[Dict[str, Any]]:
        """Get state from Redis with memory fallback."""
        if self.redis_available and self.redis_client:
            try:
                data = await self.redis_client.hgetall(key)
                if data:
                    return {k.decode(): v.decode() for k, v in data.items()}
            except Exception as e:
                logger.warning(f"Redis get failed, using memory fallback: {e}")
                self.redis_available = False
        
        return await self.memory_fallback.get_state(key)
    
    async def set_state(self, key: str, state: Dict[str, Any]) -> None:
        """Set state in Redis with memory fallback."""
        if self.redis_available and self.redis_client:
            try:
                await self.redis_client.hset(key, mapping=state)
                return
            except Exception as e:
                logger.warning(f"Redis set failed, using memory fallback: {e}")
                self.redis_available = False
        
        await self.memory_fallback.set_state(key, state)


class FastCircuitBreaker:
    """
    High-performance circuit breaker with sub-microsecond latency.
    
    Features:
    - Memory-first lookups for minimal latency
    - Parallel probe execution
    - Graceful Redis degradation
    - Per-provider configuration
    """
    
    def __init__(
        self,
        name: str,
        config: CircuitBreakerConfig,
        state_store: Optional[StateStore] = None
    ):
        self.name = name
        self.config = config
        self.state_store = state_store or MemoryStateStore()
        
        # Hot cache for sub-microsecond lookups
        self.memory_cache: Dict[str, Any] = {
            "state": CircuitBreakerState.CLOSED,
            "metrics": CircuitBreakerMetrics(),
            "last_sync": time.time()
        }
        
        # Background sync configuration
        self.sync_interval = 5.0  # seconds
        self.sync_task: Optional[asyncio.Task] = None
        
        # Active probe tracking
        self.active_probes: Dict[str, asyncio.Task] = {}
        
        logger.info(f"Circuit breaker '{name}' initialized with config: {config}")
    
    async def start(self):
        """Start background sync task."""
        if self.sync_task is None or self.sync_task.done():
            self.sync_task = asyncio.create_task(self._sync_loop())
    
    async def stop(self):
        """Stop background sync task."""
        if self.sync_task and not self.sync_task.done():
            self.sync_task.cancel()
            try:
                await self.sync_task
            except asyncio.CancelledError:
                pass
    
    async def _sync_loop(self):
        """Background task to sync state to persistent store."""
        while True:
            try:
                await asyncio.sleep(self.sync_interval)
                await self._sync_to_store()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in circuit breaker sync loop: {e}")
    
    async def _sync_to_store(self):
        """Sync memory cache to persistent store."""
        try:
            state_data = {
                "state": self.memory_cache["state"].value,
                "total_calls": str(self.memory_cache["metrics"].total_calls),
                "failed_calls": str(self.memory_cache["metrics"].failed_calls),
                "success_calls": str(self.memory_cache["metrics"].success_calls),
                "last_failure_time": str(self.memory_cache["metrics"].last_failure_time),
                "consecutive_successes": str(self.memory_cache["metrics"].consecutive_successes),
                "state_changes": str(self.memory_cache["metrics"].state_changes)
            }
            await self.state_store.set_state(self.name, state_data)
            self.memory_cache["last_sync"] = time.time()
        except Exception as e:
            logger.warning(f"Failed to sync circuit breaker state: {e}")
    
    async def _load_from_store(self):
        """Load state from persistent store."""
        try:
            state_data = await self.state_store.get_state(self.name)
            if state_data:
                self.memory_cache["state"] = CircuitBreakerState(state_data.get("state", "closed"))
                metrics = self.memory_cache["metrics"]
                metrics.total_calls = int(state_data.get("total_calls", 0))
                metrics.failed_calls = int(state_data.get("failed_calls", 0))
                metrics.success_calls = int(state_data.get("success_calls", 0))
                metrics.last_failure_time = float(state_data.get("last_failure_time", 0))
                metrics.consecutive_successes = int(state_data.get("consecutive_successes", 0))
                metrics.state_changes = int(state_data.get("state_changes", 0))
        except Exception as e:
            logger.warning(f"Failed to load circuit breaker state: {e}")
    
    def _should_trip(self) -> bool:
        """Check if circuit breaker should trip to open state."""
        metrics = self.memory_cache["metrics"]
        
        # Need minimum calls before evaluation
        if metrics.total_calls < self.config.minimum_calls:
            return False
        
        # Check failure rate
        return metrics.failure_rate >= self.config.fail_ratio
    
    def _should_attempt_reset(self) -> bool:
        """Check if circuit breaker should attempt reset from open state."""
        metrics = self.memory_cache["metrics"]
        time_since_failure = time.time() - metrics.last_failure_time
        return time_since_failure >= self.config.reset_timeout
    
    def _should_close(self) -> bool:
        """Check if circuit breaker should close from half-open state."""
        metrics = self.memory_cache["metrics"]
        return metrics.consecutive_successes >= self.config.success_threshold
    
    async def _execute_probe(self, func: Callable, *args, **kwargs) -> Any:
        """Execute a probe call in half-open state."""
        probe_key = f"{self.name}_probe_{id(func)}"
        
        # Check if probe is already running
        if probe_key in self.active_probes:
            existing_task = self.active_probes[probe_key]
            if not existing_task.done():
                return await existing_task
        
        # Create new probe task
        probe_task = asyncio.create_task(func(*args, **kwargs))
        self.active_probes[probe_key] = probe_task
        
        try:
            result = await probe_task
            await self._record_success()
            return result
        except Exception as e:
            await self._record_failure()
            raise
        finally:
            self.active_probes.pop(probe_key, None)
    
    async def _record_success(self):
        """Record successful call."""
        metrics = self.memory_cache["metrics"]
        metrics.total_calls += 1
        metrics.success_calls += 1
        metrics.consecutive_successes += 1
        
        # Check if we should close from half-open
        if (self.memory_cache["state"] == CircuitBreakerState.HALF_OPEN and 
            self._should_close()):
            await self._transition_to_closed()
    
    async def _record_failure(self):
        """Record failed call."""
        metrics = self.memory_cache["metrics"]
        metrics.total_calls += 1
        metrics.failed_calls += 1
        metrics.last_failure_time = time.time()
        metrics.consecutive_successes = 0
        
        # Check if we should trip to open
        if (self.memory_cache["state"] == CircuitBreakerState.CLOSED and 
            self._should_trip()):
            await self._transition_to_open()
        elif self.memory_cache["state"] == CircuitBreakerState.HALF_OPEN:
            await self._transition_to_open()
    
    async def _transition_to_open(self):
        """Transition to open state."""
        self.memory_cache["state"] = CircuitBreakerState.OPEN
        self.memory_cache["metrics"].state_changes += 1
        logger.warning(f"Circuit breaker '{self.name}' opened")
    
    async def _transition_to_half_open(self):
        """Transition to half-open state."""
        self.memory_cache["state"] = CircuitBreakerState.HALF_OPEN
        self.memory_cache["metrics"].state_changes += 1
        self.memory_cache["metrics"].consecutive_successes = 0
        logger.info(f"Circuit breaker '{self.name}' half-opened")
    
    async def _transition_to_closed(self):
        """Transition to closed state."""
        self.memory_cache["state"] = CircuitBreakerState.CLOSED
        self.memory_cache["metrics"].state_changes += 1
        self.memory_cache["metrics"].reset_window()
        logger.info(f"Circuit breaker '{self.name}' closed")
    
    async def call(self, func: Callable, *args, **kwargs) -> Any:
        """
        Execute function with circuit breaker protection.
        
        This is the main entry point with sub-microsecond state checking.
        """
        current_state = self.memory_cache["state"]
        
        # Fast path: CLOSED state (most common)
        if current_state == CircuitBreakerState.CLOSED:
            try:
                result = await func(*args, **kwargs)
                await self._record_success()
                return result
            except Exception as e:
                if not self.config.expected_exceptions or isinstance(e, self.config.expected_exceptions):
                    await self._record_failure()
                raise
        
        # OPEN state: check if we should attempt reset
        elif current_state == CircuitBreakerState.OPEN:
            if self._should_attempt_reset():
                await self._transition_to_half_open()
                return await self._execute_probe(func, *args, **kwargs)
            else:
                raise CircuitBreakerOpenException(f"Circuit breaker '{self.name}' is open")
        
        # HALF_OPEN state: execute probe
        elif current_state == CircuitBreakerState.HALF_OPEN:
            return await self._execute_probe(func, *args, **kwargs)
        
        else:
            raise ValueError(f"Unknown circuit breaker state: {current_state}")
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get current circuit breaker metrics."""
        metrics = self.memory_cache["metrics"]
        return {
            "name": self.name,
            "state": self.memory_cache["state"].value,
            "total_calls": metrics.total_calls,
            "failed_calls": metrics.failed_calls,
            "success_calls": metrics.success_calls,
            "failure_rate": metrics.failure_rate,
            "consecutive_successes": metrics.consecutive_successes,
            "state_changes": metrics.state_changes,
            "last_failure_time": metrics.last_failure_time,
            "config": {
                "fail_ratio": self.config.fail_ratio,
                "minimum_calls": self.config.minimum_calls,
                "reset_timeout": self.config.reset_timeout,
                "success_threshold": self.config.success_threshold
            }
        }


class CircuitBreakerOpenException(Exception):
    """Exception raised when circuit breaker is open."""
    pass


class CircuitBreakerManager:
    """
    Manages multiple circuit breakers with per-provider configuration.
    """
    
    def __init__(self, redis_url: Optional[str] = None):
        self.breakers: Dict[str, FastCircuitBreaker] = {}
        self.state_store = RedisStateStore(redis_url) if redis_url else MemoryStateStore()
        self._cleanup_refs: Dict[str, weakref.ref] = {}
    
    def create_breaker(
        self,
        name: str,
        config: CircuitBreakerConfig
    ) -> FastCircuitBreaker:
        """Create a new circuit breaker."""
        if name in self.breakers:
            return self.breakers[name]
        
        breaker = FastCircuitBreaker(name, config, self.state_store)
        self.breakers[name] = breaker
        
        # Schedule cleanup when breaker is garbage collected
        def cleanup(ref):
            asyncio.create_task(breaker.stop())
        
        self._cleanup_refs[name] = weakref.ref(breaker, cleanup)
        return breaker
    
    def get_breaker(self, name: str) -> Optional[FastCircuitBreaker]:
        """Get existing circuit breaker."""
        return self.breakers.get(name)
    
    async def start_all(self):
        """Start all circuit breakers."""
        for breaker in self.breakers.values():
            await breaker.start()
    
    async def stop_all(self):
        """Stop all circuit breakers."""
        for breaker in self.breakers.values():
            await breaker.stop()
    
    def get_all_metrics(self) -> Dict[str, Dict[str, Any]]:
        """Get metrics for all circuit breakers."""
        return {name: breaker.get_metrics() for name, breaker in self.breakers.items()}


# Pre-configured circuit breaker configurations for different providers
PROVIDER_CONFIGS = {
    "openai": CircuitBreakerConfig(
        fail_ratio=0.5,
        minimum_calls=20,
        reset_timeout=60,
        success_threshold=5
    ),
    "anthropic": CircuitBreakerConfig(
        fail_ratio=0.4,
        minimum_calls=15,
        reset_timeout=30,
        success_threshold=3
    ),
    "groq": CircuitBreakerConfig(
        fail_ratio=0.6,
        minimum_calls=30,
        reset_timeout=120,
        success_threshold=8
    ),
    "google": CircuitBreakerConfig(
        fail_ratio=0.5,
        minimum_calls=20,
        reset_timeout=60,
        success_threshold=5
    ),
    "azure": CircuitBreakerConfig(
        fail_ratio=0.5,
        minimum_calls=20,
        reset_timeout=60,
        success_threshold=5
    )
}


# Global circuit breaker manager instance
_circuit_breaker_manager: Optional[CircuitBreakerManager] = None


def get_circuit_breaker_manager(redis_url: Optional[str] = None) -> CircuitBreakerManager:
    """Get the global circuit breaker manager."""
    global _circuit_breaker_manager
    if _circuit_breaker_manager is None:
        _circuit_breaker_manager = CircuitBreakerManager(redis_url)
    return _circuit_breaker_manager


def circuit_breaker(
    name: str,
    config: Optional[CircuitBreakerConfig] = None,
    redis_url: Optional[str] = None
):
    """
    Decorator for applying circuit breaker protection to functions.
    
    Example:
        @circuit_breaker("openai_chat", PROVIDER_CONFIGS["openai"])
        async def call_openai_api():
            # API call here
            pass
    """
    def decorator(func):
        async def wrapper(*args, **kwargs):
            manager = get_circuit_breaker_manager(redis_url)
            breaker_config = config or PROVIDER_CONFIGS.get(name.split("_")[0], CircuitBreakerConfig())
            breaker = manager.create_breaker(name, breaker_config)
            
            if not hasattr(wrapper, '_breaker_started'):
                await breaker.start()
                wrapper._breaker_started = True
            
            return await breaker.call(func, *args, **kwargs)
        return wrapper
    return decorator