"""
HTTP Utilities for Pooled Client Usage

This module provides utility functions to simplify the use of pooled HTTP clients
throughout the application, eliminating one-shot client usage patterns.
"""

import asyncio
import logging
from typing import Optional, Dict, Any, Union
from contextlib import asynccontextmanager

from app.core.http_client_manager import get_http_client_manager, OptimizedHTTPXClient

logger = logging.getLogger(__name__)


class PooledHTTPClient:
    """
    Utility class for easy access to pooled HTTP clients.
    
    This class provides a simple interface for making HTTP requests using
    the pooled HTTP client manager, eliminating the need for one-shot clients.
    """
    
    def __init__(self, provider: str = "default"):
        self.provider = provider
        self._client: Optional[OptimizedHTTPXClient] = None
        self._initialized = False
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.start()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        # Note: We don't stop the client here as it's managed by the pool
        pass
    
    async def start(self):
        """Initialize the HTTP client."""
        if self._initialized:
            return
        
        http_manager = get_http_client_manager()
        self._client = http_manager.get_client(self.provider)
        await self._client.start()
        self._initialized = True
    
    async def get(self, url: str, **kwargs) -> Any:
        """Make GET request."""
        await self.start()
        return await self._client.get(url, **kwargs)
    
    async def post(self, url: str, **kwargs) -> Any:
        """Make POST request."""
        await self.start()
        return await self._client.post(url, **kwargs)
    
    async def put(self, url: str, **kwargs) -> Any:
        """Make PUT request."""
        await self.start()
        return await self._client.put(url, **kwargs)
    
    async def delete(self, url: str, **kwargs) -> Any:
        """Make DELETE request."""
        await self.start()
        return await self._client.delete(url, **kwargs)
    
    async def request(self, method: str, url: str, **kwargs) -> Any:
        """Make request with specified method."""
        await self.start()
        return await self._client.request(method, url, **kwargs)
    
    @property
    def client(self) -> OptimizedHTTPXClient:
        """Get the underlying HTTP client."""
        if not self._client:
            raise RuntimeError("Client not initialized. Call start() first.")
        return self._client


@asynccontextmanager
async def pooled_http_client(provider: str = "default"):
    """
    Context manager for pooled HTTP client usage.
    
    Usage:
        async with pooled_http_client("openai") as client:
            response = await client.post(url, json=data)
    """
    client = PooledHTTPClient(provider)
    try:
        yield client
    finally:
        pass  # Client is managed by the pool


async def get_pooled_client(provider: str = "default") -> PooledHTTPClient:
    """
    Get a pooled HTTP client for a specific provider.
    
    Args:
        provider: The provider name (e.g., "openai", "groq", "anthropic")
        
    Returns:
        PooledHTTPClient: Initialized pooled client
    """
    client = PooledHTTPClient(provider)
    await client.start()
    return client


# Convenience functions for common HTTP operations
async def pooled_get(url: str, provider: str = "default", **kwargs) -> Any:
    """Make GET request using pooled client."""
    async with pooled_http_client(provider) as client:
        return await client.get(url, **kwargs)


async def pooled_post(url: str, provider: str = "default", **kwargs) -> Any:
    """Make POST request using pooled client."""
    async with pooled_http_client(provider) as client:
        return await client.post(url, **kwargs)


async def pooled_put(url: str, provider: str = "default", **kwargs) -> Any:
    """Make PUT request using pooled client."""
    async with pooled_http_client(provider) as client:
        return await client.put(url, **kwargs)


async def pooled_delete(url: str, provider: str = "default", **kwargs) -> Any:
    """Make DELETE request using pooled client."""
    async with pooled_http_client(provider) as client:
        return await client.delete(url, **kwargs)


# Migration helper for replacing one-shot httpx clients
class HTTPXClientReplacement:
    """
    Drop-in replacement for httpx.AsyncClient that uses pooled connections.
    
    This class provides a compatibility layer for existing code that uses
    httpx.AsyncClient directly, redirecting to the pooled client manager.
    """
    
    def __init__(self, provider: str = "default", **kwargs):
        self.provider = provider
        self._client: Optional[PooledHTTPClient] = None
        # Note: We ignore httpx-specific kwargs since the pool manages configuration
    
    async def __aenter__(self):
        """Async context manager entry."""
        self._client = await get_pooled_client(self.provider)
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        # Client is managed by the pool, so we don't need to close it
        pass
    
    async def get(self, url: str, **kwargs) -> Any:
        """Make GET request."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return await self._client.get(url, **kwargs)
    
    async def post(self, url: str, **kwargs) -> Any:
        """Make POST request."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return await self._client.post(url, **kwargs)
    
    async def put(self, url: str, **kwargs) -> Any:
        """Make PUT request."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return await self._client.put(url, **kwargs)
    
    async def delete(self, url: str, **kwargs) -> Any:
        """Make DELETE request."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return await self._client.delete(url, **kwargs)
    
    async def request(self, method: str, url: str, **kwargs) -> Any:
        """Make request with specified method."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return await self._client.request(method, url, **kwargs)
    
    def stream(self, method: str, url: str, **kwargs):
        """Stream request - delegates to underlying client."""
        if not self._client:
            raise RuntimeError("Client not initialized. Use as context manager.")
        return self._client.client.client.stream(method, url, **kwargs)


# Factory function for creating pooled HTTP clients with provider auto-detection
def create_pooled_client(url: str = None, provider: str = None) -> PooledHTTPClient:
    """
    Create a pooled HTTP client with automatic provider detection.
    
    Args:
        url: Optional URL to detect provider from
        provider: Explicit provider name
        
    Returns:
        PooledHTTPClient: Configured pooled client
    """
    if provider:
        return PooledHTTPClient(provider)
    
    # Auto-detect provider from URL
    if url:
        if "openai.com" in url:
            return PooledHTTPClient("openai")
        elif "groq.com" in url:
            return PooledHTTPClient("groq")
        elif "anthropic.com" in url:
            return PooledHTTPClient("anthropic")
        elif "googleapis.com" in url:
            return PooledHTTPClient("google")
        elif "azure.com" in url:
            return PooledHTTPClient("azure")
    
    # Default to generic client
    return PooledHTTPClient("default")


# Migration utility for finding and replacing one-shot clients
def audit_one_shot_clients():
    """
    Utility function to help identify remaining one-shot HTTP clients.
    
    This function can be used during development to find code that still
    uses one-shot httpx.AsyncClient instances.
    """
    import ast
    import os
    from pathlib import Path
    
    one_shot_patterns = [
        "httpx.AsyncClient(",
        "httpx.Client(",
        "async with httpx.AsyncClient",
        "async with httpx.Client"
    ]
    
    app_root = Path(__file__).parent.parent
    python_files = list(app_root.rglob("*.py"))
    
    findings = []
    
    for file_path in python_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            for line_num, line in enumerate(content.splitlines(), 1):
                for pattern in one_shot_patterns:
                    if pattern in line and "# POOLED" not in line:
                        findings.append({
                            'file': str(file_path),
                            'line': line_num,
                            'content': line.strip(),
                            'pattern': pattern
                        })
        except Exception as e:
            logger.warning(f"Could not analyze file {file_path}: {e}")
    
    return findings


# Example usage patterns for documentation
"""
# OLD: One-shot client usage
async with httpx.AsyncClient(timeout=60.0) as client:
    response = await client.post(url, json=data)

# NEW: Pooled client usage
async with pooled_http_client("openai") as client:
    response = await client.post(url, json=data)

# OR: Direct utility function
response = await pooled_post(url, provider="openai", json=data)

# OR: Long-lived client
client = await get_pooled_client("openai")
response = await client.post(url, json=data)
"""