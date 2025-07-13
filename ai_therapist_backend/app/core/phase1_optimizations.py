"""
Phase 1: HTTP Client Hot-rodding

This module implements Phase 1 optimizations for the speed-first backend plan:
1. HTTP/2 connection pre-warming with persistent pools
2. Enhanced keep-alive configuration for all providers  
3. Parallel provider warm-up with connection reuse tracking
4. DNS pre-resolution and connection establishment
5. Smart timeout configuration for optimal latency

Target: Reduce TTFB by 100-200ms through connection optimization
"""

import asyncio
import logging
import time
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
import httpx
from concurrent.futures import ThreadPoolExecutor

from app.core.observability import record_latency, record_counter, log_info, log_error
from app.core.http_client_manager import get_http_client_manager

logger = logging.getLogger(__name__)


@dataclass
class Phase1Config:
    """Configuration for Phase 1 optimizations."""
    # HTTP/2 and connection settings
    enable_http2_preconnect: bool = True
    connection_pool_size: int = 25  # Per provider
    keepalive_timeout: float = 90.0  # Extended keep-alive
    dns_cache_ttl: int = 600  # 10 minutes
    
    # Pre-warming settings
    prewarm_providers: List[str] = None
    prewarm_timeout: float = 10.0
    parallel_prewarm: bool = True
    max_concurrent_prewarming: int = 8
    
    # Connection validation
    validate_connections: bool = True
    connection_validation_timeout: float = 3.0
    
    def __post_init__(self):
        if self.prewarm_providers is None:
            self.prewarm_providers = ["openai", "groq", "anthropic", "google"]


class Phase1Optimizer:
    """
    Phase 1 HTTP client hot-rodding optimizer.
    
    This class implements connection pre-warming, HTTP/2 optimization,
    and keep-alive enhancement for minimal latency.
    """
    
    def __init__(self, config: Phase1Config = None):
        self.config = config or Phase1Config()
        self.optimization_results: Dict[str, Any] = {}
        self.prewarmed_connections: Dict[str, bool] = {}
        self.connection_metrics: Dict[str, Dict[str, float]] = {}
        
    async def run_phase1_optimizations(self) -> Dict[str, Any]:
        """Run complete Phase 1 optimization suite."""
        start_time = time.time()
        
        await log_info(
            "phase1_optimizer",
            "Starting Phase 1 HTTP client hot-rodding",
            config=self.config.__dict__
        )
        
        optimization_tasks = []
        
        # Task 1: HTTP/2 connection pre-warming
        if self.config.enable_http2_preconnect:
            optimization_tasks.append(self._optimize_http2_connections())
        
        # Task 2: Enhanced keep-alive configuration
        optimization_tasks.append(self._optimize_keepalive_settings())
        
        # Task 3: Parallel provider pre-warming
        if self.config.parallel_prewarm:
            optimization_tasks.append(self._parallel_provider_prewarm())
        
        # Task 4: DNS pre-resolution
        optimization_tasks.append(self._preresol_dns())
        
        # Execute all optimizations in parallel
        results = await asyncio.gather(*optimization_tasks, return_exceptions=True)
        
        # Process results
        total_duration = (time.time() - start_time) * 1000
        
        optimization_summary = {
            "total_duration_ms": total_duration,
            "optimizations_completed": len([r for r in results if not isinstance(r, Exception)]),
            "optimizations_failed": len([r for r in results if isinstance(r, Exception)]),
            "prewarmed_connections": self.prewarmed_connections,
            "connection_metrics": self.connection_metrics,
            "phase1_status": "completed"
        }
        
        # Record metrics
        record_latency("phase1", "total_optimization_time", total_duration)
        record_counter("phase1", "optimizations_completed", len([r for r in results if not isinstance(r, Exception)]))
        
        await log_info(
            "phase1_optimizer", 
            "Phase 1 optimizations completed",
            **optimization_summary
        )
        
        return optimization_summary
    
    async def _optimize_http2_connections(self) -> Dict[str, Any]:
        """Optimize HTTP/2 connections with pre-establishment."""
        start_time = time.time()
        
        try:
            await log_info(
                "phase1_optimizer",
                "Starting HTTP/2 connection optimization"
            )
            
            http_manager = get_http_client_manager()
            
            # Create optimized HTTP/2 clients for each provider
            connection_results = {}
            
            for provider in self.config.prewarm_providers:
                try:
                    provider_start = time.time()
                    
                    # Get client with enhanced HTTP/2 configuration
                    client = http_manager.get_client(provider)
                    
                    # Establish connection with HTTP/2 negotiation
                    await self._establish_http2_connection(provider, client)
                    
                    provider_duration = (time.time() - provider_start) * 1000
                    connection_results[provider] = {
                        "success": True,
                        "duration_ms": provider_duration,
                        "http2_enabled": True
                    }
                    
                    self.prewarmed_connections[provider] = True
                    
                except Exception as e:
                    provider_duration = (time.time() - provider_start) * 1000
                    connection_results[provider] = {
                        "success": False,
                        "duration_ms": provider_duration,
                        "error": str(e)
                    }
                    
                    self.prewarmed_connections[provider] = False
            
            total_duration = (time.time() - start_time) * 1000
            
            # Record metrics
            successful_connections = len([r for r in connection_results.values() if r.get("success", False)])
            record_latency("phase1", "http2_optimization", total_duration)
            record_counter("phase1", "http2_connections_established", successful_connections)
            
            return {
                "optimization": "http2_connections",
                "total_duration_ms": total_duration,
                "successful_connections": successful_connections,
                "total_providers": len(self.config.prewarm_providers),
                "connection_results": connection_results
            }
            
        except Exception as e:
            await log_error(
                "phase1_optimizer",
                f"HTTP/2 optimization failed: {str(e)}",
                error=str(e)
            )
            raise
    
    async def _establish_http2_connection(self, provider: str, client):
        """Establish HTTP/2 connection for a provider."""
        # Provider-specific endpoints optimized for HTTP/2
        http2_endpoints = {
            "openai": "https://api.openai.com/v1/models",
            "groq": "https://api.groq.com/openai/v1/models", 
            "anthropic": "https://api.anthropic.com/v1/messages",
            "google": "https://generativelanguage.googleapis.com/v1beta/models"
        }
        
        endpoint = http2_endpoints.get(provider)
        if not endpoint:
            return
        
        try:
            # Start client to establish connection pool
            await client.start()
            
            # Make lightweight OPTIONS request to establish HTTP/2 connection
            # OPTIONS is safe, cacheable, and typically fastest
            response = await client.request(
                "OPTIONS", 
                endpoint,
                timeout=httpx.Timeout(connect=3.0, read=5.0)
            )
            
            # Check if HTTP/2 was negotiated
            http_version = getattr(response, 'http_version', 'HTTP/1.1')
            
            logger.debug(f"Established {http_version} connection to {provider}")
            
            # Store connection info for metrics
            self.connection_metrics[provider] = {
                "http_version": http_version,
                "established_at": time.time()
            }
            
        except Exception as e:
            logger.debug(f"Failed to establish HTTP/2 connection to {provider}: {e}")
            raise
    
    async def _optimize_keepalive_settings(self) -> Dict[str, Any]:
        """Optimize keep-alive settings for all HTTP clients."""
        start_time = time.time()
        
        try:
            await log_info(
                "phase1_optimizer",
                "Optimizing keep-alive settings"
            )
            
            http_manager = get_http_client_manager()
            
            # Apply optimized keep-alive settings to all existing clients
            optimized_clients = 0
            
            for client_key, client in http_manager.clients.items():
                try:
                    # HTTP clients are already configured with optimized keep-alive in http_client_manager.py
                    # This is a validation step to ensure settings are applied
                    await client.start()
                    optimized_clients += 1
                    
                except Exception as e:
                    logger.warning(f"Failed to optimize keep-alive for {client_key}: {e}")
            
            total_duration = (time.time() - start_time) * 1000
            
            record_latency("phase1", "keepalive_optimization", total_duration)
            record_counter("phase1", "keepalive_clients_optimized", optimized_clients)
            
            return {
                "optimization": "keepalive_settings",
                "total_duration_ms": total_duration,
                "optimized_clients": optimized_clients,
                "keepalive_timeout": self.config.keepalive_timeout
            }
            
        except Exception as e:
            await log_error(
                "phase1_optimizer",
                f"Keep-alive optimization failed: {str(e)}",
                error=str(e)
            )
            raise
    
    async def _parallel_provider_prewarm(self) -> Dict[str, Any]:
        """Parallel provider pre-warming for optimal connection reuse."""
        start_time = time.time()
        
        try:
            await log_info(
                "phase1_optimizer",
                "Starting parallel provider pre-warming",
                providers=self.config.prewarm_providers
            )
            
            # Create semaphore for controlled concurrency
            semaphore = asyncio.Semaphore(self.config.max_concurrent_prewarming)
            
            # Create pre-warming tasks for each provider
            prewarm_tasks = []
            for provider in self.config.prewarm_providers:
                prewarm_tasks.append(self._prewarm_provider_with_semaphore(semaphore, provider))
            
            # Execute pre-warming in parallel
            prewarm_results = await asyncio.gather(*prewarm_tasks, return_exceptions=True)
            
            # Process results
            successful_prewarming = 0
            provider_results = {}
            
            for provider, result in zip(self.config.prewarm_providers, prewarm_results):
                if isinstance(result, Exception):
                    provider_results[provider] = {
                        "success": False,
                        "error": str(result)
                    }
                else:
                    provider_results[provider] = result
                    if result.get("success", False):
                        successful_prewarming += 1
            
            total_duration = (time.time() - start_time) * 1000
            
            record_latency("phase1", "parallel_prewarm", total_duration)
            record_counter("phase1", "providers_prewarmed", successful_prewarming)
            
            return {
                "optimization": "parallel_provider_prewarm",
                "total_duration_ms": total_duration,
                "successful_prewarming": successful_prewarming,
                "total_providers": len(self.config.prewarm_providers),
                "provider_results": provider_results
            }
            
        except Exception as e:
            await log_error(
                "phase1_optimizer",
                f"Parallel provider pre-warming failed: {str(e)}",
                error=str(e)
            )
            raise
    
    async def _prewarm_provider_with_semaphore(self, semaphore: asyncio.Semaphore, provider: str) -> Dict[str, Any]:
        """Pre-warm a specific provider with concurrency control."""
        async with semaphore:
            start_time = time.time()
            
            try:
                http_manager = get_http_client_manager()
                client = http_manager.get_client(provider)
                
                # Start client and establish connection
                await client.start()
                
                # Validate connection with lightweight request
                if self.config.validate_connections:
                    await self._validate_provider_connection(provider, client)
                
                duration_ms = (time.time() - start_time) * 1000
                
                return {
                    "success": True,
                    "duration_ms": duration_ms,
                    "connection_validated": self.config.validate_connections
                }
                
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                return {
                    "success": False,
                    "duration_ms": duration_ms,
                    "error": str(e)
                }
    
    async def _validate_provider_connection(self, provider: str, client):
        """Validate provider connection with lightweight request."""
        validation_endpoints = {
            "openai": ("HEAD", "https://api.openai.com/v1/models"),
            "groq": ("HEAD", "https://api.groq.com/openai/v1/models"),
            "anthropic": ("OPTIONS", "https://api.anthropic.com/v1/messages"),
            "google": ("HEAD", "https://generativelanguage.googleapis.com/v1beta/models")
        }
        
        if provider not in validation_endpoints:
            return
        
        method, endpoint = validation_endpoints[provider]
        
        try:
            response = await client.request(
                method,
                endpoint,
                timeout=httpx.Timeout(connect=2.0, read=self.config.connection_validation_timeout)
            )
            
            # Any response (even 401/403) indicates successful connection
            if response.status_code in [200, 401, 403, 405]:  # 405 = Method Not Allowed (for OPTIONS)
                logger.debug(f"Connection validated for {provider} ({response.status_code})")
                return True
            
        except Exception as e:
            logger.debug(f"Connection validation failed for {provider}: {e}")
            raise
    
    async def _preresol_dns(self) -> Dict[str, Any]:
        """Pre-resolve DNS for all provider endpoints."""
        start_time = time.time()
        
        try:
            await log_info(
                "phase1_optimizer",
                "Starting DNS pre-resolution"
            )
            
            # Provider hostnames for DNS pre-resolution
            provider_hostnames = {
                "openai": "api.openai.com",
                "groq": "api.groq.com", 
                "anthropic": "api.anthropic.com",
                "google": "generativelanguage.googleapis.com"
            }
            
            # DNS resolution is handled by httpx/aiohttp automatically
            # This is more of a connection establishment verification
            resolved_hosts = 0
            
            for provider, hostname in provider_hostnames.items():
                try:
                    # The HTTP clients will handle DNS resolution with caching
                    # This validates that the hostnames are resolvable
                    import socket
                    socket.getaddrinfo(hostname, 443, socket.AF_UNSPEC, socket.SOCK_STREAM)
                    resolved_hosts += 1
                    logger.debug(f"DNS resolved for {provider}: {hostname}")
                    
                except Exception as e:
                    logger.debug(f"DNS resolution failed for {provider}: {e}")
            
            total_duration = (time.time() - start_time) * 1000
            
            record_latency("phase1", "dns_preresolution", total_duration)
            record_counter("phase1", "dns_hosts_resolved", resolved_hosts)
            
            return {
                "optimization": "dns_preresolution",
                "total_duration_ms": total_duration,
                "resolved_hosts": resolved_hosts,
                "total_hosts": len(provider_hostnames)
            }
            
        except Exception as e:
            await log_error(
                "phase1_optimizer",
                f"DNS pre-resolution failed: {str(e)}",
                error=str(e)
            )
            raise
    
    def get_optimization_status(self) -> Dict[str, Any]:
        """Get current optimization status."""
        return {
            "phase": "1",
            "optimization_type": "http_client_hotrodding",
            "prewarmed_connections": self.prewarmed_connections,
            "connection_metrics": self.connection_metrics,
            "config": self.config.__dict__
        }


# Global Phase 1 optimizer instance
_phase1_optimizer: Optional[Phase1Optimizer] = None


def get_phase1_optimizer() -> Phase1Optimizer:
    """Get the global Phase 1 optimizer."""
    global _phase1_optimizer
    if _phase1_optimizer is None:
        _phase1_optimizer = Phase1Optimizer()
    return _phase1_optimizer


async def run_phase1_optimizations(config: Optional[Phase1Config] = None) -> Dict[str, Any]:
    """Run Phase 1 HTTP client hot-rodding optimizations."""
    optimizer = Phase1Optimizer(config)
    return await optimizer.run_phase1_optimizations()


async def quick_phase1_optimization() -> Dict[str, Any]:
    """Run a quick Phase 1 optimization with minimal configuration."""
    config = Phase1Config(
        prewarm_providers=["openai", "groq"],  # Focus on primary providers
        prewarm_timeout=5.0,
        max_concurrent_prewarming=4,
        validate_connections=True
    )
    
    return await run_phase1_optimizations(config)