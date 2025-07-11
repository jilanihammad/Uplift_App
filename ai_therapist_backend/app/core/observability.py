"""
Enhanced Observability System

This module provides comprehensive observability for the AI Therapist backend with:
- Structured logging with JSON format
- Request tracing with correlation IDs
- Performance metrics collection
- Non-blocking metric and log collection
- Smart sampling for production
"""

import asyncio
import json
import logging
import time
import uuid
from contextvars import ContextVar
from dataclasses import dataclass, asdict
from typing import Dict, Any, Optional, List, AsyncGenerator
from functools import wraps
import weakref
from collections import defaultdict, deque
import threading

# Import enhanced logging context variables
from app.core.enhanced_logging import request_id_context, trace_id_context


@dataclass
class MetricRecord:
    """Structured metric record."""
    timestamp: float
    metric_name: str
    value: float
    labels: Dict[str, str]
    metric_type: str = "gauge"  # gauge, counter, histogram


@dataclass
class LogRecord:
    """Structured log record."""
    timestamp: float
    level: str
    service: str
    message: str
    request_id: str
    trace_id: str
    provider: Optional[str] = None
    method: Optional[str] = None
    duration_ms: Optional[float] = None
    tokens_used: Optional[int] = None
    model: Optional[str] = None
    error: Optional[str] = None
    extra: Optional[Dict[str, Any]] = None


class PerformantLogger:
    """
    High-performance logger with non-blocking queue and batch processing.
    
    Features:
    - Non-blocking log queuing
    - Batch processing for efficiency
    - Automatic queue overflow handling
    - Structured JSON output
    """
    
    def __init__(self, 
                 max_queue_size: int = 10000,
                 batch_size: int = 1000,
                 flush_interval: float = 2.0):
        self.max_queue_size = max_queue_size
        self.batch_size = batch_size
        self.flush_interval = flush_interval
        
        # Non-blocking queue for log records
        self.log_queue = asyncio.Queue(maxsize=max_queue_size)
        
        # Background task for processing logs
        self.flush_task: Optional[asyncio.Task] = None
        self.running = False
        
        # Standard logger for actual output
        self.logger = logging.getLogger("ai_therapist.observability")
        
        # Metrics for monitoring the logger itself
        self.dropped_logs = 0
        self.processed_logs = 0
        
    async def start(self):
        """Start the background log processing task."""
        if self.running:
            return
        
        self.running = True
        self.flush_task = asyncio.create_task(self._flush_loop())
        
    async def stop(self):
        """Stop the background log processing task."""
        if not self.running:
            return
        
        self.running = False
        
        if self.flush_task:
            self.flush_task.cancel()
            try:
                await self.flush_task
            except asyncio.CancelledError:
                pass
        
        # Flush remaining logs
        await self._flush_batch()
    
    async def _flush_loop(self):
        """Background task to flush logs in batches."""
        while self.running:
            try:
                await asyncio.sleep(self.flush_interval)
                await self._flush_batch()
            except asyncio.CancelledError:
                break
            except Exception as e:
                # Log to standard logger to avoid recursion
                self.logger.error(f"Error in log flush loop: {e}")
    
    async def _flush_batch(self):
        """Flush a batch of logs."""
        logs_to_flush = []
        
        # Collect logs from queue
        for _ in range(self.batch_size):
            try:
                log_record = self.log_queue.get_nowait()
                logs_to_flush.append(log_record)
            except asyncio.QueueEmpty:
                break
        
        # Process logs
        if logs_to_flush:
            for log_record in logs_to_flush:
                await self._write_log(log_record)
                self.processed_logs += 1
    
    async def _write_log(self, log_record: LogRecord):
        """Write a single log record in JSON format."""
        try:
            # Convert to JSON
            log_dict = asdict(log_record)
            log_dict['timestamp'] = time.strftime('%Y-%m-%dT%H:%M:%S.%fZ', 
                                                 time.gmtime(log_record.timestamp))
            
            # Log as JSON
            if log_record.level == "ERROR":
                self.logger.error(json.dumps(log_dict))
            elif log_record.level == "WARNING":
                self.logger.warning(json.dumps(log_dict))
            elif log_record.level == "INFO":
                self.logger.info(json.dumps(log_dict))
            elif log_record.level == "DEBUG":
                self.logger.debug(json.dumps(log_dict))
            else:
                self.logger.info(json.dumps(log_dict))
        except Exception as e:
            # Fallback to standard logging
            self.logger.error(f"Error writing structured log: {e}")
    
    async def log_async(self, 
                       level: str, 
                       service: str, 
                       message: str,
                       **kwargs):
        """Log a message asynchronously."""
        log_record = LogRecord(
            timestamp=time.time(),
            level=level,
            service=service,
            message=message,
            request_id=request_id_context.get(''),
            trace_id=trace_id_context.get(''),
            **kwargs
        )
        
        # Non-blocking queue insertion
        try:
            self.log_queue.put_nowait(log_record)
        except asyncio.QueueFull:
            # Drop logs if queue is full
            self.dropped_logs += 1
            # Emit a warning (but don't create recursion)
            if self.dropped_logs % 1000 == 0:
                self.logger.warning(f"Dropped {self.dropped_logs} logs due to queue overflow")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get logger statistics."""
        return {
            "queue_size": self.log_queue.qsize(),
            "max_queue_size": self.max_queue_size,
            "dropped_logs": self.dropped_logs,
            "processed_logs": self.processed_logs,
            "queue_utilization": self.log_queue.qsize() / self.max_queue_size
        }


class MetricsCollector:
    """
    High-performance metrics collector with smart sampling and aggregation.
    
    Features:
    - Real-time metric collection
    - Smart sampling for production
    - Aggregation of similar metrics
    - Non-blocking collection
    """
    
    def __init__(self, 
                 sample_rate: float = 1.0,
                 export_interval: float = 5.0,
                 max_metrics_buffer: int = 10000):
        self.sample_rate = sample_rate
        self.export_interval = export_interval
        self.max_metrics_buffer = max_metrics_buffer
        
        # Metrics buffer
        self.metrics_buffer: deque = deque(maxlen=max_metrics_buffer)
        self.metrics_lock = threading.Lock()
        
        # Aggregated metrics
        self.aggregated_metrics: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
            'count': 0,
            'sum': 0.0,
            'min': float('inf'),
            'max': float('-inf'),
            'last_value': 0.0
        })
        
        # Background export task
        self.export_task: Optional[asyncio.Task] = None
        self.running = False
        
    async def start(self):
        """Start the metrics collection system."""
        if self.running:
            return
        
        self.running = True
        self.export_task = asyncio.create_task(self._export_loop())
    
    async def stop(self):
        """Stop the metrics collection system."""
        if not self.running:
            return
        
        self.running = False
        
        if self.export_task:
            self.export_task.cancel()
            try:
                await self.export_task
            except asyncio.CancelledError:
                pass
    
    async def _export_loop(self):
        """Background task to export metrics."""
        while self.running:
            try:
                await asyncio.sleep(self.export_interval)
                await self._export_metrics()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logging.error(f"Error in metrics export loop: {e}")
    
    async def _export_metrics(self):
        """Export aggregated metrics."""
        # This would typically send to a metrics backend
        # For now, we'll just log the aggregated metrics
        if self.aggregated_metrics:
            metrics_summary = {
                name: {
                    'count': data['count'],
                    'avg': data['sum'] / data['count'] if data['count'] > 0 else 0,
                    'min': data['min'] if data['min'] != float('inf') else 0,
                    'max': data['max'] if data['max'] != float('-inf') else 0,
                    'last': data['last_value']
                }
                for name, data in self.aggregated_metrics.items()
            }
            
            # Log metrics summary
            logger = logging.getLogger("ai_therapist.metrics")
            logger.info(f"Metrics summary: {json.dumps(metrics_summary)}")
    
    def record_metric(self, 
                     metric_name: str, 
                     value: float, 
                     labels: Optional[Dict[str, str]] = None,
                     metric_type: str = "gauge"):
        """Record a metric value."""
        # Smart sampling - skip if random doesn't meet sample rate
        if self.sample_rate < 1.0:
            import random
            if random.random() > self.sample_rate:
                return
        
        # Create metric record
        metric_record = MetricRecord(
            timestamp=time.time(),
            metric_name=metric_name,
            value=value,
            labels=labels or {},
            metric_type=metric_type
        )
        
        # Add to buffer (thread-safe)
        with self.metrics_lock:
            self.metrics_buffer.append(metric_record)
        
        # Update aggregated metrics
        self._update_aggregated_metrics(metric_name, value)
    
    def _update_aggregated_metrics(self, metric_name: str, value: float):
        """Update aggregated metrics for a given metric name."""
        metrics = self.aggregated_metrics[metric_name]
        
        metrics['count'] += 1
        metrics['sum'] += value
        metrics['min'] = min(metrics['min'], value)
        metrics['max'] = max(metrics['max'], value)
        metrics['last_value'] = value
    
    def get_metrics_summary(self) -> Dict[str, Any]:
        """Get current metrics summary."""
        return {
            name: {
                'count': data['count'],
                'average': data['sum'] / data['count'] if data['count'] > 0 else 0,
                'min': data['min'] if data['min'] != float('inf') else 0,
                'max': data['max'] if data['max'] != float('-inf') else 0,
                'last_value': data['last_value']
            }
            for name, data in self.aggregated_metrics.items()
        }


class RequestTracer:
    """
    Request tracing system with correlation IDs and performance tracking.
    
    Features:
    - Automatic request ID generation
    - Trace ID correlation across services
    - Performance timing
    - Request context management
    """
    
    @staticmethod
    def generate_request_id() -> str:
        """Generate a unique request ID."""
        return str(uuid.uuid4())
    
    @staticmethod
    def generate_trace_id() -> str:
        """Generate a unique trace ID."""
        return str(uuid.uuid4())
    
    @staticmethod
    def set_request_context(request_id: str, trace_id: str):
        """Set the current request context."""
        request_id_context.set(request_id)
        trace_id_context.set(trace_id)
    
    @staticmethod
    def get_request_context() -> Dict[str, str]:
        """Get the current request context."""
        return {
            'request_id': request_id_context.get(''),
            'trace_id': trace_id_context.get('')
        }
    
    @staticmethod
    def trace_request(func):
        """Decorator to automatically trace requests."""
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Generate IDs if not already set
            if not request_id_context.get(''):
                request_id = RequestTracer.generate_request_id()
                trace_id = RequestTracer.generate_trace_id()
                RequestTracer.set_request_context(request_id, trace_id)
            
            # Execute function with timing
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = (time.time() - start_time) * 1000  # Convert to milliseconds
                
                # Log successful request
                await observability_manager.log_async(
                    "INFO",
                    "request_tracer",
                    f"Request completed successfully",
                    method=func.__name__,
                    duration_ms=duration
                )
                
                return result
            except Exception as e:
                duration = (time.time() - start_time) * 1000
                
                # Log failed request
                await observability_manager.log_async(
                    "ERROR",
                    "request_tracer",
                    f"Request failed: {str(e)}",
                    method=func.__name__,
                    duration_ms=duration,
                    error=str(e)
                )
                
                raise
        
        return wrapper


class ObservabilityManager:
    """
    Central observability manager that coordinates logging, metrics, and tracing.
    
    Features:
    - Unified interface for all observability features
    - Smart sampling configuration
    - Performance optimization
    - Health monitoring
    """
    
    def __init__(self, 
                 log_sample_rate: float = 1.0,
                 metric_sample_rate: float = 1.0,
                 trace_sample_rate: float = 1.0):
        # Initialize components
        self.logger = PerformantLogger()
        self.metrics_collector = MetricsCollector(sample_rate=metric_sample_rate)
        self.tracer = RequestTracer()
        
        # Sampling configuration
        self.log_sample_rate = log_sample_rate
        self.metric_sample_rate = metric_sample_rate
        self.trace_sample_rate = trace_sample_rate
        
        # Health tracking
        self.start_time = time.time()
        self.health_status = "healthy"
        
    async def start(self):
        """Start all observability components."""
        await self.logger.start()
        await self.metrics_collector.start()
        
    async def stop(self):
        """Stop all observability components."""
        await self.logger.stop()
        await self.metrics_collector.stop()
    
    async def log_async(self, level: str, service: str, message: str, **kwargs):
        """Log a message asynchronously with smart sampling."""
        # Smart sampling for logs
        if self.log_sample_rate < 1.0:
            import random
            if random.random() > self.log_sample_rate:
                return
        
        await self.logger.log_async(level, service, message, **kwargs)
    
    def record_metric(self, metric_name: str, value: float, 
                     labels: Optional[Dict[str, str]] = None,
                     metric_type: str = "gauge"):
        """Record a metric with smart sampling."""
        self.metrics_collector.record_metric(metric_name, value, labels, metric_type)
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get comprehensive health status."""
        return {
            "status": self.health_status,
            "uptime_seconds": time.time() - self.start_time,
            "logger_stats": self.logger.get_stats(),
            "metrics_summary": self.metrics_collector.get_metrics_summary(),
            "sampling_config": {
                "log_sample_rate": self.log_sample_rate,
                "metric_sample_rate": self.metric_sample_rate,
                "trace_sample_rate": self.trace_sample_rate
            }
        }


# Global observability manager instance
observability_manager = ObservabilityManager()


# Convenience functions
async def log_info(service: str, message: str, **kwargs):
    """Log an info message."""
    await observability_manager.log_async("INFO", service, message, **kwargs)


async def log_error(service: str, message: str, **kwargs):
    """Log an error message."""
    await observability_manager.log_async("ERROR", service, message, **kwargs)


async def log_warning(service: str, message: str, **kwargs):
    """Log a warning message."""
    await observability_manager.log_async("WARNING", service, message, **kwargs)


def record_latency(service: str, operation: str, duration_ms: float, 
                  labels: Optional[Dict[str, str]] = None):
    """Record a latency metric."""
    metric_name = f"{service}_{operation}_latency_ms"
    observability_manager.record_metric(metric_name, duration_ms, labels, "histogram")


def record_counter(service: str, operation: str, count: int = 1,
                  labels: Optional[Dict[str, str]] = None):
    """Record a counter metric."""
    metric_name = f"{service}_{operation}_count"
    observability_manager.record_metric(metric_name, count, labels, "counter")


def record_gauge(service: str, metric: str, value: float,
                labels: Optional[Dict[str, str]] = None):
    """Record a gauge metric."""
    metric_name = f"{service}_{metric}"
    observability_manager.record_metric(metric_name, value, labels, "gauge")


# Decorators for easy usage
def observe_performance(service: str, operation: str):
    """Decorator to automatically observe performance metrics."""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = (time.time() - start_time) * 1000
                
                # Record success metrics
                record_latency(service, operation, duration)
                record_counter(service, f"{operation}_success")
                
                return result
            except Exception as e:
                duration = (time.time() - start_time) * 1000
                
                # Record failure metrics
                record_latency(service, operation, duration)
                record_counter(service, f"{operation}_failure")
                
                raise
        
        return wrapper
    return decorator


def observe_llm_call(provider: str, operation: str):
    """Decorator specifically for LLM calls."""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = (time.time() - start_time) * 1000
                
                # Record detailed LLM metrics
                await log_info(
                    "llm_manager",
                    f"LLM call completed successfully",
                    provider=provider,
                    method=operation,
                    duration_ms=duration
                )
                
                record_latency("llm", operation, duration, {"provider": provider})
                record_counter("llm", f"{operation}_success", labels={"provider": provider})
                
                return result
            except Exception as e:
                duration = (time.time() - start_time) * 1000
                
                # Record failure
                await log_error(
                    "llm_manager",
                    f"LLM call failed: {str(e)}",
                    provider=provider,
                    method=operation,
                    duration_ms=duration,
                    error=str(e)
                )
                
                record_latency("llm", operation, duration, {"provider": provider})
                record_counter("llm", f"{operation}_failure", labels={"provider": provider})
                
                raise
        
        return wrapper
    return decorator