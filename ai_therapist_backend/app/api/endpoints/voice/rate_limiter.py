"""
Text input rate limiter for WebSocket connections.

Implements Step 12: Text Input Rate Limiting (30 requests/minute per user)
"""
import asyncio
import time
import logging
from typing import Optional, Dict, Any, List

logger = logging.getLogger(__name__)


class TextInputRateLimiter:
    """
    Rate limiter for text input to prevent abuse
    Implements Step 12: Text Input Rate Limiting (30 requests/minute per user)
    """

    def __init__(self):
        # Track requests per user ID
        self.user_requests: Dict[str, List[float]] = {}
        # Track requests per IP (fallback)
        self.ip_requests: Dict[str, List[float]] = {}
        # Lock for thread-safe operations
        self._lock = asyncio.Lock()
        # Rate limit configuration
        self.requests_per_minute = 30  # Step 12: 30 requests per minute per user

    async def is_allowed(self, user_id: str, client_ip: Optional[str] = None) -> Dict[str, Any]:
        """
        Check if user is allowed to make a request based on rate limiting

        Args:
            user_id: User identifier
            client_ip: Client IP address (fallback if user_id is None)

        Returns:
            Dict with allowed status, request count, and reset time
        """
        async with self._lock:
            current_time = time.time()

            # Use user_id or fall back to IP
            key = user_id if user_id else client_ip
            if not key:
                return {
                    "allowed": False,
                    "user_request_count": 0,
                    "reason": "No identifier provided",
                    "reset_time": current_time + 60
                }

            # Choose the appropriate tracking dict
            requests_dict = self.user_requests if user_id else self.ip_requests

            # Clean up old requests (older than 1 minute)
            if key in requests_dict:
                cutoff_time = current_time - 60
                requests_dict[key] = [req_time for req_time in requests_dict[key] if req_time > cutoff_time]
            else:
                requests_dict[key] = []

            # Add current request
            requests_dict[key].append(current_time)

            current_count = len(requests_dict[key])

            # Check if limit exceeded
            allowed = current_count <= self.requests_per_minute

            # Calculate reset time (when oldest request will be outside the window)
            reset_time = current_time + 60
            if requests_dict[key]:
                oldest_request = min(requests_dict[key])
                reset_time = oldest_request + 60

            return {
                "allowed": allowed,
                "user_request_count": current_count,
                "requests_per_minute": self.requests_per_minute,
                "reset_time": reset_time,
                "window_start": current_time - 60
            }

    async def get_user_status(self, user_id: str) -> Dict[str, Any]:
        """
        Get current rate limit status for a user

        Args:
            user_id: User identifier

        Returns:
            Dict with user rate limit status
        """
        async with self._lock:
            current_time = time.time()

            # Clean up old requests
            if user_id in self.user_requests:
                cutoff_time = current_time - 60
                self.user_requests[user_id] = [req_time for req_time in self.user_requests[user_id] if req_time > cutoff_time]
                current_count = len(self.user_requests[user_id])
            else:
                current_count = 0

            return {
                "requests_made": current_count,
                "limit_per_minute": self.requests_per_minute,
                "remaining": max(0, self.requests_per_minute - current_count),
                "reset_time": current_time + 60
            }


# Global instance
text_rate_limiter = TextInputRateLimiter()
