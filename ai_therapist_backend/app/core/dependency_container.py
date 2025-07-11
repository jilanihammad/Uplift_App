"""
Early Dependency Injection Container

This module provides a lightweight dependency injection container for new services
while maintaining backward compatibility with existing service locator patterns.

Features:
- Constructor injection for new services
- Interface-based design
- Singleton lifecycle management
- Configuration injection
- Service health monitoring
- Graceful degradation
"""

import asyncio
import logging
import time
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Type, TypeVar, Generic, Callable, List
from dataclasses import dataclass
from enum import Enum
import weakref
from contextlib import asynccontextmanager

from app.core.observability import log_info, log_error, log_warning

logger = logging.getLogger(__name__)

T = TypeVar('T')


class ServiceScope(Enum):
    """Service lifecycle scopes."""
    SINGLETON = "singleton"
    TRANSIENT = "transient"
    SCOPED = "scoped"


class ServiceStatus(Enum):
    """Service status."""
    REGISTERED = "registered"
    INITIALIZING = "initializing"
    READY = "ready"
    ERROR = "error"
    DISPOSED = "disposed"


@dataclass
class ServiceDescriptor:
    """Descriptor for registered services."""
    service_type: Type
    implementation_type: Type
    factory: Optional[Callable] = None
    scope: ServiceScope = ServiceScope.SINGLETON
    dependencies: List[Type] = None
    status: ServiceStatus = ServiceStatus.REGISTERED
    instance: Any = None
    created_at: Optional[float] = None
    error: Optional[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []


class ServiceInterface(ABC):
    """Base interface for all services."""
    
    @abstractmethod
    async def initialize(self) -> None:
        """Initialize the service."""
        pass
    
    @abstractmethod
    async def dispose(self) -> None:
        """Dispose of the service."""
        pass
    
    @abstractmethod
    def get_health_status(self) -> Dict[str, Any]:
        """Get service health status."""
        pass


class ICircuitBreakerService(ServiceInterface):
    """Interface for circuit breaker service."""
    
    @abstractmethod
    async def call_with_protection(self, provider: str, operation: str, func: Callable, *args, **kwargs) -> Any:
        """Call function with circuit breaker protection."""
        pass
    
    @abstractmethod
    def get_breaker_status(self, provider: str) -> Dict[str, Any]:
        """Get circuit breaker status."""
        pass


class IObservabilityService(ServiceInterface):
    """Interface for observability service."""
    
    @abstractmethod
    async def log_event(self, level: str, service: str, message: str, **kwargs) -> None:
        """Log an event."""
        pass
    
    @abstractmethod
    def record_metric(self, name: str, value: float, labels: Dict[str, str] = None) -> None:
        """Record a metric."""
        pass
    
    @abstractmethod
    def get_metrics_summary(self) -> Dict[str, Any]:
        """Get metrics summary."""
        pass


class IHTTPClientService(ServiceInterface):
    """Interface for HTTP client service."""
    
    @abstractmethod
    async def get_client(self, provider: str) -> Any:
        """Get HTTP client for provider."""
        pass
    
    @abstractmethod
    def get_client_stats(self) -> Dict[str, Any]:
        """Get client statistics."""
        pass


class IWarmupService(ServiceInterface):
    """Interface for warm-up service."""
    
    @abstractmethod
    async def run_warmup(self, config: Any = None) -> Dict[str, Any]:
        """Run warm-up process."""
        pass
    
    @abstractmethod
    def get_warmup_status(self) -> Dict[str, Any]:
        """Get warm-up status."""
        pass


class DependencyResolutionException(Exception):
    """Exception raised when dependency resolution fails."""
    pass


class CircularDependencyException(Exception):
    """Exception raised when circular dependencies are detected."""
    pass


class ServiceContainer:
    """
    Lightweight dependency injection container.
    
    Features:
    - Constructor injection
    - Interface-based design
    - Singleton lifecycle management
    - Circular dependency detection
    - Service health monitoring
    """
    
    def __init__(self):
        self._services: Dict[Type, ServiceDescriptor] = {}
        self._instances: Dict[Type, Any] = {}
        self._resolution_stack: List[Type] = []
        self._initialized = False
        self._disposal_callbacks: List[Callable] = []
        
        # Service health tracking
        self._health_checks: Dict[Type, Callable] = {}
        self._last_health_check = 0
        self._health_check_interval = 30.0  # 30 seconds
        
    def register_singleton(self, interface: Type[T], implementation: Type[T], 
                          dependencies: List[Type] = None) -> 'ServiceContainer':
        """Register a singleton service."""
        return self._register_service(interface, implementation, ServiceScope.SINGLETON, dependencies)
    
    def register_transient(self, interface: Type[T], implementation: Type[T], 
                          dependencies: List[Type] = None) -> 'ServiceContainer':
        """Register a transient service."""
        return self._register_service(interface, implementation, ServiceScope.TRANSIENT, dependencies)
    
    def register_scoped(self, interface: Type[T], implementation: Type[T], 
                       dependencies: List[Type] = None) -> 'ServiceContainer':
        """Register a scoped service."""
        return self._register_service(interface, implementation, ServiceScope.SCOPED, dependencies)
    
    def register_factory(self, interface: Type[T], factory: Callable[[], T], 
                        scope: ServiceScope = ServiceScope.SINGLETON) -> 'ServiceContainer':
        """Register a factory function."""
        descriptor = ServiceDescriptor(
            service_type=interface,
            implementation_type=interface,
            factory=factory,
            scope=scope
        )
        
        self._services[interface] = descriptor
        return self
    
    def register_instance(self, interface: Type[T], instance: T) -> 'ServiceContainer':
        """Register an existing instance."""
        descriptor = ServiceDescriptor(
            service_type=interface,
            implementation_type=type(instance),
            scope=ServiceScope.SINGLETON,
            instance=instance,
            status=ServiceStatus.READY,
            created_at=time.time()
        )
        
        self._services[interface] = descriptor
        self._instances[interface] = instance
        return self
    
    def _register_service(self, interface: Type[T], implementation: Type[T], 
                         scope: ServiceScope, dependencies: List[Type] = None) -> 'ServiceContainer':
        """Register a service with the container."""
        descriptor = ServiceDescriptor(
            service_type=interface,
            implementation_type=implementation,
            scope=scope,
            dependencies=dependencies or []
        )
        
        self._services[interface] = descriptor
        
        logger.info(f"Registered service: {interface.__name__} -> {implementation.__name__} ({scope.value})")
        return self
    
    async def get_service(self, interface: Type[T]) -> T:
        """Get a service instance."""
        if interface not in self._services:
            raise DependencyResolutionException(f"Service {interface.__name__} not registered")
        
        descriptor = self._services[interface]
        
        # Check for circular dependencies
        if interface in self._resolution_stack:
            cycle = " -> ".join([t.__name__ for t in self._resolution_stack[self._resolution_stack.index(interface):]])
            raise CircularDependencyException(f"Circular dependency detected: {cycle} -> {interface.__name__}")
        
        # Handle singleton scope
        if descriptor.scope == ServiceScope.SINGLETON:
            if interface in self._instances:
                return self._instances[interface]
            
            instance = await self._create_instance(interface, descriptor)
            self._instances[interface] = instance
            return instance
        
        # Handle transient scope
        elif descriptor.scope == ServiceScope.TRANSIENT:
            return await self._create_instance(interface, descriptor)
        
        # Handle scoped scope (for now, treat as singleton)
        elif descriptor.scope == ServiceScope.SCOPED:
            if interface in self._instances:
                return self._instances[interface]
            
            instance = await self._create_instance(interface, descriptor)
            self._instances[interface] = instance
            return instance
        
        else:
            raise DependencyResolutionException(f"Unsupported scope: {descriptor.scope}")
    
    async def _create_instance(self, interface: Type[T], descriptor: ServiceDescriptor) -> T:
        """Create a service instance."""
        descriptor.status = ServiceStatus.INITIALIZING
        
        try:
            self._resolution_stack.append(interface)
            
            # Use factory if available
            if descriptor.factory:
                instance = descriptor.factory()
            else:
                # Resolve dependencies
                dependencies = []
                for dep_type in descriptor.dependencies:
                    dep_instance = await self.get_service(dep_type)
                    dependencies.append(dep_instance)
                
                # Create instance
                instance = descriptor.implementation_type(*dependencies)
            
            # Initialize if it's a service interface
            if isinstance(instance, ServiceInterface):
                await instance.initialize()
            
            descriptor.status = ServiceStatus.READY
            descriptor.instance = instance
            descriptor.created_at = time.time()
            
            await log_info(
                "dependency_container",
                f"Service {interface.__name__} created successfully",
                service_type=interface.__name__,
                implementation_type=descriptor.implementation_type.__name__
            )
            
            return instance
            
        except Exception as e:
            descriptor.status = ServiceStatus.ERROR
            descriptor.error = str(e)
            
            await log_error(
                "dependency_container",
                f"Failed to create service {interface.__name__}: {str(e)}",
                service_type=interface.__name__,
                error=str(e)
            )
            
            raise DependencyResolutionException(f"Failed to create service {interface.__name__}: {str(e)}")
        
        finally:
            if interface in self._resolution_stack:
                self._resolution_stack.remove(interface)
    
    async def initialize_all(self) -> None:
        """Initialize all registered services."""
        if self._initialized:
            return
        
        await log_info(
            "dependency_container",
            "Initializing all services",
            service_count=len(self._services)
        )
        
        initialization_tasks = []
        
        for interface in self._services.keys():
            task = asyncio.create_task(self._initialize_service(interface))
            initialization_tasks.append(task)
        
        # Wait for all services to initialize
        results = await asyncio.gather(*initialization_tasks, return_exceptions=True)
        
        # Check for failures
        failed_services = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                interface = list(self._services.keys())[i]
                failed_services.append((interface.__name__, str(result)))
        
        if failed_services:
            await log_error(
                "dependency_container",
                f"Failed to initialize {len(failed_services)} services",
                failed_services=failed_services
            )
        
        self._initialized = True
        
        await log_info(
            "dependency_container",
            "Service initialization complete",
            successful_services=len(self._services) - len(failed_services),
            failed_services=len(failed_services)
        )
    
    async def _initialize_service(self, interface: Type) -> None:
        """Initialize a single service."""
        try:
            await self.get_service(interface)
        except Exception as e:
            await log_error(
                "dependency_container",
                f"Failed to initialize service {interface.__name__}",
                service_type=interface.__name__,
                error=str(e)
            )
            raise
    
    async def dispose_all(self) -> None:
        """Dispose of all service instances."""
        await log_info(
            "dependency_container",
            "Disposing all services",
            service_count=len(self._instances)
        )
        
        disposal_tasks = []
        
        for interface, instance in self._instances.items():
            if isinstance(instance, ServiceInterface):
                task = asyncio.create_task(instance.dispose())
                disposal_tasks.append(task)
        
        # Wait for all services to dispose
        await asyncio.gather(*disposal_tasks, return_exceptions=True)
        
        # Run disposal callbacks
        for callback in self._disposal_callbacks:
            try:
                await callback()
            except Exception as e:
                logger.error(f"Error in disposal callback: {e}")
        
        self._instances.clear()
        self._initialized = False
        
        await log_info(
            "dependency_container",
            "Service disposal complete"
        )
    
    def add_disposal_callback(self, callback: Callable) -> None:
        """Add a callback to run during disposal."""
        self._disposal_callbacks.append(callback)
    
    def get_service_health(self) -> Dict[str, Any]:
        """Get health status of all services."""
        current_time = time.time()
        
        # Run health checks if needed
        if current_time - self._last_health_check > self._health_check_interval:
            self._run_health_checks()
            self._last_health_check = current_time
        
        service_health = {}
        
        for interface, descriptor in self._services.items():
            service_health[interface.__name__] = {
                "status": descriptor.status.value,
                "created_at": descriptor.created_at,
                "uptime_seconds": current_time - descriptor.created_at if descriptor.created_at else 0,
                "error": descriptor.error,
                "has_instance": interface in self._instances
            }
            
            # Add health check result if available
            if interface in self._instances and isinstance(self._instances[interface], ServiceInterface):
                try:
                    health_status = self._instances[interface].get_health_status()
                    service_health[interface.__name__]["health_check"] = health_status
                except Exception as e:
                    service_health[interface.__name__]["health_check_error"] = str(e)
        
        return {
            "overall_health": "healthy" if all(
                desc.status == ServiceStatus.READY 
                for desc in self._services.values()
            ) else "degraded",
            "initialized": self._initialized,
            "total_services": len(self._services),
            "ready_services": sum(1 for desc in self._services.values() 
                                if desc.status == ServiceStatus.READY),
            "services": service_health
        }
    
    def _run_health_checks(self) -> None:
        """Run health checks for all services."""
        for interface, instance in self._instances.items():
            if isinstance(instance, ServiceInterface):
                try:
                    # This will trigger health check internally
                    instance.get_health_status()
                except Exception as e:
                    logger.warning(f"Health check failed for {interface.__name__}: {e}")
    
    @asynccontextmanager
    async def scope_context(self):
        """Context manager for scoped services."""
        scoped_instances = {}
        
        try:
            # Store current instances
            original_instances = self._instances.copy()
            
            # Create new scope
            yield self
            
        finally:
            # Dispose scoped instances
            for interface, instance in self._instances.items():
                if (interface not in original_instances and 
                    isinstance(instance, ServiceInterface)):
                    try:
                        await instance.dispose()
                    except Exception as e:
                        logger.error(f"Error disposing scoped service {interface.__name__}: {e}")
            
            # Restore original instances
            self._instances = original_instances


# Global container instance
_container: Optional[ServiceContainer] = None


def get_container() -> ServiceContainer:
    """Get the global service container."""
    global _container
    if _container is None:
        _container = ServiceContainer()
    return _container


# Convenience functions
def register_singleton(interface: Type[T], implementation: Type[T], 
                      dependencies: List[Type] = None) -> ServiceContainer:
    """Register a singleton service."""
    return get_container().register_singleton(interface, implementation, dependencies)


def register_transient(interface: Type[T], implementation: Type[T], 
                      dependencies: List[Type] = None) -> ServiceContainer:
    """Register a transient service."""
    return get_container().register_transient(interface, implementation, dependencies)


def register_instance(interface: Type[T], instance: T) -> ServiceContainer:
    """Register an existing instance."""
    return get_container().register_instance(interface, instance)


async def get_service(interface: Type[T]) -> T:
    """Get a service instance."""
    return await get_container().get_service(interface)


async def initialize_container() -> None:
    """Initialize the global container."""
    await get_container().initialize_all()


async def dispose_container() -> None:
    """Dispose of the global container."""
    await get_container().dispose_all()


def get_container_health() -> Dict[str, Any]:
    """Get container health status."""
    return get_container().get_service_health()