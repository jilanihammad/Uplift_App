#!/usr/bin/env python3
"""
Test Enhanced Logging Configuration

This script tests the enhanced logging configuration to ensure:
1. httpcore DEBUG logging is suppressed in production
2. Request tracing works correctly
3. Structured logging functions properly
"""

import logging
import os
import sys
import asyncio
import httpx
from contextlib import asynccontextmanager

# Set environment for testing
os.environ['ENVIRONMENT'] = 'production'  # Test production logging

# Import after setting environment
from app.core.enhanced_logging import (
    setup_logging, 
    get_logger,
    RequestTraceContext,
    set_request_context,
    with_request_trace
)

async def test_httpcore_logging():
    """Test that httpcore DEBUG logging is suppressed."""
    print("Testing httpcore logging suppression...")
    
    # Setup logging
    setup_logging()
    
    # Get loggers
    root_logger = logging.getLogger()
    httpcore_logger = logging.getLogger('httpcore')
    httpcore_connection_logger = logging.getLogger('httpcore.connection')
    app_logger = get_logger('test_app')
    
    print(f"Root logger level: {logging.getLevelName(root_logger.level)}")
    print(f"httpcore logger level: {logging.getLevelName(httpcore_logger.level)}")
    print(f"httpcore.connection logger level: {logging.getLevelName(httpcore_connection_logger.level)}")
    
    # Test that httpcore DEBUG messages are suppressed
    httpcore_logger.debug("This httpcore DEBUG message should be suppressed")
    httpcore_connection_logger.debug("This httpcore.connection DEBUG message should be suppressed")
    
    # Test that INFO messages still come through
    httpcore_logger.info("This httpcore INFO message should appear")
    app_logger.info("This app INFO message should appear")
    
    # Test HTTP request to generate httpcore logs
    print("\nMaking HTTP request to test httpcore logging...")
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get('https://httpbin.org/get')
            print(f"HTTP request status: {response.status_code}")
    except Exception as e:
        print(f"HTTP request failed (expected in some environments): {e}")
    
    print("httpcore logging test completed\n")

def test_request_tracing():
    """Test request tracing functionality."""
    print("Testing request tracing...")
    
    logger = get_logger('test_tracing')
    
    # Test context manager
    with RequestTraceContext('test_req_123', 'test_trace_456'):
        logger.info("This log should have request and trace IDs")
        
        # Test nested context
        with RequestTraceContext('nested_req_789', 'nested_trace_101'):
            logger.info("This log should have nested request and trace IDs")
        
        logger.info("This log should have original request and trace IDs")
    
    logger.info("This log should have no request or trace IDs")
    
    print("Request tracing test completed\n")

@with_request_trace(request_id='decorator_req_222', trace_id='decorator_trace_333')
async def test_decorator_tracing():
    """Test decorator-based request tracing."""
    print("Testing decorator-based tracing...")
    
    logger = get_logger('test_decorator')
    logger.info("This log should have decorator-set request and trace IDs")
    
    # Simulate some async work
    await asyncio.sleep(0.1)
    
    logger.info("This log should still have decorator-set request and trace IDs")
    
    print("Decorator tracing test completed\n")

def test_structured_logging():
    """Test structured logging format."""
    print("Testing structured logging...")
    
    logger = get_logger('test_structured')
    
    # Set request context
    set_request_context('struct_req_444', 'struct_trace_555')
    
    # Test different log levels
    logger.info("Info message with structured data", extra={'key1': 'value1', 'key2': 42})
    logger.warning("Warning message", extra={'warning_type': 'test_warning'})
    logger.error("Error message", extra={'error_code': 'TEST_ERROR'})
    
    # Test exception logging
    try:
        raise ValueError("Test exception for logging")
    except Exception as e:
        logger.error("Exception occurred", exc_info=True)
    
    print("Structured logging test completed\n")

async def main():
    """Run all tests."""
    print("=== Enhanced Logging Configuration Test ===\n")
    
    # Test httpcore logging suppression
    await test_httpcore_logging()
    
    # Test request tracing
    test_request_tracing()
    
    # Test decorator tracing
    await test_decorator_tracing()
    
    # Test structured logging
    test_structured_logging()
    
    print("=== All tests completed ===")

if __name__ == "__main__":
    asyncio.run(main())