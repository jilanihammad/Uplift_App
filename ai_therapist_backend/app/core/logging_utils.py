"""
Logging utilities for security, privacy, and debugging best practices.

This module provides helper functions for:
- Redacting sensitive headers (cookies, auth tokens)
- Scrubbing PII from user text
- Managing correlation IDs for request tracing
- Monotonic timing for accurate latency measurements
"""

import time
import uuid
from typing import Dict, Any, Optional


# Safe headers that can be logged without redaction
SAFE_HEADERS = {
    "x-request-id",
    "date",
    "content-type",
    "content-length",
    "user-agent",
    "accept",
    "accept-encoding"
}


def redact_headers(headers: Dict[str, Any]) -> Dict[str, Any]:
    """
    Redact sensitive headers from logging output.

    Only whitelisted headers (SAFE_HEADERS) are kept in full.
    All other headers (especially cookies, authorization) are redacted.

    Args:
        headers: Dictionary of HTTP headers

    Returns:
        Dictionary with sensitive headers redacted

    Example:
        >>> headers = {"cookie": "session=abc123", "x-request-id": "123"}
        >>> redact_headers(headers)
        {"cookie": "<redacted>", "x-request-id": "123"}
    """
    if not headers:
        return {}

    return {
        k: (headers[k] if k.lower() in SAFE_HEADERS else "<redacted>")
        for k in headers
    }


def preview_text(text: str, max_length: int = 60) -> str:
    """
    Create a safe preview of user text for logging.

    Truncates long text to prevent logging full PII/user messages.
    Use this for INFO-level logs. Full text should only be at DEBUG level.

    Args:
        text: User-provided text that may contain PII
        max_length: Maximum characters to include in preview

    Returns:
        Truncated text with ellipsis if needed

    Example:
        >>> preview_text("This is a very long user message that contains sensitive info", 30)
        "This is a very long user mes…"
    """
    if not text:
        return ""

    if len(text) <= max_length:
        return text

    return text[:max_length] + "…"


def generate_request_id() -> str:
    """
    Generate a unique correlation ID for request tracing.

    Returns:
        UUID string suitable for x-request-id header

    Example:
        >>> req_id = generate_request_id()
        >>> len(req_id)
        36
    """
    return str(uuid.uuid4())


def extract_request_id(headers: Optional[Dict[str, Any]] = None,
                       fallback_id: Optional[str] = None) -> str:
    """
    Extract or generate a request correlation ID.

    Tries to find x-request-id in headers, falls back to provided ID,
    or generates a new one.

    Args:
        headers: HTTP headers dictionary
        fallback_id: Optional ID to use if not found in headers

    Returns:
        Request correlation ID

    Example:
        >>> headers = {"x-request-id": "abc-123"}
        >>> extract_request_id(headers)
        "abc-123"
    """
    if headers:
        # Try various common header names
        for key in ["x-request-id", "X-Request-ID", "request-id", "Request-ID"]:
            if key in headers:
                return headers[key]

    if fallback_id:
        return fallback_id

    return generate_request_id()


class LatencyTimer:
    """
    Monotonic timer for accurate latency measurements.

    Uses time.perf_counter() to avoid clock/DST issues.

    Example:
        >>> timer = LatencyTimer()
        >>> # ... do some work ...
        >>> elapsed_ms = timer.elapsed_ms()
        >>> print(f"Operation took {elapsed_ms}ms")
    """

    def __init__(self):
        """Start the timer."""
        self.start_time = time.perf_counter()
        self._checkpoints = {}

    def elapsed_ms(self) -> float:
        """
        Get elapsed time in milliseconds since timer start.

        Returns:
            Elapsed time in milliseconds (rounded to 1 decimal place)
        """
        elapsed = time.perf_counter() - self.start_time
        return round(elapsed * 1000, 1)

    def checkpoint(self, name: str) -> float:
        """
        Record a named checkpoint and return elapsed time.

        Args:
            name: Name for this checkpoint (e.g., "first_chunk", "complete")

        Returns:
            Elapsed milliseconds since timer start
        """
        elapsed = self.elapsed_ms()
        self._checkpoints[name] = elapsed
        return elapsed

    def get_checkpoint(self, name: str) -> Optional[float]:
        """
        Get the elapsed time for a previously recorded checkpoint.

        Args:
            name: Checkpoint name

        Returns:
            Elapsed milliseconds, or None if checkpoint doesn't exist
        """
        return self._checkpoints.get(name)


def create_log_context(req_id: str, **kwargs) -> Dict[str, Any]:
    """
    Create a structured logging context with correlation ID.

    All log entries for the same request should include the same req_id
    for easy filtering and tracing.

    Args:
        req_id: Request correlation ID
        **kwargs: Additional context fields

    Returns:
        Dictionary suitable for logger.info(..., extra=context)

    Example:
        >>> ctx = create_log_context("req-123", user_id=456, action="tts")
        >>> logger.info("TTS started", extra=ctx)
    """
    context = {"req_id": req_id}
    context.update(kwargs)
    return context
