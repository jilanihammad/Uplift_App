"""
Observability Middleware for FastAPI

This module provides middleware for automatic request tracing, performance monitoring,
and structured logging in FastAPI applications.

Features:
- Automatic request ID and trace ID injection
- Request/response timing
- Structured logging
- Performance metrics collection
- Error tracking
"""

import time
import uuid
from typing import Callable, Dict, Any, Optional
from fastapi import Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.core.observability import (
    observability_manager,
    RequestTracer,
    record_latency,
    record_counter,
    log_info,
    log_error,
    log_warning
)


class ObservabilityMiddleware(BaseHTTPMiddleware):
    """
    Middleware for comprehensive observability in FastAPI applications.
    
    Features:
    - Request ID and trace ID injection
    - Performance monitoring
    - Structured logging
    - Error tracking
    - Health check optimization
    """
    
    def __init__(self, app: ASGIApp, service_name: str = "ai_therapist_backend"):
        super().__init__(app)
        self.service_name = service_name
        
        # Performance tracking
        self.request_count = 0
        self.error_count = 0
        self.total_response_time = 0.0
        
        # Health check optimization
        self.health_endpoints = {"/health", "/health/", "/healthz", "/healthz/"}
        
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Process request with observability."""
        start_time = time.time()
        
        # Generate or extract request/trace IDs
        request_id = self._get_or_generate_request_id(request)
        trace_id = self._get_or_generate_trace_id(request)
        
        # Set request context
        RequestTracer.set_request_context(request_id, trace_id)
        
        # Skip detailed logging for health checks
        is_health_check = request.url.path in self.health_endpoints
        
        # Log request start (skip for health checks)
        if not is_health_check:
            await log_info(
                self.service_name,
                f"Request started: {request.method} {request.url.path}",
                method=request.method,
                path=request.url.path,
                query_params=str(request.query_params),
                user_agent=request.headers.get("user-agent", ""),
                client_ip=self._get_client_ip(request)
            )
        
        # Process request
        response = None
        error = None
        
        try:
            response = await call_next(request)
            
            # Calculate response time
            duration_ms = (time.time() - start_time) * 1000
            
            # Update internal metrics
            self.request_count += 1
            self.total_response_time += duration_ms
            
            # Add observability headers
            response.headers["X-Request-ID"] = request_id
            response.headers["X-Trace-ID"] = trace_id
            response.headers["X-Response-Time"] = f"{duration_ms:.2f}ms"
            
            # Record success metrics
            if not is_health_check:
                record_latency(
                    self.service_name, 
                    "request", 
                    duration_ms,
                    labels={
                        "method": request.method,
                        "path": request.url.path,
                        "status_code": str(response.status_code)
                    }
                )
                
                record_counter(
                    self.service_name,
                    "requests_total",
                    labels={
                        "method": request.method,
                        "path": request.url.path,
                        "status_code": str(response.status_code)
                    }
                )
                
                # Log successful request
                await log_info(
                    self.service_name,
                    f"Request completed: {request.method} {request.url.path}",
                    method=request.method,
                    path=request.url.path,
                    status_code=response.status_code,
                    duration_ms=duration_ms
                )
            
            return response
            
        except Exception as e:
            error = e
            duration_ms = (time.time() - start_time) * 1000
            
            # Update error metrics
            self.error_count += 1
            
            # Record error metrics
            record_latency(
                self.service_name, 
                "request", 
                duration_ms,
                labels={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": "500"
                }
            )
            
            record_counter(
                self.service_name,
                "requests_total",
                labels={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": "500"
                }
            )
            
            record_counter(
                self.service_name,
                "errors_total",
                labels={
                    "method": request.method,
                    "path": request.url.path,
                    "error_type": type(e).__name__
                }
            )
            
            # Log error
            await log_error(
                self.service_name,
                f"Request failed: {request.method} {request.url.path}",
                method=request.method,
                path=request.url.path,
                duration_ms=duration_ms,
                error=str(e),
                error_type=type(e).__name__
            )
            
            # Return error response
            return JSONResponse(
                status_code=500,
                content={
                    "error": "Internal Server Error",
                    "request_id": request_id,
                    "trace_id": trace_id
                },
                headers={
                    "X-Request-ID": request_id,
                    "X-Trace-ID": trace_id,
                    "X-Response-Time": f"{duration_ms:.2f}ms"
                }
            )
    
    def _get_or_generate_request_id(self, request: Request) -> str:
        """Get request ID from header or generate a new one."""
        request_id = request.headers.get("X-Request-ID")
        if not request_id:
            request_id = str(uuid.uuid4())
        return request_id
    
    def _get_or_generate_trace_id(self, request: Request) -> str:
        """Get trace ID from header or generate a new one."""
        trace_id = request.headers.get("X-Trace-ID")
        if not trace_id:
            trace_id = str(uuid.uuid4())
        return trace_id
    
    def _get_client_ip(self, request: Request) -> str:
        """Extract client IP address from request."""
        # Check for forwarded headers (for load balancers/proxies)
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
        
        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            return real_ip
        
        # Fall back to direct connection
        if request.client:
            return request.client.host
        
        return "unknown"
    
    def get_middleware_stats(self) -> Dict[str, Any]:
        """Get middleware statistics."""
        avg_response_time = (
            self.total_response_time / self.request_count 
            if self.request_count > 0 else 0
        )
        
        error_rate = (
            self.error_count / self.request_count 
            if self.request_count > 0 else 0
        )
        
        return {
            "request_count": self.request_count,
            "error_count": self.error_count,
            "error_rate": error_rate,
            "average_response_time_ms": avg_response_time
        }


class LLMObservabilityMiddleware:
    """
    Specialized middleware for LLM operations.
    
    This can be used as a context manager or decorator for LLM-specific operations
    to provide detailed observability.
    """
    
    def __init__(self, provider: str, operation: str):
        self.provider = provider
        self.operation = operation
        self.start_time = None
        
    async def __aenter__(self):
        """Enter context manager."""
        self.start_time = time.time()
        
        await log_info(
            "llm_manager",
            f"Starting LLM operation: {self.operation}",
            provider=self.provider,
            method=self.operation
        )
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Exit context manager."""
        duration_ms = (time.time() - self.start_time) * 1000
        
        if exc_type is None:
            # Success
            await log_info(
                "llm_manager",
                f"LLM operation completed: {self.operation}",
                provider=self.provider,
                method=self.operation,
                duration_ms=duration_ms
            )
            
            record_latency(
                "llm", 
                self.operation, 
                duration_ms,
                labels={"provider": self.provider}
            )
            
            record_counter(
                "llm",
                f"{self.operation}_success",
                labels={"provider": self.provider}
            )
        else:
            # Error
            await log_error(
                "llm_manager",
                f"LLM operation failed: {self.operation}",
                provider=self.provider,
                method=self.operation,
                duration_ms=duration_ms,
                error=str(exc_val),
                error_type=exc_type.__name__
            )
            
            record_latency(
                "llm", 
                self.operation, 
                duration_ms,
                labels={"provider": self.provider}
            )
            
            record_counter(
                "llm",
                f"{self.operation}_failure",
                labels={"provider": self.provider}
            )
        
        return False  # Don't suppress exceptions


# Convenience functions for FastAPI integration
def add_observability_middleware(app, service_name: str = "ai_therapist_backend"):
    """Add observability middleware to FastAPI app."""
    middleware = ObservabilityMiddleware(app, service_name)
    app.add_middleware(BaseHTTPMiddleware, dispatch=middleware.dispatch)
    return middleware


def llm_observe(provider: str, operation: str):
    """Context manager for LLM operation observability."""
    return LLMObservabilityMiddleware(provider, operation)


# Decorator for automatic LLM observability
def observe_llm_operation(provider: str, operation: str):
    """Decorator for automatic LLM operation observability."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            async with llm_observe(provider, operation):
                return await func(*args, **kwargs)
        return wrapper
    return decorator