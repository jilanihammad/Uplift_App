"""
Enhanced Logging Configuration

This module provides production-optimized logging configuration with:
- Environment-specific log levels
- External library log suppression  
- Structured logging with correlation IDs
- Performance-optimized logging
- httpcore DEBUG suppression for production
"""

import logging
import os
import sys
import time
from typing import Dict, Any, Optional
from functools import wraps
from contextvars import ContextVar

# Import existing environment settings
from app.core.environment import env_settings, Environment

# Context variables for request tracing
request_id_context: ContextVar[str] = ContextVar('request_id', default='')
trace_id_context: ContextVar[str] = ContextVar('trace_id', default='')


class ProductionOptimizedFormatter(logging.Formatter):
    """
    Production-optimized formatter with structured logging and correlation IDs.
    """
    
    def __init__(self, include_trace_info: bool = True):
        super().__init__()
        self.include_trace_info = include_trace_info
        
    def format(self, record: logging.LogRecord) -> str:
        """Format log record with structured information."""
        # Base log information
        log_data = {
            'timestamp': time.time(),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
        }
        
        # Add trace information if available and enabled
        if self.include_trace_info:
            request_id = request_id_context.get('')
            trace_id = trace_id_context.get('')
            
            if request_id:
                log_data['request_id'] = request_id
            if trace_id:
                log_data['trace_id'] = trace_id
        
        # Add exception information if present
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)
        
        # Add extra fields from record
        for key, value in record.__dict__.items():
            if key not in {'name', 'msg', 'args', 'levelname', 'levelno', 'pathname', 
                          'filename', 'module', 'lineno', 'funcName', 'created', 'msecs', 
                          'relativeCreated', 'thread', 'threadName', 'processName', 'process',
                          'message', 'exc_info', 'exc_text', 'stack_info', 'getMessage'}:
                log_data[key] = value
        
        # Format as JSON in production, human-readable in development
        if env_settings.is_production or env_settings.is_staging:
            import json
            return json.dumps(log_data, default=str)
        else:
            # Human-readable format for development
            base_msg = f"{record.levelname}: {record.getMessage()}"
            if request_id or trace_id:
                trace_info = f" [req:{request_id or 'N/A'}, trace:{trace_id or 'N/A'}]"
                base_msg += trace_info
            return base_msg


class EnhancedLoggingConfig:
    """Enhanced logging configuration with environment-specific optimizations."""
    
    # Library-specific log levels for production
    PRODUCTION_LOG_LEVELS = {
        # HTTP libraries - suppress DEBUG to reduce noise
        'httpcore': logging.WARNING,
        'httpcore.connection': logging.WARNING,
        'httpcore.http11': logging.WARNING,
        'httpcore.http2': logging.WARNING,
        'httpx': logging.INFO,
        'urllib3': logging.WARNING,
        'requests': logging.WARNING,
        
        # Database libraries
        'sqlalchemy.engine': logging.WARNING,
        'sqlalchemy.pool': logging.WARNING,
        'alembic': logging.INFO,
        
        # Cloud libraries
        'google.cloud': logging.INFO,
        'google.auth': logging.WARNING,
        'google.oauth2': logging.WARNING,
        
        # Other libraries
        'websockets': logging.INFO,
        'asyncio': logging.WARNING,
        'multipart': logging.WARNING,
        'uvicorn': logging.INFO,
        'fastapi': logging.INFO,
        
        # AI/ML libraries
        'openai': logging.INFO,
        'anthropic': logging.INFO,
        'groq': logging.INFO,
    }
    
    # Development log levels (more verbose)
    DEVELOPMENT_LOG_LEVELS = {
        'httpcore': logging.INFO,
        'httpcore.connection': logging.INFO,
        'httpcore.http11': logging.INFO,
        'httpcore.http2': logging.INFO,
        'httpx': logging.DEBUG,
        'urllib3': logging.INFO,
        'requests': logging.INFO,
        'sqlalchemy.engine': logging.INFO,
        'sqlalchemy.pool': logging.INFO,
        'websockets': logging.DEBUG,
        'asyncio': logging.INFO,
        'uvicorn': logging.INFO,
        'fastapi': logging.DEBUG,
        'openai': logging.DEBUG,
        'anthropic': logging.DEBUG,
        'groq': logging.DEBUG,
    }
    
    @classmethod
    def setup_enhanced_logging(cls):
        """Setup enhanced logging configuration."""
        # Clear existing handlers
        root_logger = logging.getLogger()
        for handler in root_logger.handlers:
            root_logger.removeHandler(handler)
        
        # Set root log level based on environment
        if env_settings.is_production:
            root_level = logging.INFO
            library_levels = cls.PRODUCTION_LOG_LEVELS
        elif env_settings.is_staging:
            root_level = logging.INFO
            library_levels = cls.PRODUCTION_LOG_LEVELS
        else:
            root_level = logging.DEBUG
            library_levels = cls.DEVELOPMENT_LOG_LEVELS
        
        root_logger.setLevel(root_level)
        
        # Configure library-specific log levels
        for library, level in library_levels.items():
            logging.getLogger(library).setLevel(level)
        
        # Setup handlers based on environment
        if env_settings.is_production or env_settings.is_staging:
            cls._setup_production_logging()
        else:
            cls._setup_development_logging()
        
        # Log configuration completion
        logger = logging.getLogger("ai_therapist.logging")
        logger.info(f"Enhanced logging configured for {env_settings.environment} environment")
        logger.info(f"Root log level: {logging.getLevelName(root_level)}")
        logger.info(f"httpcore log level: {logging.getLevelName(library_levels.get('httpcore', root_level))}")
        
    @classmethod
    def _setup_production_logging(cls):
        """Setup production logging with Google Cloud Logging."""
        try:
            # Try to setup Google Cloud Logging
            import google.cloud.logging
            client = google.cloud.logging.Client()
            client.setup_logging()
            
            logger = logging.getLogger("ai_therapist.logging")
            logger.info("Google Cloud Logging initialized successfully")
            
        except Exception as e:
            # Fallback to structured console logging
            cls._setup_fallback_logging(structured=True)
            logger = logging.getLogger("ai_therapist.logging")
            logger.warning(f"Failed to initialize Google Cloud Logging: {str(e)}")
            logger.info("Using fallback structured console logging")
        else:
            # Even with Google Cloud Logging, ensure our formatter is used for local handlers
            root_logger = logging.getLogger()
            formatter = ProductionOptimizedFormatter(include_trace_info=True)
            cls._update_all_loggers_formatter(formatter)
    
    @classmethod
    def _setup_development_logging(cls):
        """Setup development logging with human-readable format."""
        cls._setup_fallback_logging(structured=False)
        
    @classmethod
    def _setup_fallback_logging(cls, structured: bool = True):
        """Setup fallback console logging."""
        root_logger = logging.getLogger()
        
        # Console handler
        handler = logging.StreamHandler(sys.stdout)
        
        # Use enhanced formatter
        formatter = ProductionOptimizedFormatter(include_trace_info=True)
        handler.setFormatter(formatter)
        
        # Remove existing handlers to avoid duplication
        for existing_handler in root_logger.handlers[:]:
            root_logger.removeHandler(existing_handler)
        
        root_logger.addHandler(handler)
        
        # Ensure all existing loggers use this formatter
        cls._update_all_loggers_formatter(formatter)
    
    @classmethod
    def _update_all_loggers_formatter(cls, formatter):
        """Update all existing loggers to use the enhanced formatter."""
        # Get all existing loggers
        existing_loggers = [logging.getLogger(name) for name in logging.root.manager.loggerDict]
        existing_loggers.append(logging.root)
        
        for logger in existing_loggers:
            for handler in logger.handlers:
                handler.setFormatter(formatter)
    
    @classmethod
    def suppress_noisy_libraries(cls):
        """Suppress noisy libraries in production."""
        if env_settings.is_production or env_settings.is_staging:
            # Extra suppression for very noisy libraries
            logging.getLogger('httpcore.connection').setLevel(logging.ERROR)
            logging.getLogger('httpcore.http11').setLevel(logging.ERROR)
            logging.getLogger('httpcore.http2').setLevel(logging.ERROR)
            logging.getLogger('urllib3.connectionpool').setLevel(logging.ERROR)
            logging.getLogger('multipart.multipart').setLevel(logging.ERROR)
            
            # Suppress asyncio debug messages
            logging.getLogger('asyncio').setLevel(logging.WARNING)
            
            logger = logging.getLogger("ai_therapist.logging")
            logger.info("Noisy library logging suppressed for production")
    
    @classmethod
    def get_logger(cls, name: str) -> logging.Logger:
        """Get a logger with enhanced configuration."""
        return logging.getLogger(name)


# Decorator for adding request tracing
def with_request_trace(request_id: str = None, trace_id: str = None):
    """Decorator to add request tracing to functions."""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            # Set context variables
            req_id = request_id or f"req_{int(time.time() * 1000)}"
            tr_id = trace_id or f"trace_{int(time.time() * 1000)}"
            
            request_id_context.set(req_id)
            trace_id_context.set(tr_id)
            
            try:
                return await func(*args, **kwargs)
            finally:
                # Clear context on exit
                request_id_context.set('')
                trace_id_context.set('')
        
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            # Set context variables
            req_id = request_id or f"req_{int(time.time() * 1000)}"
            tr_id = trace_id or f"trace_{int(time.time() * 1000)}"
            
            request_id_context.set(req_id)
            trace_id_context.set(tr_id)
            
            try:
                return func(*args, **kwargs)
            finally:
                # Clear context on exit
                request_id_context.set('')
                trace_id_context.set('')
        
        # Return appropriate wrapper based on function type
        import asyncio
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper
    
    return decorator


# Convenience functions
def setup_logging():
    """Setup enhanced logging configuration."""
    EnhancedLoggingConfig.setup_enhanced_logging()
    EnhancedLoggingConfig.suppress_noisy_libraries()


def get_logger(name: str) -> logging.Logger:
    """Get a logger with enhanced configuration."""
    return EnhancedLoggingConfig.get_logger(name)


def set_request_context(request_id: str, trace_id: str = None):
    """Set request context for logging."""
    request_id_context.set(request_id)
    if trace_id:
        trace_id_context.set(trace_id)


def get_request_context() -> Dict[str, str]:
    """Get current request context."""
    return {
        'request_id': request_id_context.get(''),
        'trace_id': trace_id_context.get('')
    }


def clear_request_context():
    """Clear request context."""
    request_id_context.set('')
    trace_id_context.set('')


# Context manager for request tracing
class RequestTraceContext:
    """Context manager for request tracing."""
    
    def __init__(self, request_id: str, trace_id: str = None):
        self.request_id = request_id
        self.trace_id = trace_id or f"trace_{int(time.time() * 1000)}"
        self.previous_request_id = None
        self.previous_trace_id = None
    
    def __enter__(self):
        self.previous_request_id = request_id_context.get('')
        self.previous_trace_id = trace_id_context.get('')
        
        request_id_context.set(self.request_id)
        trace_id_context.set(self.trace_id)
        
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        request_id_context.set(self.previous_request_id)
        trace_id_context.set(self.previous_trace_id)