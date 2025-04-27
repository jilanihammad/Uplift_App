# app/core/rate_limiter.py

from fastapi import Request, Response, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
import time
from typing import Dict, Tuple

class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests_per_minute: int = 60):
        super().__init__(app)
        self.requests_per_minute = requests_per_minute
        self.request_records: Dict[str, Tuple[int, float]] = {}  # IP: (count, start_time)
    
    async def dispatch(self, request: Request, call_next):
        # Get client IP
        client_ip = request.client.host if request.client else "unknown"
        
        # Check if this IP is already being tracked
        current_time = time.time()
        if client_ip in self.request_records:
            count, start_time = self.request_records[client_ip]
            
            # If 1 minute has passed, reset the counter
            if current_time - start_time > 60:
                self.request_records[client_ip] = (1, current_time)
            else:
                # Increment request count
                count += 1
                if count > self.requests_per_minute:
                    # Too many requests
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Too many requests",
                    )
                else:
                    self.request_records[client_ip] = (count, start_time)
        else:
            # First request from this IP
            self.request_records[client_ip] = (1, current_time)
        
        # Clean up old records (optional, for memory management)
        self._cleanup_old_records(current_time)
        
        # Process the request
        return await call_next(request)
    
    def _cleanup_old_records(self, current_time: float):
        """Remove records older than 5 minutes to save memory"""
        ips_to_remove = []
        for ip, (_, start_time) in self.request_records.items():
            if current_time - start_time > 300:  # 5 minutes
                ips_to_remove.append(ip)
        
        for ip in ips_to_remove:
            del self.request_records[ip]