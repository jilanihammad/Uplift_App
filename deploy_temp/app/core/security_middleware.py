# app/core/security_middleware.py

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
import time

class SecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Start time for performance monitoring
        start_time = time.time()
        
        # Process the request and get the response
        response = await call_next(request)
        
        # Add security headers
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; connect-src 'self'"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        
        # Add performance monitoring header
        process_time = time.time() - start_time
        response.headers["X-Process-Time"] = str(process_time)
        
        return response