"""
Request Middleware for Enhanced Logging

This module provides middleware to automatically set request context
for all HTTP requests, enabling proper request tracing and correlation.
"""

import time
import uuid
from typing import Callable
from fastapi import Request, Response
from fastapi.middleware.base import BaseHTTPMiddleware

from app.core.enhanced_logging import (
    RequestTraceContext, 
    get_logger,
    set_request_context,
    clear_request_context
)

logger = get_logger(__name__)


class RequestTracingMiddleware(BaseHTTPMiddleware):
    """
    Middleware to automatically set request context for all HTTP requests.
    
    Features:
    - Generates unique request IDs
    - Extracts or generates trace IDs
    - Sets logging context for the entire request lifecycle
    - Adds request timing metrics
    - Handles request ID propagation
    """
    
    def __init__(self, app, generate_request_id: bool = True, generate_trace_id: bool = True):
        super().__init__(app)
        self.generate_request_id = generate_request_id
        self.generate_trace_id = generate_trace_id
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Process request with automatic tracing context."""
        start_time = time.time()
        
        # Generate or extract request ID
        request_id = self._get_or_generate_request_id(request)
        
        # Generate or extract trace ID
        trace_id = self._get_or_generate_trace_id(request)
        
        # Set request context
        with RequestTraceContext(request_id, trace_id):
            try:
                # Log request start
                logger.info(
                    f"Request started: {request.method} {request.url.path}",
                    extra={
                        'method': request.method,
                        'path': request.url.path,
                        'query_params': str(request.query_params) if request.query_params else None,
                        'user_agent': request.headers.get('user-agent'),
                        'client_ip': self._get_client_ip(request)
                    }
                )
                
                # Process request
                response = await call_next(request)
                
                # Calculate request duration
                duration_ms = (time.time() - start_time) * 1000
                
                # Add headers to response
                response.headers["X-Request-ID"] = request_id
                response.headers["X-Trace-ID"] = trace_id
                
                # Log request completion
                logger.info(
                    f"Request completed: {request.method} {request.url.path}",
                    extra={
                        'method': request.method,
                        'path': request.url.path,
                        'status_code': response.status_code,
                        'duration_ms': duration_ms,
                        'content_length': response.headers.get('content-length')
                    }
                )
                
                return response
                
            except Exception as e:
                # Calculate request duration
                duration_ms = (time.time() - start_time) * 1000
                
                # Log request error
                logger.error(
                    f"Request failed: {request.method} {request.url.path}",
                    extra={
                        'method': request.method,
                        'path': request.url.path,
                        'error': str(e),
                        'duration_ms': duration_ms
                    },
                    exc_info=True
                )
                
                raise
    
    def _get_or_generate_request_id(self, request: Request) -> str:
        """Get request ID from headers or generate a new one."""
        if not self.generate_request_id:
            return ''
        
        # Try to get from various possible headers
        request_id = (
            request.headers.get('x-request-id') or
            request.headers.get('x-correlation-id') or
            request.headers.get('request-id') or
            request.headers.get('correlation-id')
        )
        
        if not request_id:
            # Generate new request ID
            request_id = f"req_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        return request_id
    
    def _get_or_generate_trace_id(self, request: Request) -> str:
        """Get trace ID from headers or generate a new one."""
        if not self.generate_trace_id:
            return ''
        
        # Try to get from various possible headers
        trace_id = (
            request.headers.get('x-trace-id') or
            request.headers.get('x-b3-traceid') or
            request.headers.get('traceparent') or
            request.headers.get('trace-id')
        )
        
        if not trace_id:
            # Generate new trace ID
            trace_id = f"trace_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        return trace_id
    
    def _get_client_ip(self, request: Request) -> str:
        """Get client IP address, handling proxies."""
        # Try various headers in order of preference
        ip = (
            request.headers.get('x-forwarded-for') or
            request.headers.get('x-real-ip') or
            request.headers.get('cf-connecting-ip') or  # Cloudflare
            request.headers.get('x-client-ip') or
            str(request.client.host if request.client else 'unknown')
        )
        
        # If x-forwarded-for contains multiple IPs, take the first one
        if ',' in ip:
            ip = ip.split(',')[0].strip()
        
        return ip


class WebSocketTracingMiddleware:
    """
    Middleware-like functionality for WebSocket connections.
    
    Since WebSockets don't use standard HTTP middleware, this provides
    similar functionality through context managers.
    """
    
    @staticmethod
    def create_websocket_context(websocket, client_id: str = None) -> RequestTraceContext:
        """Create request context for WebSocket connections."""
        # Generate request ID for WebSocket
        request_id = client_id or f"ws_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        # Generate trace ID
        trace_id = f"ws_trace_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}"
        
        return RequestTraceContext(request_id, trace_id)
    
    @staticmethod
    def log_websocket_event(event: str, client_id: str = None, **kwargs):
        """Log WebSocket events with proper context."""
        logger.info(
            f"WebSocket {event}",
            extra={
                'websocket_client_id': client_id,
                'event': event,
                **kwargs
            }
        )


# Global middleware instance
request_tracing_middleware = RequestTracingMiddleware
websocket_tracing = WebSocketTracingMiddleware()