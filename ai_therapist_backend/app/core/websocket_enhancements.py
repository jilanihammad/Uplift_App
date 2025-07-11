"""
WebSocket Performance Enhancements

This module provides enhanced WebSocket management with:
- Proper connection lifecycle management
- Control frame signaling for immediate cleanup
- Connection duration monitoring
- Memory-efficient WebSocket pooling
- Graceful disconnection handling
"""

import asyncio
import json
import logging
import time
from typing import Dict, Any, Optional, Set
from dataclasses import dataclass, field
from enum import Enum
from fastapi import WebSocket
from contextlib import asynccontextmanager
import weakref

from app.core.observability import log_info, log_warning, log_error, record_latency, record_counter

logger = logging.getLogger(__name__)


class WebSocketState(Enum):
    """WebSocket connection states."""
    CONNECTING = "connecting"
    CONNECTED = "connected"
    STREAMING = "streaming"
    COMPLETING = "completing"
    DISCONNECTING = "disconnecting"
    DISCONNECTED = "disconnected"


class ControlFrameType(Enum):
    """Control frame types for WebSocket communication."""
    HELLO = "hello"
    READY = "ready"
    STREAMING_START = "streaming_start"
    STREAMING_CHUNK = "streaming_chunk"
    STREAMING_DONE = "streaming_done"
    COMPLETION_SIGNAL = "completion_signal"
    DISCONNECT_PREPARE = "disconnect_prepare"
    DISCONNECT_CONFIRM = "disconnect_confirm"
    ERROR = "error"
    HEARTBEAT = "heartbeat"


@dataclass
class WebSocketConnection:
    """Enhanced WebSocket connection tracking."""
    websocket: WebSocket
    client_id: str
    connection_time: float
    state: WebSocketState = WebSocketState.CONNECTING
    last_activity: float = field(default_factory=time.time)
    bytes_sent: int = 0
    messages_sent: int = 0
    control_frames_sent: int = 0
    streaming_sessions: int = 0
    total_streaming_time: float = 0.0
    user_info: Optional[Dict[str, Any]] = None
    
    def update_activity(self):
        """Update last activity timestamp."""
        self.last_activity = time.time()
    
    def get_connection_duration(self) -> float:
        """Get connection duration in seconds."""
        return time.time() - self.connection_time
    
    def get_idle_time(self) -> float:
        """Get time since last activity in seconds."""
        return time.time() - self.last_activity


class EnhancedWebSocketManager:
    """
    Enhanced WebSocket manager with proper connection lifecycle management.
    
    Features:
    - Connection lifecycle tracking
    - Control frame signaling
    - Automatic cleanup
    - Memory monitoring
    - Performance metrics
    """
    
    def __init__(self, 
                 max_connections: int = 1000,
                 connection_timeout: float = 300.0,  # 5 minutes
                 cleanup_interval: float = 60.0):    # 1 minute
        self.max_connections = max_connections
        self.connection_timeout = connection_timeout
        self.cleanup_interval = cleanup_interval
        
        # Connection tracking
        self.connections: Dict[str, WebSocketConnection] = {}
        self.connection_states: Dict[str, WebSocketState] = {}
        
        # Background tasks
        self.cleanup_task: Optional[asyncio.Task] = None
        self.running = False
        
        # Metrics
        self.total_connections = 0
        self.active_connections = 0
        self.completed_connections = 0
        self.failed_connections = 0
        
        # Weak references for cleanup
        self._cleanup_refs: Set[weakref.ref] = set()
        
    async def start(self):
        """Start the WebSocket manager."""
        if self.running:
            return
        
        self.running = True
        self.cleanup_task = asyncio.create_task(self._cleanup_loop())
        
        await log_info(
            "websocket_manager",
            "Enhanced WebSocket manager started",
            max_connections=self.max_connections,
            connection_timeout=self.connection_timeout
        )
    
    async def stop(self):
        """Stop the WebSocket manager."""
        self.running = False
        
        if self.cleanup_task:
            self.cleanup_task.cancel()
            try:
                await self.cleanup_task
            except asyncio.CancelledError:
                pass
        
        # Close all connections
        await self._close_all_connections()
        
        await log_info(
            "websocket_manager",
            "Enhanced WebSocket manager stopped",
            total_connections=self.total_connections,
            completed_connections=self.completed_connections
        )
    
    async def register_connection(self, 
                                websocket: WebSocket, 
                                client_id: str,
                                user_info: Optional[Dict[str, Any]] = None) -> bool:
        """Register a new WebSocket connection."""
        # Check connection limits
        if len(self.connections) >= self.max_connections:
            await log_warning(
                "websocket_manager",
                "Connection limit reached",
                max_connections=self.max_connections,
                active_connections=len(self.connections)
            )
            return False
        
        # Create connection tracking
        connection = WebSocketConnection(
            websocket=websocket,
            client_id=client_id,
            connection_time=time.time(),
            user_info=user_info
        )
        
        self.connections[client_id] = connection
        self.connection_states[client_id] = WebSocketState.CONNECTING
        self.total_connections += 1
        self.active_connections += 1
        
        # Send hello control frame
        await self._send_control_frame(client_id, ControlFrameType.HELLO, {
            "client_id": client_id,
            "connection_time": connection.connection_time,
            "capabilities": {
                "control_frames": True,
                "binary_frames": True,
                "compression": True
            }
        })
        
        # Update connection state
        await self._update_connection_state(client_id, WebSocketState.CONNECTED)
        
        # Register with connection monitor
        try:
            from app.core.connection_monitor import get_connection_monitor, ResourceType
            monitor = get_connection_monitor()
            await monitor.register_connection(
                connection_id=client_id,
                resource_type=ResourceType.WEBSOCKET_CONNECTION,
                provider="websocket"
            )
        except ImportError:
            pass  # Connection monitor not available
        
        await log_info(
            "websocket_manager",
            "WebSocket connection registered",
            client_id=client_id,
            active_connections=len(self.connections)
        )
        
        record_counter("websocket", "connections_registered")
        return True
    
    async def start_streaming(self, client_id: str, stream_type: str = "tts") -> bool:
        """Start streaming session for a client."""
        if client_id not in self.connections:
            return False
        
        connection = self.connections[client_id]
        connection.streaming_sessions += 1
        connection.update_activity()
        
        # Send streaming start control frame
        await self._send_control_frame(client_id, ControlFrameType.STREAMING_START, {
            "stream_type": stream_type,
            "session_id": connection.streaming_sessions,
            "start_time": time.time()
        })
        
        await self._update_connection_state(client_id, WebSocketState.STREAMING)
        
        record_counter("websocket", "streaming_sessions_started", 
                      labels={"stream_type": stream_type})
        return True
    
    async def send_streaming_chunk(self, 
                                  client_id: str, 
                                  chunk_data: bytes,
                                  chunk_sequence: int = 0) -> bool:
        """Send streaming chunk with tracking."""
        if client_id not in self.connections:
            return False
        
        connection = self.connections[client_id]
        websocket = connection.websocket
        
        try:
            # Send binary data
            await websocket.send_bytes(chunk_data)
            
            # Update connection stats
            connection.bytes_sent += len(chunk_data)
            connection.messages_sent += 1
            connection.update_activity()
            
            # Send chunk control frame (optional, for sequence tracking)
            if chunk_sequence > 0:
                await self._send_control_frame(client_id, ControlFrameType.STREAMING_CHUNK, {
                    "sequence": chunk_sequence,
                    "bytes_sent": len(chunk_data),
                    "total_bytes": connection.bytes_sent
                })
            
            return True
            
        except Exception as e:
            await log_error(
                "websocket_manager",
                "Failed to send streaming chunk",
                client_id=client_id,
                error=str(e)
            )
            return False
    
    async def complete_streaming(self, 
                               client_id: str,
                               total_bytes: int = 0,
                               total_duration: float = 0.0,
                               auto_disconnect: bool = True) -> bool:
        """Complete streaming session with proper cleanup signaling."""
        if client_id not in self.connections:
            return False
        
        connection = self.connections[client_id]
        connection.total_streaming_time += total_duration
        connection.update_activity()
        
        # Send streaming done control frame
        await self._send_control_frame(client_id, ControlFrameType.STREAMING_DONE, {
            "total_bytes": total_bytes or connection.bytes_sent,
            "total_duration": total_duration,
            "total_messages": connection.messages_sent,
            "session_id": connection.streaming_sessions
        })
        
        # Send completion signal for immediate client cleanup
        await self._send_control_frame(client_id, ControlFrameType.COMPLETION_SIGNAL, {
            "reason": "streaming_complete",
            "auto_disconnect": auto_disconnect,
            "cleanup_delay": 0.1  # 100ms delay for client cleanup
        })
        
        await self._update_connection_state(client_id, WebSocketState.COMPLETING)
        
        # Record metrics
        record_latency("websocket", "streaming_duration", total_duration * 1000)
        record_counter("websocket", "streaming_sessions_completed")
        
        # Auto-disconnect if requested
        if auto_disconnect:
            await asyncio.sleep(0.1)  # Give client time to process
            await self.disconnect_client(client_id, "streaming_complete")
        
        return True
    
    async def disconnect_client(self, 
                              client_id: str, 
                              reason: str = "normal_closure") -> bool:
        """Gracefully disconnect a client."""
        if client_id not in self.connections:
            return False
        
        connection = self.connections[client_id]
        
        # Send disconnect prepare signal
        await self._send_control_frame(client_id, ControlFrameType.DISCONNECT_PREPARE, {
            "reason": reason,
            "connection_duration": connection.get_connection_duration(),
            "total_bytes_sent": connection.bytes_sent
        })
        
        await self._update_connection_state(client_id, WebSocketState.DISCONNECTING)
        
        # Give client time to process disconnect signal
        await asyncio.sleep(0.05)  # 50ms
        
        # Close WebSocket connection
        try:
            await connection.websocket.close(code=1000, reason=reason)
        except Exception as e:
            await log_warning(
                "websocket_manager",
                "Error closing WebSocket",
                client_id=client_id,
                error=str(e)
            )
        
        # Clean up connection
        await self._cleanup_connection(client_id)
        
        return True
    
    async def _send_control_frame(self, 
                                client_id: str, 
                                frame_type: ControlFrameType, 
                                data: Dict[str, Any]) -> bool:
        """Send control frame to client."""
        if client_id not in self.connections:
            return False
        
        connection = self.connections[client_id]
        
        control_frame = {
            "type": frame_type.value,
            "timestamp": time.time(),
            "client_id": client_id,
            "data": data
        }
        
        try:
            await connection.websocket.send_text(json.dumps(control_frame))
            connection.control_frames_sent += 1
            connection.update_activity()
            return True
            
        except Exception as e:
            await log_error(
                "websocket_manager",
                "Failed to send control frame",
                client_id=client_id,
                frame_type=frame_type.value,
                error=str(e)
            )
            return False
    
    async def _update_connection_state(self, client_id: str, state: WebSocketState):
        """Update connection state."""
        if client_id in self.connection_states:
            old_state = self.connection_states[client_id]
            self.connection_states[client_id] = state
            
            if client_id in self.connections:
                self.connections[client_id].state = state
            
            await log_info(
                "websocket_manager",
                "Connection state updated",
                client_id=client_id,
                old_state=old_state.value,
                new_state=state.value
            )
    
    async def _cleanup_connection(self, client_id: str):
        """Clean up connection resources."""
        if client_id in self.connections:
            connection = self.connections[client_id]
            
            # Record connection metrics
            duration = connection.get_connection_duration()
            record_latency("websocket", "connection_duration", duration * 1000)
            
            # Remove from tracking
            del self.connections[client_id]
            self.active_connections -= 1
            self.completed_connections += 1
            
            # Update state
            if client_id in self.connection_states:
                await self._update_connection_state(client_id, WebSocketState.DISCONNECTED)
                del self.connection_states[client_id]
            
            await log_info(
                "websocket_manager",
                "Connection cleaned up",
                client_id=client_id,
                duration=duration,
                bytes_sent=connection.bytes_sent,
                messages_sent=connection.messages_sent
            )
    
    async def _cleanup_loop(self):
        """Background cleanup loop."""
        while self.running:
            try:
                await asyncio.sleep(self.cleanup_interval)
                await self._cleanup_stale_connections()
            except asyncio.CancelledError:
                break
            except Exception as e:
                await log_error(
                    "websocket_manager",
                    "Error in cleanup loop",
                    error=str(e)
                )
    
    async def _cleanup_stale_connections(self):
        """Clean up stale connections."""
        current_time = time.time()
        stale_clients = []
        
        for client_id, connection in self.connections.items():
            if (current_time - connection.last_activity) > self.connection_timeout:
                stale_clients.append(client_id)
        
        for client_id in stale_clients:
            await log_warning(
                "websocket_manager",
                "Cleaning up stale connection",
                client_id=client_id,
                idle_time=self.connections[client_id].get_idle_time()
            )
            await self.disconnect_client(client_id, "stale_connection")
    
    async def _close_all_connections(self):
        """Close all active connections."""
        clients_to_close = list(self.connections.keys())
        
        for client_id in clients_to_close:
            await self.disconnect_client(client_id, "manager_shutdown")
    
    def get_connection_stats(self) -> Dict[str, Any]:
        """Get connection statistics."""
        return {
            "total_connections": self.total_connections,
            "active_connections": self.active_connections,
            "completed_connections": self.completed_connections,
            "failed_connections": self.failed_connections,
            "max_connections": self.max_connections,
            "connection_utilization": self.active_connections / self.max_connections,
            "average_connection_duration": self._calculate_average_duration()
        }
    
    def _calculate_average_duration(self) -> float:
        """Calculate average connection duration."""
        if not self.connections:
            return 0.0
        
        total_duration = sum(
            conn.get_connection_duration() 
            for conn in self.connections.values()
        )
        
        return total_duration / len(self.connections)
    
    @asynccontextmanager
    async def connection_context(self, websocket: WebSocket, client_id: str, user_info: Optional[Dict[str, Any]] = None):
        """Context manager for WebSocket connections."""
        success = await self.register_connection(websocket, client_id, user_info)
        
        if not success:
            raise RuntimeError("Failed to register WebSocket connection")
        
        try:
            yield client_id
        finally:
            await self.disconnect_client(client_id, "context_exit")


# Global WebSocket manager instance
_websocket_manager: Optional[EnhancedWebSocketManager] = None


def get_websocket_manager() -> EnhancedWebSocketManager:
    """Get the global WebSocket manager."""
    global _websocket_manager
    if _websocket_manager is None:
        _websocket_manager = EnhancedWebSocketManager()
    return _websocket_manager


# Context manager for WebSocket connections
@asynccontextmanager
async def websocket_connection(websocket: WebSocket, client_id: str, user_info: Optional[Dict[str, Any]] = None):
    """Context manager for WebSocket connections."""
    manager = get_websocket_manager()
    
    # Ensure manager is started
    if not manager.running:
        await manager.start()
    
    async with manager.connection_context(websocket, client_id, user_info) as client_id:
        yield client_id


# Decorator for WebSocket endpoints
def websocket_managed(func):
    """Decorator to add WebSocket management to endpoints."""
    async def wrapper(websocket: WebSocket, *args, **kwargs):
        client_id = f"client_{int(time.time() * 1000)}_{id(websocket)}"
        
        async with websocket_connection(websocket, client_id) as managed_client_id:
            return await func(websocket, managed_client_id, *args, **kwargs)
    
    return wrapper