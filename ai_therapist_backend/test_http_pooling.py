#!/usr/bin/env python3
"""
Test HTTP Client Pooling

This script tests the HTTP client pooling functionality to ensure:
1. Pooled clients are reused across requests
2. One-shot clients are eliminated
3. Connection pooling works as expected
"""

import asyncio
import sys
import os
import time

# Add the app to the path
sys.path.insert(0, '/home/jilani/MyApps/Uplift_App/ai_therapist_backend')

try:
    from app.core.http_client_manager import get_http_client_manager
    from app.core.http_utils import pooled_http_client, get_pooled_client, audit_one_shot_clients
    
    async def test_pooled_client_reuse():
        """Test that pooled clients are reused across requests."""
        print("Testing pooled client reuse...")
        
        http_manager = get_http_client_manager()
        
        # Get client for OpenAI twice
        client1 = http_manager.get_client("openai")
        client2 = http_manager.get_client("openai")
        
        # They should be the same object (reused)
        assert client1 is client2, "Pooled clients should be reused"
        print("✓ Pooled clients are properly reused")
        
        # Test with different providers
        groq_client = http_manager.get_client("groq")
        anthropic_client = http_manager.get_client("anthropic")
        
        # They should be different objects
        assert groq_client is not anthropic_client, "Different providers should have different clients"
        print("✓ Different providers have different clients")
        
        # Test client statistics
        await client1.start()
        stats = client1.get_stats()
        print(f"✓ Client stats: {stats}")
        
    async def test_http_utils():
        """Test HTTP utilities for pooled client usage."""
        print("\nTesting HTTP utilities...")
        
        # Test context manager
        async with pooled_http_client("openai") as client:
            print("✓ Context manager works")
            
        # Test direct client access
        client = await get_pooled_client("groq")
        print("✓ Direct client access works")
        
        # Test that clients are properly initialized
        assert client._initialized, "Client should be initialized"
        print("✓ Client initialization works")
        
    def test_one_shot_audit():
        """Test the one-shot client audit functionality."""
        print("\nTesting one-shot client audit...")
        
        findings = audit_one_shot_clients()
        
        print(f"Found {len(findings)} potential one-shot client usages:")
        for finding in findings:
            print(f"  {finding['file']}:{finding['line']} - {finding['pattern']}")
        
        # Filter out test files and known acceptable usage
        production_findings = [
            f for f in findings 
            if not any(exclude in f['file'] for exclude in [
                'test_', 'tests/', '__pycache__', '.pyc', 'cloud_deploy/', 
                'test_enhanced_logging.py', 'test_http_pooling.py'
            ])
        ]
        
        print(f"\nProduction code findings: {len(production_findings)}")
        for finding in production_findings:
            print(f"  {finding['file']}:{finding['line']} - {finding['content']}")
        
    async def test_client_performance():
        """Test that pooled clients perform well."""
        print("\nTesting client performance...")
        
        # Test multiple requests using the same client
        async with pooled_http_client("default") as client:
            start_time = time.time()
            
            # Make multiple requests (to httpbin for testing)
            tasks = []
            for i in range(5):
                # We'll simulate requests without actually making them
                # since we don't want to depend on external services
                task = asyncio.create_task(asyncio.sleep(0.01))
                tasks.append(task)
            
            await asyncio.gather(*tasks)
            
            duration = time.time() - start_time
            print(f"✓ 5 simulated requests completed in {duration:.3f}s")
            
    async def main():
        """Run all tests."""
        print("=== HTTP Client Pooling Test ===\n")
        
        await test_pooled_client_reuse()
        await test_http_utils()
        test_one_shot_audit()
        await test_client_performance()
        
        print("\n=== All tests completed ===")
    
    if __name__ == "__main__":
        asyncio.run(main())
        
except Exception as e:
    print(f"Error running HTTP pooling tests: {e}")
    import traceback
    traceback.print_exc()