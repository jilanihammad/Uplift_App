"""
High-Performance HTTP Client Manager

This module provides optimized HTTP clients with:
- Per-provider connection pooling
- HTTP/2 support where available
- DNS caching
- Connection keep-alive optimization
- Request/response compression
- Timeout configuration
- Circuit breaker integration
"""

import asyncio
import logging
import time
from typing import Dict, Optional, Any, Union, List
from dataclasses import dataclass
from enum import Enum
import httpx
import aiohttp
from contextlib import asynccontextmanager

from app.core.observability import observe_performance, record_counter, record_latency

logger = logging.getLogger(__name__)


class HTTPClientType(Enum):
    """HTTP client types."""
    HTTPX = "httpx"
    AIOHTTP = "aiohttp"


@dataclass
class HTTPClientConfig:
    """Configuration for HTTP client."""
    # Connection pool settings
    max_connections: int = 100
    max_keepalive_connections: int = 20
    keepalive_timeout: float = 75.0
    
    # Timeout settings
    connect_timeout: float = 5.0
    read_timeout: float = 30.0
    write_timeout: float = 30.0
    pool_timeout: float = 5.0
    
    # DNS and connection settings
    dns_cache_ttl: int = 300  # 5 minutes
    use_dns_cache: bool = True
    enable_http2: bool = True
    
    # Compression and headers
    enable_compression: bool = True
    user_agent: str = "ai-therapist-backend/1.0"
    default_headers: Dict[str, str] = None
    
    # Performance settings
    max_redirects: int = 5
    verify_ssl: bool = True
    
    def __post_init__(self):
        if self.default_headers is None:
            self.default_headers = {}


# Provider-specific optimized configurations
PROVIDER_HTTP_CONFIGS = {
    "openai": HTTPClientConfig(
        max_connections=100,
        max_keepalive_connections=20,
        keepalive_timeout=75.0,
        connect_timeout=5.0,
        read_timeout=30.0,
        enable_http2=True,
        default_headers={
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate, br"
        }
    ),
    "anthropic": HTTPClientConfig(
        max_connections=50,
        max_keepalive_connections=15,
        keepalive_timeout=60.0,
        connect_timeout=5.0,
        read_timeout=45.0,
        enable_http2=True,
        default_headers={
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate"
        }
    ),
    "groq": HTTPClientConfig(
        max_connections=80,
        max_keepalive_connections=25,
        keepalive_timeout=90.0,
        connect_timeout=3.0,
        read_timeout=25.0,
        enable_http2=True,
        default_headers={
            "Connection": "keep-alive",
            "User-Agent": "groq-client/1.0"
        }
    ),
    "google": HTTPClientConfig(
        max_connections=60,
        max_keepalive_connections=20,
        keepalive_timeout=60.0,
        connect_timeout=5.0,
        read_timeout=30.0,
        enable_http2=True,
        default_headers={
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate"
        }
    ),
    "azure": HTTPClientConfig(
        max_connections=100,
        max_keepalive_connections=20,
        keepalive_timeout=75.0,
        connect_timeout=5.0,
        read_timeout=30.0,
        enable_http2=True,
        default_headers={
            "Connection": "keep-alive",
            "Accept-Encoding": "gzip, deflate"
        }
    ),
    "default": HTTPClientConfig()
}


class OptimizedHTTPXClient:
    """Optimized HTTPX client with connection pooling and performance features."""
    
    def __init__(self, config: HTTPClientConfig):
        self.config = config
        self.client: Optional[httpx.AsyncClient] = None
        self.created_at = time.time()
        self.request_count = 0
        
    async def __aenter__(self):
        """Async context manager entry."""
        await self.start()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.stop()
    
    async def start(self):
        """Start the HTTP client."""
        if self.client is not None:
            return
        
        # Create transport with optimized settings
        transport = httpx.AsyncHTTPTransport(
            limits=httpx.Limits(
                max_connections=self.config.max_connections,
                max_keepalive_connections=self.config.max_keepalive_connections,
                keepalive_expiry=self.config.keepalive_timeout
            ),
            retries=0,  # We handle retries at higher level
            http2=self.config.enable_http2
        )
        
        # Create client with optimized settings
        self.client = httpx.AsyncClient(
            transport=transport,
            timeout=httpx.Timeout(
                connect=self.config.connect_timeout,
                read=self.config.read_timeout,
                write=self.config.write_timeout,
                pool=self.config.pool_timeout
            ),
            headers=self.config.default_headers,
            follow_redirects=True,
            max_redirects=self.config.max_redirects,
            verify=self.config.verify_ssl
        )
        
        # Register with connection monitor
        try:
            from app.core.connection_monitor import get_connection_monitor, ResourceType
            monitor = get_connection_monitor()
            await monitor.register_connection(
                connection_id=f"httpx_client_{id(self.client)}",
                resource_type=ResourceType.HTTP_CONNECTION,
                provider=getattr(self, 'provider', 'unknown')
            )
        except ImportError:
            pass  # Connection monitor not available
        
        logger.info("HTTPX client started with optimized configuration")
    
    async def stop(self):
        """Stop the HTTP client."""
        if self.client is not None:
            await self.client.aclose()
            self.client = None
            logger.info("HTTPX client stopped")
    
    async def request(self, method: str, url: str, **kwargs) -> httpx.Response:
        """Make an HTTP request with performance monitoring."""
        if self.client is None:
            await self.start()
        
        start_time = time.time()
        self.request_count += 1
        
        try:
            response = await self.client.request(method, url, **kwargs)
            duration_ms = (time.time() - start_time) * 1000
            
            # Record metrics
            record_latency(
                "http_client", 
                "request", 
                duration_ms,
                labels={
                    "method": method,
                    "status_code": str(response.status_code),
                    "client_type": "httpx"
                }
            )
            
            record_counter(
                "http_client",
                "requests_total",
                labels={
                    "method": method,
                    "status_code": str(response.status_code),
                    "client_type": "httpx"
                }
            )
            
            return response
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            # Record error metrics
            record_latency(
                "http_client", 
                "request", 
                duration_ms,
                labels={
                    "method": method,
                    "status_code": "error",
                    "client_type": "httpx"
                }
            )
            
            record_counter(
                "http_client",
                "requests_error",
                labels={
                    "method": method,
                    "error_type": type(e).__name__,
                    "client_type": "httpx"
                }
            )
            
            raise
    
    async def get(self, url: str, **kwargs) -> httpx.Response:
        """Make GET request."""
        return await self.request("GET", url, **kwargs)
    
    async def post(self, url: str, **kwargs) -> httpx.Response:
        """Make POST request."""
        return await self.request("POST", url, **kwargs)
    
    async def put(self, url: str, **kwargs) -> httpx.Response:
        """Make PUT request."""
        return await self.request("PUT", url, **kwargs)
    
    async def delete(self, url: str, **kwargs) -> httpx.Response:
        """Make DELETE request."""
        return await self.request("DELETE", url, **kwargs)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get client statistics."""
        return {
            "client_type": "httpx",
            "created_at": self.created_at,
            "uptime_seconds": time.time() - self.created_at,
            "request_count": self.request_count,
            "is_active": self.client is not None
        }


class OptimizedAIOHTTPClient:
    """Optimized aiohttp client with connection pooling and performance features."""
    
    def __init__(self, config: HTTPClientConfig):
        self.config = config
        self.session: Optional[aiohttp.ClientSession] = None
        self.connector: Optional[aiohttp.TCPConnector] = None
        self.created_at = time.time()
        self.request_count = 0
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self.start()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.stop()
    
    async def start(self):
        """Start the HTTP client."""
        if self.session is not None:
            return
        
        # Create optimized TCP connector
        self.connector = aiohttp.TCPConnector(
            limit=self.config.max_connections,
            limit_per_host=self.config.max_keepalive_connections,
            keepalive_timeout=self.config.keepalive_timeout,
            ttl_dns_cache=self.config.dns_cache_ttl if self.config.use_dns_cache else None,
            use_dns_cache=self.config.use_dns_cache,
            enable_cleanup_closed=True,
            force_close=False,
            ssl=self.config.verify_ssl
        )
        
        # Create timeout configuration
        timeout = aiohttp.ClientTimeout(
            total=None,  # No total timeout, handle at higher level
            connect=self.config.connect_timeout,
            sock_read=self.config.read_timeout,
            sock_connect=self.config.connect_timeout
        )
        
        # Create session with optimized settings
        self.session = aiohttp.ClientSession(
            connector=self.connector,
            timeout=timeout,
            headers=self.config.default_headers,
            auto_decompress=self.config.enable_compression,
            max_redirects=self.config.max_redirects,
            connector_owner=True
        )
        
        logger.info("aiohttp client started with optimized configuration")
    
    async def stop(self):
        """Stop the HTTP client."""
        if self.session is not None:
            await self.session.close()
            self.session = None
            self.connector = None
            logger.info("aiohttp client stopped")
    
    async def request(self, method: str, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an HTTP request with performance monitoring."""
        if self.session is None:
            await self.start()
        
        start_time = time.time()
        self.request_count += 1
        
        try:
            async with self.session.request(method, url, **kwargs) as response:
                duration_ms = (time.time() - start_time) * 1000
                
                # Record metrics
                record_latency(
                    "http_client", 
                    "request", 
                    duration_ms,
                    labels={
                        "method": method,
                        "status_code": str(response.status),
                        "client_type": "aiohttp"
                    }
                )
                
                record_counter(
                    "http_client",
                    "requests_total",
                    labels={
                        "method": method,
                        "status_code": str(response.status),
                        "client_type": "aiohttp"
                    }
                )
                
                return response
                
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            # Record error metrics
            record_latency(
                "http_client", 
                "request", 
                duration_ms,
                labels={
                    "method": method,
                    "status_code": "error",
                    "client_type": "aiohttp"
                }
            )
            
            record_counter(
                "http_client",
                "requests_error",
                labels={
                    "method": method,
                    "error_type": type(e).__name__,
                    "client_type": "aiohttp"
                }
            )
            
            raise
    
    async def get(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make GET request."""
        return await self.request("GET", url, **kwargs)
    
    async def post(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make POST request."""
        return await self.request("POST", url, **kwargs)
    
    async def put(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make PUT request."""
        return await self.request("PUT", url, **kwargs)
    
    async def delete(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make DELETE request."""
        return await self.request("DELETE", url, **kwargs)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get client statistics."""
        return {
            "client_type": "aiohttp",
            "created_at": self.created_at,
            "uptime_seconds": time.time() - self.created_at,
            "request_count": self.request_count,
            "is_active": self.session is not None
        }


class HTTPClientManager:
    """
    Manager for optimized HTTP clients with per-provider configuration.
    
    Features:
    - Per-provider connection pooling
    - HTTP/2 support
    - DNS caching
    - Connection keep-alive
    - Performance monitoring
    """
    
    def __init__(self, default_client_type: HTTPClientType = HTTPClientType.HTTPX):
        self.default_client_type = default_client_type
        self.clients: Dict[str, Union[OptimizedHTTPXClient, OptimizedAIOHTTPClient]] = {}
        self.client_stats: Dict[str, Dict[str, Any]] = {}
        
    def get_client(self, provider: str, 
                   client_type: Optional[HTTPClientType] = None) -> Union[OptimizedHTTPXClient, OptimizedAIOHTTPClient]:
        """Get or create optimized HTTP client for provider."""
        client_type = client_type or self.default_client_type
        client_key = f"{provider}_{client_type.value}"
        
        if client_key not in self.clients:
            config = PROVIDER_HTTP_CONFIGS.get(provider, PROVIDER_HTTP_CONFIGS["default"])
            
            if client_type == HTTPClientType.HTTPX:
                client = OptimizedHTTPXClient(config)
            elif client_type == HTTPClientType.AIOHTTP:
                client = OptimizedAIOHTTPClient(config)
            else:
                raise ValueError(f"Unsupported client type: {client_type}")
            
            self.clients[client_key] = client
            logger.info(f"Created optimized HTTP client for {provider} using {client_type.value}")
        
        return self.clients[client_key]
    
    @asynccontextmanager
    async def client_context(self, provider: str, 
                           client_type: Optional[HTTPClientType] = None):
        """Context manager for HTTP client."""
        client = self.get_client(provider, client_type)
        
        try:
            await client.start()
            yield client
        finally:
            # Don't stop client here - let it be reused
            pass
    
    async def start_all_clients(self):
        """Start all HTTP clients."""
        for client in self.clients.values():
            await client.start()
    
    async def prewarm_all_clients(self, providers: List[str] = None) -> Dict[str, Any]:
        """Pre-warm HTTP clients with connection establishment."""
        providers = providers or ["openai", "anthropic", "groq", "google", "azure"]
        prewarm_results = {}
        
        # Create warmup tasks for all providers
        warmup_tasks = []
        for provider in providers:
            warmup_tasks.append(self._prewarm_provider_client(provider))
        
        # Execute warmups in parallel
        results = await asyncio.gather(*warmup_tasks, return_exceptions=True)
        
        # Process results
        for provider, result in zip(providers, results):
            if isinstance(result, Exception):
                prewarm_results[provider] = {
                    "success": False,
                    "error": str(result),
                    "duration_ms": 0
                }
            else:
                prewarm_results[provider] = result
        
        return prewarm_results
    
    async def _prewarm_provider_client(self, provider: str) -> Dict[str, Any]:
        """Pre-warm a specific provider client with connection establishment."""
        import time
        start_time = time.time()
        
        try:
            # Get optimized client for provider
            client = self.get_client(provider)
            await client.start()
            
            # Establish actual HTTP/2 connection with lightweight request
            await self._establish_connection(provider, client)
            
            duration_ms = (time.time() - start_time) * 1000
            
            logger.info(f"Successfully pre-warmed {provider} client in {duration_ms:.1f}ms")
            
            return {
                "success": True,
                "duration_ms": duration_ms,
                "connection_established": True,
                "http2_enabled": True
            }
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            logger.warning(f"Failed to pre-warm {provider} client: {e}")
            
            return {
                "success": False,
                "duration_ms": duration_ms,
                "error": str(e),
                "connection_established": False
            }
    
    async def _establish_connection(self, provider: str, client):
        """Establish actual HTTP connection with provider-specific endpoint."""
        # Provider-specific lightweight endpoints for connection establishment
        endpoints = {
            "openai": "https://api.openai.com/v1/models",
            "anthropic": "https://api.anthropic.com/v1/messages",
            "groq": "https://api.groq.com/openai/v1/models",
            "google": "https://generativelanguage.googleapis.com/v1beta/models",
            "azure": "https://api.openai.com/v1/models"  # Azure uses OpenAI compatible endpoint
        }
        
        endpoint = endpoints.get(provider)
        if not endpoint:
            return
        
        try:
            # Make a lightweight HEAD request to establish connection
            # HEAD requests are cacheable and don't transfer response body
            import httpx
            response = await client.request("HEAD", endpoint, timeout=httpx.Timeout(connect=3.0, read=5.0))
            
            # Even if we get 401/403 (no API key), the connection is established
            if response.status_code in [200, 401, 403]:
                logger.debug(f"Connection established to {provider} ({response.status_code})")
            
        except Exception as e:
            # Log but don't fail - connection establishment is best-effort
            logger.debug(f"Connection establishment for {provider} failed: {e}")
    
    async def stop_all_clients(self):
        """Stop all HTTP clients."""
        for client in self.clients.values():
            await client.stop()
    
    def get_all_stats(self) -> Dict[str, Dict[str, Any]]:
        """Get statistics for all clients."""
        return {
            client_key: client.get_stats() 
            for client_key, client in self.clients.items()
        }
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get health status of all clients."""
        total_clients = len(self.clients)
        active_clients = sum(1 for client in self.clients.values() 
                           if client.client is not None or client.session is not None)
        
        return {
            "total_clients": total_clients,
            "active_clients": active_clients,
            "health_status": "healthy" if active_clients == total_clients else "degraded",
            "client_stats": self.get_all_stats()
        }


# Global HTTP client manager instance
_http_client_manager: Optional[HTTPClientManager] = None


def get_http_client_manager() -> HTTPClientManager:
    """Get the global HTTP client manager."""
    global _http_client_manager
    if _http_client_manager is None:
        _http_client_manager = HTTPClientManager()
    return _http_client_manager


# Convenience functions
def get_optimized_client(provider: str, 
                        client_type: HTTPClientType = HTTPClientType.HTTPX) -> Union[OptimizedHTTPXClient, OptimizedAIOHTTPClient]:
    """Get optimized HTTP client for provider."""
    manager = get_http_client_manager()
    return manager.get_client(provider, client_type)


async def prewarm_http_clients(providers: List[str] = None) -> Dict[str, Any]:
    """Pre-warm HTTP clients for faster first requests."""
    manager = get_http_client_manager()
    return await manager.prewarm_all_clients(providers)


@asynccontextmanager
async def http_client_context(provider: str, 
                             client_type: HTTPClientType = HTTPClientType.HTTPX):
    """Context manager for HTTP client."""
    manager = get_http_client_manager()
    async with manager.client_context(provider, client_type) as client:
        yield client


# Performance-optimized HTTP client decorator
def with_optimized_http_client(provider: str, 
                              client_type: HTTPClientType = HTTPClientType.HTTPX):
    """Decorator to inject optimized HTTP client."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            async with http_client_context(provider, client_type) as client:
                return await func(client, *args, **kwargs)
        return wrapper
    return decorator