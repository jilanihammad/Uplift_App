#!/usr/bin/env python3
"""
Simple Enhanced Logging Test

This script tests the enhanced logging configuration without external dependencies.
"""

import logging
import os
import sys

# Set environment for testing
os.environ['ENVIRONMENT'] = 'production'

# Add the app to the path
sys.path.insert(0, '/home/jilani/MyApps/Uplift_App/ai_therapist_backend')

try:
    from app.core.enhanced_logging import (
        setup_logging, 
        get_logger,
        RequestTraceContext,
    )
    
    def test_logging_levels():
        """Test that logging levels are configured correctly."""
        print("Testing logging level configuration...")
        
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
        
        # Test logging at different levels
        print("\nTesting log suppression (DEBUG messages should be suppressed):")
        httpcore_logger.debug("httpcore DEBUG - should be suppressed")
        httpcore_connection_logger.debug("httpcore.connection DEBUG - should be suppressed")
        
        print("\nTesting log visibility (INFO/WARNING messages should appear):")
        httpcore_logger.info("httpcore INFO - should appear")
        httpcore_logger.warning("httpcore WARNING - should appear")
        app_logger.info("app INFO - should appear")
        
        print("Logging level test completed\n")
    
    def test_request_context():
        """Test request context functionality."""
        print("Testing request context...")
        
        logger = get_logger('test_context')
        
        # Test without context
        logger.info("Log without context")
        
        # Test with context
        with RequestTraceContext('test_req_123', 'test_trace_456'):
            logger.info("Log with context")
        
        # Test back to no context
        logger.info("Log without context again")
        
        print("Request context test completed\n")
    
    def main():
        """Run all tests."""
        print("=== Simple Enhanced Logging Test ===\n")
        
        test_logging_levels()
        test_request_context()
        
        print("=== All tests completed ===")
    
    if __name__ == "__main__":
        main()
        
except Exception as e:
    print(f"Error running logging tests: {e}")
    import traceback
    traceback.print_exc()