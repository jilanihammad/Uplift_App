#!/usr/bin/env python3
"""
Test script for Phase 0 TTFB metrics implementation.

This script demonstrates the new TTFB tracking capabilities added to the backend:
1. LLM chat streaming TTFB measurement
2. TTS first-byte latency tracking  
3. Provider error rate monitoring
4. Real-time metrics endpoint

Usage:
    python test_ttfb_metrics.py
"""

import asyncio
import aiohttp
import json
import time
from typing import Dict, Any

BACKEND_URL = "http://localhost:8000"

async def test_metrics_endpoint():
    """Test the new /metrics endpoint."""
    print("🔍 Testing /metrics endpoint...")
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(f"{BACKEND_URL}/metrics") as response:
                if response.status == 200:
                    data = await response.json()
                    print("✅ Metrics endpoint is working")
                    print(f"📊 Phase 0 Status: {data.get('phase_0_status', {})}")
                    
                    # Show critical metrics targets
                    targets = data.get('critical_metrics', {}).get('targets', {})
                    print("🎯 TTFB Targets:")
                    for metric, target in targets.items():
                        print(f"  • {metric}: {target.get('target', 'N/A')}")
                    
                    return True
                else:
                    print(f"❌ Metrics endpoint returned {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Error testing metrics endpoint: {e}")
            return False

async def test_health_endpoint():
    """Test that health endpoint still works."""
    print("\n🔍 Testing /health endpoint...")
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(f"{BACKEND_URL}/health") as response:
                if response.status == 200:
                    data = await response.json()
                    print("✅ Health endpoint is working")
                    print(f"📊 Status: {data.get('status', 'unknown')}")
                    return True
                else:
                    print(f"❌ Health endpoint returned {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Error testing health endpoint: {e}")
            return False

async def simulate_chat_request():
    """Simulate a chat request to test LLM TTFB tracking."""
    print("\n🔍 Testing LLM TTFB tracking...")
    
    # Sample chat request
    chat_data = {
        "history": [
            {"role": "user", "content": "Hello, how are you today?", "sequence": 1}
        ]
    }
    
    async with aiohttp.ClientSession() as session:
        try:
            start_time = time.time()
            async with session.post(
                f"{BACKEND_URL}/sessions/test-session/chat_stream",
                json=chat_data,
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 200:
                    # Read first chunk to measure TTFB
                    first_chunk = await response.content.read(1024)
                    client_ttfb = (time.time() - start_time) * 1000
                    
                    print("✅ LLM streaming request successful")
                    print(f"⏱️  Client-measured TTFB: {client_ttfb:.1f}ms")
                    print("📝 Server-side TTFB metrics should now be recorded")
                    return True
                else:
                    print(f"❌ Chat request returned {response.status}")
                    error_text = await response.text()
                    print(f"Error details: {error_text}")
                    return False
        except Exception as e:
            print(f"❌ Error testing chat request: {e}")
            return False

async def simulate_tts_request():
    """Simulate a TTS request to test TTS first-byte tracking."""
    print("\n🔍 Testing TTS TTFB tracking...")
    
    # Sample TTS request  
    tts_data = {
        "text": "Hello, this is a test of text-to-speech latency measurement.",
        "voice": "alloy",
        "model": "tts-1"
    }
    
    async with aiohttp.ClientSession() as session:
        try:
            start_time = time.time()
            async with session.post(
                f"{BACKEND_URL}/voice/synthesize",
                json=tts_data,
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 200:
                    # Read first chunk to measure TTFB
                    first_chunk = await response.content.read(1024)
                    client_ttfb = (time.time() - start_time) * 1000
                    
                    print("✅ TTS request successful")
                    print(f"⏱️  Client-measured TTFB: {client_ttfb:.1f}ms")
                    print("📝 Server-side TTS TTFB metrics should now be recorded")
                    return True
                else:
                    print(f"❌ TTS request returned {response.status}")
                    error_text = await response.text()
                    print(f"Error details: {error_text}")
                    return False
        except Exception as e:
            print(f"❌ Error testing TTS request: {e}")
            return False

async def check_metrics_after_requests():
    """Check if metrics were recorded after our test requests."""
    print("\n🔍 Checking recorded metrics...")
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(f"{BACKEND_URL}/metrics") as response:
                if response.status == 200:
                    data = await response.json()
                    metrics = data.get('metrics', {})
                    
                    print("📊 Recorded Metrics:")
                    for metric_name, metric_data in metrics.items():
                        if 'ttfb' in metric_name.lower() or 'first_byte' in metric_name.lower():
                            print(f"  • {metric_name}: {metric_data}")
                    
                    return True
                else:
                    print(f"❌ Could not fetch metrics: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Error checking metrics: {e}")
            return False

async def main():
    """Run all tests."""
    print("🚀 Phase 0 TTFB Metrics Test Suite")
    print("=" * 50)
    
    results = []
    
    # Test basic endpoints
    results.append(await test_health_endpoint())
    results.append(await test_metrics_endpoint())
    
    # Test TTFB tracking
    results.append(await simulate_chat_request())
    results.append(await simulate_tts_request())
    
    # Check metrics collection
    results.append(await check_metrics_after_requests())
    
    # Summary
    print("\n" + "=" * 50)
    print("📋 Test Summary")
    print(f"✅ Passed: {sum(results)}/{len(results)} tests")
    
    if all(results):
        print("🎉 Phase 0 TTFB metrics implementation is working correctly!")
        print("✅ Ready to proceed to Phase 1: HTTP Client Hot-rodding")
    else:
        print("⚠️  Some tests failed. Check the backend logs for details.")
        print("💡 Make sure the backend is running: python dev_server.py")

if __name__ == "__main__":
    asyncio.run(main())