# app/core/rate_limiter.py

from fastapi import Request, Response, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
import time
from typing import Dict, Tuple


def _get_client_ip(request: Request) -> str:
    """Extract real client IP, respecting X-Forwarded-For behind load balancers (Cloud Run, etc.)."""
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        # First IP in the chain is the original client
        return forwarded_for.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    In-memory IP-based rate limiter.
    NOTE: On Cloud Run / multi-instance deployments, each instance tracks independently.
    This provides per-instance protection against abuse but is NOT globally consistent.
    For strict global rate limiting, use Redis or a managed API gateway.
    """
    def __init__(self, app, requests_per_minute: int = 60):
        super().__init__(app)
        self.requests_per_minute = requests_per_minute
        self.request_records: Dict[str, Tuple[int, float]] = {}  # key: (count, window_start)
    
    async def dispatch(self, request: Request, call_next):
        # Skip rate limiting for WebSocket connections
        if request.url.path.startswith("/ws/") or "websocket" in request.headers.get("upgrade", "").lower():
            return await call_next(request)
        
        client_ip = _get_client_ip(request)
        
        current_time = time.time()
        if client_ip in self.request_records:
            count, start_time = self.request_records[client_ip]
            
            if current_time - start_time > 60:
                self.request_records[client_ip] = (1, current_time)
            else:
                count += 1
                if count > self.requests_per_minute:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Too many requests",
                    )
                else:
                    self.request_records[client_ip] = (count, start_time)
        else:
            self.request_records[client_ip] = (1, current_time)
        
        self._cleanup_old_records(current_time)
        
        return await call_next(request)
    
    def _cleanup_old_records(self, current_time: float):
        """Remove records older than 5 minutes to save memory."""
        ips_to_remove = [
            ip for ip, (_, start_time) in self.request_records.items()
            if current_time - start_time > 300
        ]
        for ip in ips_to_remove:
            del self.request_records[ip]


# --- Per-user endpoint rate limiter (for use as a FastAPI dependency) ---

class _UserRateLimiter:
    """Simple per-user sliding window rate limiter for individual endpoints."""

    def __init__(self, max_requests: int = 10, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._records: Dict[str, Tuple[int, float]] = {}

    def check(self, user_key: str) -> None:
        now = time.time()
        if user_key in self._records:
            count, window_start = self._records[user_key]
            if now - window_start > self.window_seconds:
                self._records[user_key] = (1, now)
            else:
                count += 1
                if count > self.max_requests:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Too many requests — try again shortly",
                    )
                self._records[user_key] = (count, window_start)
        else:
            self._records[user_key] = (1, now)


# Shared instance: 10 profile updates per minute per user
profile_rate_limiter = _UserRateLimiter(max_requests=10, window_seconds=60)