"""
Performance Monitoring for HTTP Optimization

This module provides utilities to monitor performance improvements from
HTTP client optimizations and container warm-up.
"""

import time
import logging
import asyncio
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
from collections import defaultdict, deque

logger = logging.getLogger(__name__)


@dataclass
class PerformanceMetric:
    """Performance metric data."""
    name: str
    value: float
    timestamp: datetime
    labels: Dict[str, str] = field(default_factory=dict)
    
    
@dataclass
class LatencyMeasurement:
    """Latency measurement with context."""
    operation: str
    duration_ms: float
    timestamp: datetime
    success: bool
    error: Optional[str] = None
    labels: Dict[str, str] = field(default_factory=dict)


class PerformanceMonitor:
    """
    Performance monitor for tracking HTTP optimization improvements.
    
    Features:
    - Latency tracking with percentiles
    - HTTP connection reuse metrics
    - Cold start time monitoring
    - Performance comparison utilities
    """
    
    def __init__(self, window_size: int = 1000):
        self.window_size = window_size
        self.latency_measurements: Dict[str, deque] = defaultdict(lambda: deque(maxlen=window_size))
        self.connection_metrics: Dict[str, Any] = {}
        self.cold_start_metrics: List[LatencyMeasurement] = []
        self.baseline_metrics: Dict[str, float] = {}
        
    def record_latency(self, operation: str, duration_ms: float, 
                      success: bool = True, error: str = None, **labels):
        """Record a latency measurement."""
        measurement = LatencyMeasurement(
            operation=operation,
            duration_ms=duration_ms,
            timestamp=datetime.now(),
            success=success,
            error=error,
            labels=labels
        )
        
        self.latency_measurements[operation].append(measurement)
        
        # Log significant performance events
        if duration_ms > 5000:  # > 5s
            logger.warning(f"High latency detected: {operation} took {duration_ms:.2f}ms")
        elif duration_ms > 2000:  # > 2s
            logger.info(f"Elevated latency: {operation} took {duration_ms:.2f}ms")
    
    def record_connection_reuse(self, provider: str, reused: bool):
        """Record HTTP connection reuse metrics."""
        if provider not in self.connection_metrics:
            self.connection_metrics[provider] = {
                "total_requests": 0,
                "reused_connections": 0,
                "new_connections": 0
            }
        
        metrics = self.connection_metrics[provider]
        metrics["total_requests"] += 1
        
        if reused:
            metrics["reused_connections"] += 1
        else:
            metrics["new_connections"] += 1
    
    def record_cold_start(self, stage: str, duration_ms: float, success: bool = True):
        """Record cold start timing."""
        measurement = LatencyMeasurement(
            operation=f"cold_start_{stage}",
            duration_ms=duration_ms,
            timestamp=datetime.now(),
            success=success,
            labels={"stage": stage}
        )
        
        self.cold_start_metrics.append(measurement)
        
        # Keep only recent cold starts (last 10)
        if len(self.cold_start_metrics) > 10:
            self.cold_start_metrics = self.cold_start_metrics[-10:]
    
    def set_baseline(self, operation: str, baseline_ms: float):
        """Set baseline performance metric for comparison."""
        self.baseline_metrics[operation] = baseline_ms
        logger.info(f"Baseline set for {operation}: {baseline_ms:.2f}ms")
    
    def get_percentiles(self, operation: str, percentiles: List[float] = None) -> Dict[str, float]:
        """Calculate latency percentiles for an operation."""
        if percentiles is None:
            percentiles = [50, 95, 99]
        
        measurements = self.latency_measurements.get(operation, deque())
        if not measurements:
            return {}
        
        # Extract successful measurements only
        durations = [m.duration_ms for m in measurements if m.success]
        if not durations:
            return {}
        
        durations.sort()
        result = {}
        
        for p in percentiles:
            idx = int((p / 100.0) * (len(durations) - 1))
            result[f"p{int(p)}"] = durations[idx]
        
        return result
    
    def get_success_rate(self, operation: str, window_minutes: int = 5) -> float:
        """Calculate success rate for an operation."""
        measurements = self.latency_measurements.get(operation, deque())
        if not measurements:
            return 1.0
        
        # Filter to recent measurements
        cutoff = datetime.now() - timedelta(minutes=window_minutes)
        recent = [m for m in measurements if m.timestamp > cutoff]
        
        if not recent:
            return 1.0
        
        successful = sum(1 for m in recent if m.success)
        return successful / len(recent)
    
    def get_connection_reuse_rate(self, provider: str) -> float:
        """Get connection reuse rate for a provider."""
        metrics = self.connection_metrics.get(provider, {})
        total = metrics.get("total_requests", 0)
        reused = metrics.get("reused_connections", 0)
        
        if total == 0:
            return 0.0
        
        return reused / total
    
    def get_improvement_percentage(self, operation: str) -> Optional[float]:
        """Calculate performance improvement vs baseline."""
        if operation not in self.baseline_metrics:
            return None
        
        baseline = self.baseline_metrics[operation]
        current_percentiles = self.get_percentiles(operation, [95])
        
        if not current_percentiles:
            return None
        
        current_p95 = current_percentiles.get("p95")
        if current_p95 is None:
            return None
        
        improvement = ((baseline - current_p95) / baseline) * 100
        return improvement
    
    def get_performance_report(self) -> Dict[str, Any]:
        """Generate comprehensive performance report."""
        report = {
            "timestamp": datetime.now().isoformat(),
            "operations": {},
            "connection_reuse": {},
            "cold_start_summary": {},
            "improvements": {}
        }
        
        # Operation metrics
        for operation in self.latency_measurements:
            percentiles = self.get_percentiles(operation)
            success_rate = self.get_success_rate(operation)
            improvement = self.get_improvement_percentage(operation)
            
            report["operations"][operation] = {
                "percentiles": percentiles,
                "success_rate": success_rate,
                "sample_count": len(self.latency_measurements[operation]),
                "improvement_vs_baseline": improvement
            }
        
        # Connection reuse metrics
        for provider in self.connection_metrics:
            reuse_rate = self.get_connection_reuse_rate(provider)
            report["connection_reuse"][provider] = {
                "reuse_rate": reuse_rate,
                "total_requests": self.connection_metrics[provider]["total_requests"]
            }
        
        # Cold start metrics
        if self.cold_start_metrics:
            recent_cold_starts = self.cold_start_metrics[-5:]  # Last 5
            avg_duration = sum(m.duration_ms for m in recent_cold_starts) / len(recent_cold_starts)
            success_rate = sum(1 for m in recent_cold_starts if m.success) / len(recent_cold_starts)
            
            report["cold_start_summary"] = {
                "average_duration_ms": avg_duration,
                "success_rate": success_rate,
                "sample_count": len(recent_cold_starts)
            }
        
        return report
    
    @asynccontextmanager
    async def measure_operation(self, operation: str, **labels):
        """Context manager for measuring operation latency."""
        start_time = time.time()
        success = True
        error = None
        
        try:
            yield
        except Exception as e:
            success = False
            error = str(e)
            raise
        finally:
            duration_ms = (time.time() - start_time) * 1000
            self.record_latency(operation, duration_ms, success, error, **labels)


# Global performance monitor instance
_performance_monitor: Optional[PerformanceMonitor] = None


def get_performance_monitor() -> PerformanceMonitor:
    """Get the global performance monitor."""
    global _performance_monitor
    if _performance_monitor is None:
        _performance_monitor = PerformanceMonitor()
    return _performance_monitor


# Convenience functions
def record_latency(operation: str, duration_ms: float, success: bool = True, **labels):
    """Record latency measurement."""
    monitor = get_performance_monitor()
    monitor.record_latency(operation, duration_ms, success, **labels)


def record_connection_reuse(provider: str, reused: bool):
    """Record connection reuse."""
    monitor = get_performance_monitor()
    monitor.record_connection_reuse(provider, reused)


def set_baseline(operation: str, baseline_ms: float):
    """Set baseline performance."""
    monitor = get_performance_monitor()
    monitor.set_baseline(operation, baseline_ms)


@asynccontextmanager
async def measure_operation(operation: str, **labels):
    """Measure operation latency."""
    monitor = get_performance_monitor()
    async with monitor.measure_operation(operation, **labels):
        yield


def get_performance_report() -> Dict[str, Any]:
    """Get performance report."""
    monitor = get_performance_monitor()
    return monitor.get_performance_report()


# Decorator for automatic latency measurement
def monitor_performance(operation: str, **labels):
    """Decorator to automatically monitor function performance."""
    def decorator(func):
        if asyncio.iscoroutinefunction(func):
            async def async_wrapper(*args, **kwargs):
                async with measure_operation(operation, **labels):
                    return await func(*args, **kwargs)
            return async_wrapper
        else:
            def sync_wrapper(*args, **kwargs):
                start_time = time.time()
                try:
                    result = func(*args, **kwargs)
                    duration_ms = (time.time() - start_time) * 1000
                    record_latency(operation, duration_ms, True, **labels)
                    return result
                except Exception as e:
                    duration_ms = (time.time() - start_time) * 1000
                    record_latency(operation, duration_ms, False, **labels)
                    raise
            return sync_wrapper
    return decorator