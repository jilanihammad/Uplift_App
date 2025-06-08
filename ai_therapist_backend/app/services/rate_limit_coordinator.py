"""
Rate Limiting Coordinator - Prevents rate limiting conflicts between streaming_pipeline and llm_manager

This module coordinates rate limiting to ensure:
1. Unified rate limit tracking across all components
2. Smart request queuing when approaching limits
3. Provider-specific rate limit handling
4. Graceful degradation under rate pressure
5. Fair resource allocation between components
"""

import logging
import asyncio
import time
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, field
from enum import Enum
import threading
from datetime import datetime, timedelta

from app.core.llm_config import ModelProvider


class RateLimitType(Enum):
    """Types of rate limits to track"""
    REQUESTS_PER_MINUTE = "requests_per_minute"
    REQUESTS_PER_HOUR = "requests_per_hour"
    TOKENS_PER_MINUTE = "tokens_per_minute"
    TOKENS_PER_HOUR = "tokens_per_hour"
    CONCURRENT_REQUESTS = "concurrent_requests"


@dataclass
class RateLimitConfig:
    """Configuration for a specific rate limit"""
    limit_type: RateLimitType
    limit_value: int
    window_seconds: int
    warning_threshold: float = 0.8  # Warn at 80% of limit
    pause_threshold: float = 0.9    # Pause at 90% of limit
    provider: Optional[ModelProvider] = None
    operation: str = "general"      # 'tts_generation', 'text_generation', etc.


@dataclass
class RateUsageTracker:
    """Tracks usage for a specific rate limit"""
    config: RateLimitConfig
    usage_history: List[float] = field(default_factory=list)  # Timestamps
    current_usage: int = 0
    last_reset: float = field(default_factory=time.time)
    is_paused: bool = False
    pause_until: Optional[float] = None
    
    def add_usage(self, amount: int = 1, timestamp: Optional[float] = None):
        """Add usage to the tracker"""
        if timestamp is None:
            timestamp = time.time()
        
        # Clean old entries outside the window
        cutoff = timestamp - self.config.window_seconds
        self.usage_history = [t for t in self.usage_history if t > cutoff]
        
        # Add new usage
        for _ in range(amount):
            self.usage_history.append(timestamp)
        
        self.current_usage = len(self.usage_history)
    
    def get_current_usage(self, timestamp: Optional[float] = None) -> int:
        """Get current usage within the time window"""
        if timestamp is None:
            timestamp = time.time()
        
        # Clean old entries
        cutoff = timestamp - self.config.window_seconds
        self.usage_history = [t for t in self.usage_history if t > cutoff]
        self.current_usage = len(self.usage_history)
        
        return self.current_usage
    
    def get_usage_percentage(self, timestamp: Optional[float] = None) -> float:
        """Get current usage as percentage of limit"""
        current = self.get_current_usage(timestamp)
        return current / self.config.limit_value if self.config.limit_value > 0 else 0.0
    
    def is_at_warning_threshold(self, timestamp: Optional[float] = None) -> bool:
        """Check if usage is at warning threshold"""
        return self.get_usage_percentage(timestamp) >= self.config.warning_threshold
    
    def is_at_pause_threshold(self, timestamp: Optional[float] = None) -> bool:
        """Check if usage is at pause threshold"""
        return self.get_usage_percentage(timestamp) >= self.config.pause_threshold
    
    def should_pause(self, timestamp: Optional[float] = None) -> bool:
        """Check if operations should be paused"""
        if timestamp is None:
            timestamp = time.time()
        
        # Check if already paused and pause period expired
        if self.is_paused and self.pause_until and timestamp > self.pause_until:
            self.is_paused = False
            self.pause_until = None
        
        return self.is_paused or self.is_at_pause_threshold(timestamp)
    
    def get_seconds_until_reset(self, timestamp: Optional[float] = None) -> float:
        """Get seconds until the oldest usage expires"""
        if not self.usage_history:
            return 0.0
        
        if timestamp is None:
            timestamp = time.time()
        
        oldest_usage = min(self.usage_history)
        reset_time = oldest_usage + self.config.window_seconds
        return max(0.0, reset_time - timestamp)


class RateLimitCoordinator:
    """
    Coordinates rate limiting between streaming_pipeline and llm_manager
    
    Prevents conflicts by:
    1. Centralized rate limit tracking for all components
    2. Smart queuing and throttling under rate pressure
    3. Provider-specific rate limit management
    4. Fair resource allocation between operations
    """
    
    def __init__(self):
        """Initialize the rate limit coordinator"""
        self.logger = logging.getLogger(__name__)
        
        # Thread-safe rate limit tracking
        self._lock = threading.RLock()
        self._rate_trackers: Dict[str, RateUsageTracker] = {}
        self._component_queues: Dict[str, asyncio.Queue] = {}
        self._active_requests: Dict[str, Set[str]] = {}
        
        # Default rate limit configurations for common providers
        self._default_configs = {
            ModelProvider.OPENAI: [
                RateLimitConfig(RateLimitType.REQUESTS_PER_MINUTE, 3000, 60, operation="tts_generation"),
                RateLimitConfig(RateLimitType.REQUESTS_PER_HOUR, 10000, 3600, operation="tts_generation"),
                RateLimitConfig(RateLimitType.TOKENS_PER_MINUTE, 50000, 60, operation="text_generation"),
                RateLimitConfig(RateLimitType.CONCURRENT_REQUESTS, 20, 1, operation="all")
            ],
            ModelProvider.GROQ: [
                RateLimitConfig(RateLimitType.REQUESTS_PER_MINUTE, 30, 60, operation="all"),
                RateLimitConfig(RateLimitType.TOKENS_PER_MINUTE, 10000, 60, operation="all"),
                RateLimitConfig(RateLimitType.CONCURRENT_REQUESTS, 5, 1, operation="all")
            ],
            ModelProvider.ANTHROPIC: [
                RateLimitConfig(RateLimitType.REQUESTS_PER_MINUTE, 1000, 60, operation="all"),
                RateLimitConfig(RateLimitType.TOKENS_PER_MINUTE, 10000, 60, operation="all"),
                RateLimitConfig(RateLimitType.CONCURRENT_REQUESTS, 10, 1, operation="all")
            ]
        }
        
        # Initialize default trackers
        self._initialize_default_trackers()
    
    def _initialize_default_trackers(self):
        """Initialize rate trackers for default configurations"""
        for provider, configs in self._default_configs.items():
            for config in configs:
                config.provider = provider
                tracker_key = f"{provider.value}_{config.operation}_{config.limit_type.value}"
                self._rate_trackers[tracker_key] = RateUsageTracker(config)
    
    def add_custom_rate_limit(self, config: RateLimitConfig) -> str:
        """
        Add a custom rate limit configuration
        
        Args:
            config: Rate limit configuration
            
        Returns:
            Tracker key for the rate limit
        """
        provider_name = config.provider.value if config.provider else "global"
        tracker_key = f"{provider_name}_{config.operation}_{config.limit_type.value}"
        
        with self._lock:
            self._rate_trackers[tracker_key] = RateUsageTracker(config)
        
        self.logger.info(f"Added custom rate limit: {tracker_key} = {config.limit_value}")
        return tracker_key
    
    async def check_rate_limit(self, 
                              component: str,
                              operation: str,
                              provider: Optional[ModelProvider] = None,
                              request_id: Optional[str] = None,
                              estimated_tokens: int = 1) -> bool:
        """
        Check if a request can proceed without hitting rate limits
        
        Args:
            component: Component making the request ('streaming_pipeline', 'llm_manager')
            operation: Type of operation ('tts_generation', 'text_generation')
            provider: API provider being used
            request_id: Unique request identifier
            estimated_tokens: Estimated token usage for the request
            
        Returns:
            True if request can proceed, False if should be throttled
        """
        timestamp = time.time()
        
        with self._lock:
            # Find applicable rate limits
            applicable_trackers = self._find_applicable_trackers(operation, provider)
            
            # Check all applicable rate limits
            for tracker_key, tracker in applicable_trackers.items():
                # Check if we're at pause threshold
                if tracker.should_pause(timestamp):
                    reset_time = tracker.get_seconds_until_reset(timestamp)
                    self.logger.warning(
                        f"Rate limit pause for {tracker_key}: {tracker.get_usage_percentage(timestamp):.1%} "
                        f"usage, reset in {reset_time:.1f}s"
                    )
                    return False
                
                # For token-based limits, check estimated usage
                if "tokens" in tracker.config.limit_type.value:
                    estimated_usage = tracker.get_current_usage(timestamp) + estimated_tokens
                    if estimated_usage > tracker.config.limit_value * tracker.config.pause_threshold:
                        self.logger.warning(
                            f"Token rate limit would be exceeded for {tracker_key}: "
                            f"{estimated_usage}/{tracker.config.limit_value} tokens"
                        )
                        return False
            
            # All checks passed - reserve the request
            if request_id:
                component_key = f"{component}_{operation}"
                if component_key not in self._active_requests:
                    self._active_requests[component_key] = set()
                self._active_requests[component_key].add(request_id)
        
        return True
    
    def record_usage(self, 
                    component: str,
                    operation: str,
                    provider: Optional[ModelProvider] = None,
                    request_id: Optional[str] = None,
                    tokens_used: int = 1):
        """
        Record actual usage for rate limit tracking
        
        Args:
            component: Component that made the request
            operation: Type of operation
            provider: API provider used
            request_id: Request identifier (for cleanup)
            tokens_used: Actual tokens used
        """
        timestamp = time.time()
        
        with self._lock:
            # Find applicable rate limits and record usage
            applicable_trackers = self._find_applicable_trackers(operation, provider)
            
            for tracker_key, tracker in applicable_trackers.items():
                if "tokens" in tracker.config.limit_type.value:
                    tracker.add_usage(tokens_used, timestamp)
                else:
                    tracker.add_usage(1, timestamp)
                
                # Log if approaching warning threshold
                if tracker.is_at_warning_threshold(timestamp):
                    usage_pct = tracker.get_usage_percentage(timestamp)
                    reset_time = tracker.get_seconds_until_reset(timestamp)
                    self.logger.warning(
                        f"Rate limit warning for {tracker_key}: {usage_pct:.1%} usage, "
                        f"reset in {reset_time:.1f}s"
                    )
            
            # Clean up active request tracking
            if request_id:
                component_key = f"{component}_{operation}"
                if component_key in self._active_requests:
                    self._active_requests[component_key].discard(request_id)
    
    def _find_applicable_trackers(self, 
                                 operation: str, 
                                 provider: Optional[ModelProvider]) -> Dict[str, RateUsageTracker]:
        """Find rate trackers applicable to the given operation and provider"""
        applicable = {}
        
        for tracker_key, tracker in self._rate_trackers.items():
            config = tracker.config
            
            # Check provider match
            if config.provider and provider and config.provider != provider:
                continue
            
            # Check operation match
            if config.operation != "all" and config.operation != operation:
                continue
            
            applicable[tracker_key] = tracker
        
        return applicable
    
    async def wait_for_rate_limit_reset(self, 
                                      operation: str,
                                      provider: Optional[ModelProvider] = None,
                                      max_wait_seconds: float = 300.0) -> bool:
        """
        Wait for rate limits to reset enough to allow requests
        
        Args:
            operation: Operation that needs to proceed
            provider: Provider for the operation
            max_wait_seconds: Maximum time to wait
            
        Returns:
            True if rate limits reset, False if timed out
        """
        start_time = time.time()
        
        while time.time() - start_time < max_wait_seconds:
            # Check if we can proceed now
            can_proceed = await self.check_rate_limit(
                component="wait_checker",
                operation=operation,
                provider=provider
            )
            
            if can_proceed:
                return True
            
            # Find the shortest reset time
            with self._lock:
                applicable_trackers = self._find_applicable_trackers(operation, provider)
                min_reset_time = float('inf')
                
                for tracker in applicable_trackers.values():
                    if tracker.should_pause():
                        reset_time = tracker.get_seconds_until_reset()
                        min_reset_time = min(min_reset_time, reset_time)
            
            # Wait for the shortest reset time, but not more than 30 seconds at once
            wait_time = min(min_reset_time, 30.0, max_wait_seconds - (time.time() - start_time))
            
            if wait_time > 0:
                self.logger.info(f"Waiting {wait_time:.1f}s for rate limit reset")
                await asyncio.sleep(wait_time)
            else:
                break
        
        return False
    
    def get_rate_limit_status(self, 
                            operation: Optional[str] = None,
                            provider: Optional[ModelProvider] = None) -> Dict[str, Any]:
        """
        Get current rate limit status
        
        Args:
            operation: Filter by operation (optional)
            provider: Filter by provider (optional)
            
        Returns:
            Dictionary with rate limit status information
        """
        timestamp = time.time()
        status = {}
        
        with self._lock:
            for tracker_key, tracker in self._rate_trackers.items():
                config = tracker.config
                
                # Apply filters
                if operation and config.operation != "all" and config.operation != operation:
                    continue
                if provider and config.provider and config.provider != provider:
                    continue
                
                current_usage = tracker.get_current_usage(timestamp)
                usage_percentage = tracker.get_usage_percentage(timestamp)
                reset_time = tracker.get_seconds_until_reset(timestamp)
                
                status[tracker_key] = {
                    "limit_type": config.limit_type.value,
                    "limit_value": config.limit_value,
                    "current_usage": current_usage,
                    "usage_percentage": usage_percentage,
                    "is_at_warning": tracker.is_at_warning_threshold(timestamp),
                    "is_at_pause": tracker.is_at_pause_threshold(timestamp),
                    "should_pause": tracker.should_pause(timestamp),
                    "seconds_until_reset": reset_time,
                    "operation": config.operation,
                    "provider": config.provider.value if config.provider else None
                }
        
        return status
    
    def reset_rate_limits(self, 
                         operation: Optional[str] = None,
                         provider: Optional[ModelProvider] = None):
        """
        Reset rate limit counters (for testing or emergency situations)
        
        Args:
            operation: Reset only specific operation (optional)
            provider: Reset only specific provider (optional)
        """
        with self._lock:
            reset_count = 0
            for tracker_key, tracker in self._rate_trackers.items():
                config = tracker.config
                
                # Apply filters
                if operation and config.operation != "all" and config.operation != operation:
                    continue
                if provider and config.provider and config.provider != provider:
                    continue
                
                tracker.usage_history.clear()
                tracker.current_usage = 0
                tracker.last_reset = time.time()
                tracker.is_paused = False
                tracker.pause_until = None
                reset_count += 1
            
            # Clear active request tracking
            if operation is None and provider is None:
                self._active_requests.clear()
        
        self.logger.info(f"Reset {reset_count} rate limit trackers")
    
    def get_component_statistics(self) -> Dict[str, Any]:
        """Get statistics about component rate limit usage"""
        with self._lock:
            stats = {
                "total_trackers": len(self._rate_trackers),
                "active_requests": {k: len(v) for k, v in self._active_requests.items()},
                "paused_trackers": []
            }
            
            for tracker_key, tracker in self._rate_trackers.items():
                if tracker.should_pause():
                    stats["paused_trackers"].append({
                        "tracker": tracker_key,
                        "usage_percentage": tracker.get_usage_percentage(),
                        "reset_seconds": tracker.get_seconds_until_reset()
                    })
        
        return stats 