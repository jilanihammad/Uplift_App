"""
Connection Monitoring and Resource Optimization

This module provides comprehensive connection monitoring with:
- Real-time connection tracking
- Resource usage monitoring
- Connection pool health checks
- Performance metrics collection
- Automatic resource cleanup
- Connection leak detection
"""

import asyncio
import logging
import time
import psutil
import threading
from typing import Dict, Any, Optional, List, Callable
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict, deque
import weakref
from contextlib import asynccontextmanager

from app.core.observability import record_counter, record_latency, log_info, log_warning, log_error

logger = logging.getLogger(__name__)


class ConnectionState(Enum):
    """Connection states for monitoring."""
    IDLE = "idle"
    ACTIVE = "active"
    CLOSING = "closing"
    CLOSED = "closed"
    ERROR = "error"


class ResourceType(Enum):
    """Types of resources being monitored."""
    HTTP_CONNECTION = "http_connection"
    WEBSOCKET_CONNECTION = "websocket_connection"
    DATABASE_CONNECTION = "database_connection"
    FILE_HANDLE = "file_handle"
    MEMORY_BUFFER = "memory_buffer"
    THREAD = "thread"
    TASK = "task"


@dataclass
class ConnectionMetrics:
    """Metrics for a single connection."""
    connection_id: str
    resource_type: ResourceType
    state: ConnectionState
    created_at: float
    last_activity: float
    bytes_sent: int = 0
    bytes_received: int = 0
    requests_count: int = 0
    errors_count: int = 0
    provider: Optional[str] = None
    endpoint: Optional[str] = None
    
    def get_age(self) -> float:
        """Get connection age in seconds."""
        return time.time() - self.created_at
    
    def get_idle_time(self) -> float:
        """Get idle time in seconds."""
        return time.time() - self.last_activity
    
    def update_activity(self):
        """Update last activity timestamp."""
        self.last_activity = time.time()


@dataclass
class ResourceLimits:
    """Resource limits for monitoring."""
    max_connections: int = 1000
    max_idle_time: float = 300.0  # 5 minutes
    max_connection_age: float = 3600.0  # 1 hour
    max_memory_mb: int = 1024
    max_file_handles: int = 1000
    max_threads: int = 100
    max_tasks: int = 1000
    cleanup_interval: float = 60.0  # 1 minute


@dataclass
class SystemMetrics:
    """System-level resource metrics."""
    timestamp: float
    cpu_percent: float
    memory_percent: float
    memory_mb: float
    open_files: int
    threads: int
    network_connections: int
    active_tasks: int
    
    connections_by_type: Dict[ResourceType, int] = field(default_factory=dict)
    connections_by_state: Dict[ConnectionState, int] = field(default_factory=dict)
    connections_by_provider: Dict[str, int] = field(default_factory=dict)


class ConnectionMonitor:
    """
    Comprehensive connection and resource monitoring system.
    
    Features:
    - Real-time connection tracking
    - Resource usage monitoring
    - Automatic cleanup of stale connections
    - Connection leak detection
    - Performance metrics collection
    - Health checks and alerts
    """
    
    def __init__(self, limits: ResourceLimits = None):
        self.limits = limits or ResourceLimits()
        self.connections: Dict[str, ConnectionMetrics] = {}
        self.system_metrics_history: deque = deque(maxlen=60)  # Last 60 measurements
        
        # Monitoring state
        self.running = False
        self.monitor_task: Optional[asyncio.Task] = None
        self.cleanup_task: Optional[asyncio.Task] = None
        
        # Callbacks for events
        self.connection_callbacks: Dict[str, List[Callable]] = defaultdict(list)
        self.resource_callbacks: Dict[str, List[Callable]] = defaultdict(list)
        
        # Metrics
        self.total_connections_created = 0
        self.total_connections_closed = 0
        self.total_cleanup_operations = 0
        self.alerts_sent = 0
        
        # Thread safety
        self._lock = asyncio.Lock()
        
        logger.info("Connection monitor initialized")
    
    async def start(self):
        """Start the connection monitor."""
        if self.running:
            return
        
        self.running = True
        
        # Start monitoring tasks
        self.monitor_task = asyncio.create_task(self._monitoring_loop())
        self.cleanup_task = asyncio.create_task(self._cleanup_loop())
        
        await log_info(
            "connection_monitor",
            "Connection monitor started",
            limits=self.limits.__dict__
        )
    
    async def stop(self):
        """Stop the connection monitor."""
        self.running = False
        
        # Cancel monitoring tasks
        if self.monitor_task:
            self.monitor_task.cancel()
            try:
                await self.monitor_task
            except asyncio.CancelledError:
                pass
        
        if self.cleanup_task:
            self.cleanup_task.cancel()
            try:
                await self.cleanup_task
            except asyncio.CancelledError:
                pass
        
        await log_info(
            "connection_monitor",
            "Connection monitor stopped",
            total_connections_tracked=self.total_connections_created,
            cleanup_operations=self.total_cleanup_operations
        )
    
    async def register_connection(self, connection_id: str, 
                                resource_type: ResourceType,
                                provider: str = None,
                                endpoint: str = None) -> ConnectionMetrics:
        """Register a new connection for monitoring."""
        async with self._lock:
            metrics = ConnectionMetrics(
                connection_id=connection_id,
                resource_type=resource_type,
                state=ConnectionState.IDLE,
                created_at=time.time(),
                last_activity=time.time(),
                provider=provider,
                endpoint=endpoint
            )
            
            self.connections[connection_id] = metrics
            self.total_connections_created += 1
            
            # Record metrics
            record_counter(
                "connection_monitor",
                "connections_registered",
                labels={
                    "resource_type": resource_type.value,
                    "provider": provider or "unknown"
                }
            )
            
            # Trigger callbacks
            await self._trigger_callbacks("connection_registered", metrics)
            
            return metrics
    
    async def update_connection_state(self, connection_id: str, 
                                    state: ConnectionState,
                                    bytes_sent: int = 0,
                                    bytes_received: int = 0,
                                    increment_requests: bool = False,
                                    increment_errors: bool = False):
        """Update connection state and metrics."""
        async with self._lock:
            if connection_id not in self.connections:
                return
            
            metrics = self.connections[connection_id]
            old_state = metrics.state
            
            metrics.state = state
            metrics.update_activity()
            
            if bytes_sent > 0:
                metrics.bytes_sent += bytes_sent
            if bytes_received > 0:
                metrics.bytes_received += bytes_received
            if increment_requests:
                metrics.requests_count += 1
            if increment_errors:
                metrics.errors_count += 1
            
            # Record state change
            if old_state != state:
                record_counter(
                    "connection_monitor",
                    "state_changes",
                    labels={
                        "resource_type": metrics.resource_type.value,
                        "old_state": old_state.value,
                        "new_state": state.value,
                        "provider": metrics.provider or "unknown"
                    }
                )
    
    async def unregister_connection(self, connection_id: str):
        """Unregister a connection from monitoring."""
        async with self._lock:
            if connection_id not in self.connections:
                return
            
            metrics = self.connections[connection_id]
            del self.connections[connection_id]
            self.total_connections_closed += 1
            
            # Record metrics
            connection_age = metrics.get_age()
            record_latency(
                "connection_monitor",
                "connection_lifetime",
                connection_age * 1000,
                labels={
                    "resource_type": metrics.resource_type.value,
                    "provider": metrics.provider or "unknown"
                }
            )
            
            # Trigger callbacks
            await self._trigger_callbacks("connection_unregistered", metrics)
    
    async def _monitoring_loop(self):
        """Main monitoring loop."""
        while self.running:
            try:
                await self._collect_system_metrics()
                await self._check_resource_limits()
                await self._detect_connection_leaks()
                
                await asyncio.sleep(10)  # Monitor every 10 seconds
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                await log_error(
                    "connection_monitor",
                    "Error in monitoring loop",
                    error=str(e)
                )
                await asyncio.sleep(5)
    
    async def _cleanup_loop(self):
        """Cleanup loop for stale connections."""
        while self.running:
            try:
                await asyncio.sleep(self.limits.cleanup_interval)
                await self._cleanup_stale_connections()
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                await log_error(
                    "connection_monitor",
                    "Error in cleanup loop",
                    error=str(e)
                )
    
    async def _collect_system_metrics(self):
        """Collect system-level metrics."""
        try:
            # Get system metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            process = psutil.Process()
            
            # Get process-specific metrics
            process_memory = process.memory_info()
            open_files = len(process.open_files())
            threads = process.num_threads()
            
            # Get network connections
            network_connections = len(psutil.net_connections())
            
            # Get active asyncio tasks
            active_tasks = len([task for task in asyncio.all_tasks() if not task.done()])
            
            # Create metrics object
            metrics = SystemMetrics(
                timestamp=time.time(),
                cpu_percent=cpu_percent,
                memory_percent=memory.percent,
                memory_mb=process_memory.rss / 1024 / 1024,
                open_files=open_files,
                threads=threads,
                network_connections=network_connections,
                active_tasks=active_tasks
            )
            
            # Add connection statistics
            async with self._lock:
                for connection in self.connections.values():
                    metrics.connections_by_type[connection.resource_type] = \
                        metrics.connections_by_type.get(connection.resource_type, 0) + 1
                    
                    metrics.connections_by_state[connection.state] = \
                        metrics.connections_by_state.get(connection.state, 0) + 1
                    
                    if connection.provider:
                        metrics.connections_by_provider[connection.provider] = \
                            metrics.connections_by_provider.get(connection.provider, 0) + 1
            
            self.system_metrics_history.append(metrics)
            
            # Record metrics
            record_counter("connection_monitor", "system_metrics_collected")
            
        except Exception as e:
            await log_error(
                "connection_monitor",
                "Error collecting system metrics",
                error=str(e)
            )
    
    async def _check_resource_limits(self):
        """Check resource limits and trigger alerts."""
        if not self.system_metrics_history:
            return
        
        latest_metrics = self.system_metrics_history[-1]
        alerts = []
        
        # Check memory limit
        if latest_metrics.memory_mb > self.limits.max_memory_mb:
            alerts.append(f"Memory usage ({latest_metrics.memory_mb:.1f}MB) exceeds limit ({self.limits.max_memory_mb}MB)")
        
        # Check file handle limit
        if latest_metrics.open_files > self.limits.max_file_handles:
            alerts.append(f"Open files ({latest_metrics.open_files}) exceeds limit ({self.limits.max_file_handles})")
        
        # Check thread limit
        if latest_metrics.threads > self.limits.max_threads:
            alerts.append(f"Thread count ({latest_metrics.threads}) exceeds limit ({self.limits.max_threads})")
        
        # Check task limit
        if latest_metrics.active_tasks > self.limits.max_tasks:
            alerts.append(f"Active tasks ({latest_metrics.active_tasks}) exceeds limit ({self.limits.max_tasks})")
        
        # Check connection limits
        total_connections = sum(latest_metrics.connections_by_type.values())
        if total_connections > self.limits.max_connections:
            alerts.append(f"Total connections ({total_connections}) exceeds limit ({self.limits.max_connections})")
        
        # Send alerts
        for alert in alerts:
            await log_warning(
                "connection_monitor",
                "Resource limit exceeded",
                alert=alert,
                metrics=latest_metrics.__dict__
            )
            self.alerts_sent += 1
    
    async def _detect_connection_leaks(self):
        """Detect potential connection leaks."""
        current_time = time.time()
        leaked_connections = []
        
        async with self._lock:
            for connection_id, metrics in self.connections.items():
                # Check for very old connections
                if metrics.get_age() > self.limits.max_connection_age:
                    leaked_connections.append((connection_id, metrics))
                
                # Check for idle connections
                elif metrics.get_idle_time() > self.limits.max_idle_time and metrics.state == ConnectionState.IDLE:
                    leaked_connections.append((connection_id, metrics))
        
        # Log potential leaks
        for connection_id, metrics in leaked_connections:
            await log_warning(
                "connection_monitor",
                "Potential connection leak detected",
                connection_id=connection_id,
                resource_type=metrics.resource_type.value,
                age_seconds=metrics.get_age(),
                idle_seconds=metrics.get_idle_time(),
                provider=metrics.provider
            )
    
    async def _cleanup_stale_connections(self):
        """Clean up stale connections."""
        current_time = time.time()
        cleanup_candidates = []
        
        async with self._lock:
            for connection_id, metrics in self.connections.items():
                # Mark very old connections for cleanup
                if metrics.get_age() > self.limits.max_connection_age:
                    cleanup_candidates.append(connection_id)
                
                # Mark idle connections for cleanup
                elif (metrics.get_idle_time() > self.limits.max_idle_time and 
                      metrics.state in [ConnectionState.IDLE, ConnectionState.ERROR]):
                    cleanup_candidates.append(connection_id)
        
        # Perform cleanup
        for connection_id in cleanup_candidates:
            await self._cleanup_connection(connection_id)
    
    async def _cleanup_connection(self, connection_id: str):
        """Clean up a specific connection."""
        try:
            async with self._lock:
                if connection_id in self.connections:
                    metrics = self.connections[connection_id]
                    
                    # Trigger cleanup callbacks
                    await self._trigger_callbacks("connection_cleanup", metrics)
                    
                    # Remove from tracking
                    del self.connections[connection_id]
                    self.total_cleanup_operations += 1
                    
                    await log_info(
                        "connection_monitor",
                        "Connection cleaned up",
                        connection_id=connection_id,
                        resource_type=metrics.resource_type.value,
                        age_seconds=metrics.get_age()
                    )
                    
        except Exception as e:
            await log_error(
                "connection_monitor",
                "Error cleaning up connection",
                connection_id=connection_id,
                error=str(e)
            )
    
    async def _trigger_callbacks(self, event: str, metrics: ConnectionMetrics):
        """Trigger callbacks for connection events."""
        for callback in self.connection_callbacks.get(event, []):
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(metrics)
                else:
                    callback(metrics)
            except Exception as e:
                logger.warning(f"Error in callback for {event}: {e}")
    
    def add_connection_callback(self, event: str, callback: Callable):
        """Add callback for connection events."""
        self.connection_callbacks[event].append(callback)
    
    def get_connection_stats(self) -> Dict[str, Any]:
        """Get comprehensive connection statistics."""
        if not self.system_metrics_history:
            return {"status": "no_metrics"}
        
        latest_metrics = self.system_metrics_history[-1]
        
        async def _get_connection_details():
            async with self._lock:
                return {
                    "total_connections": len(self.connections),
                    "connections_by_type": dict(latest_metrics.connections_by_type),
                    "connections_by_state": dict(latest_metrics.connections_by_state),
                    "connections_by_provider": dict(latest_metrics.connections_by_provider),
                    "connection_details": [
                        {
                            "id": conn_id,
                            "type": metrics.resource_type.value,
                            "state": metrics.state.value,
                            "age_seconds": metrics.get_age(),
                            "idle_seconds": metrics.get_idle_time(),
                            "provider": metrics.provider,
                            "requests": metrics.requests_count,
                            "errors": metrics.errors_count
                        }
                        for conn_id, metrics in list(self.connections.items())
                    ]
                }
        
        return {
            "system_metrics": latest_metrics.__dict__,
            "monitor_stats": {
                "total_connections_created": self.total_connections_created,
                "total_connections_closed": self.total_connections_closed,
                "total_cleanup_operations": self.total_cleanup_operations,
                "alerts_sent": self.alerts_sent,
                "running": self.running
            },
            "resource_limits": self.limits.__dict__
        }
    
    async def get_health_status(self) -> Dict[str, Any]:
        """Get health status for the connection monitor."""
        stats = self.get_connection_stats()
        
        if not self.system_metrics_history:
            return {"status": "starting", "details": "No metrics collected yet"}
        
        latest_metrics = self.system_metrics_history[-1]
        
        # Determine health status
        health_issues = []
        
        if latest_metrics.memory_mb > self.limits.max_memory_mb * 0.8:
            health_issues.append("high_memory_usage")
        
        if latest_metrics.open_files > self.limits.max_file_handles * 0.8:
            health_issues.append("high_file_handle_usage")
        
        total_connections = sum(latest_metrics.connections_by_type.values())
        if total_connections > self.limits.max_connections * 0.8:
            health_issues.append("high_connection_count")
        
        if health_issues:
            status = "degraded"
        else:
            status = "healthy"
        
        return {
            "status": status,
            "health_issues": health_issues,
            "metrics_summary": {
                "memory_mb": latest_metrics.memory_mb,
                "open_files": latest_metrics.open_files,
                "total_connections": total_connections,
                "cpu_percent": latest_metrics.cpu_percent
            }
        }


# Global connection monitor instance
_connection_monitor: Optional[ConnectionMonitor] = None


def get_connection_monitor() -> ConnectionMonitor:
    """Get the global connection monitor."""
    global _connection_monitor
    if _connection_monitor is None:
        _connection_monitor = ConnectionMonitor()
    return _connection_monitor


# Context manager for connection monitoring
@asynccontextmanager
async def monitored_connection(connection_id: str, 
                             resource_type: ResourceType,
                             provider: str = None,
                             endpoint: str = None):
    """Context manager for monitoring a connection."""
    monitor = get_connection_monitor()
    
    # Register connection
    metrics = await monitor.register_connection(
        connection_id, resource_type, provider, endpoint
    )
    
    try:
        # Update to active state
        await monitor.update_connection_state(connection_id, ConnectionState.ACTIVE)
        yield metrics
    finally:
        # Unregister connection
        await monitor.unregister_connection(connection_id)


# Decorator for monitoring function calls
def monitor_connection(resource_type: ResourceType, provider: str = None):
    """Decorator for monitoring connections in functions."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            connection_id = f"{func.__name__}_{int(time.time() * 1000)}"
            
            async with monitored_connection(connection_id, resource_type, provider):
                return await func(*args, **kwargs)
        
        return wrapper
    return decorator