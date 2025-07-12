#!/usr/bin/env python3
"""
WebSocket TTS Streaming Test Script
Tests TTFB (Time To First Byte) performance for the /ws/tts endpoint
"""

import asyncio
import json
import time
import sys

try:
    import websockets
except ImportError:
    print("❌ Missing websockets library. Install with: pip install websockets")
    sys.exit(1)

URL = "ws://localhost:8000/ws/tts"

async def test_tts_streaming():
    """Test WebSocket TTS streaming performance."""
    print(f"🔗 Connecting to {URL}")
    
    try:
        async with websockets.connect(URL) as ws:
            print("✅ WebSocket connected")
            
            # Wait for hello message
            hello_msg = await ws.recv()
            print(f"📨 Received: {hello_msg}")
            
            # Send TTS request
            t0 = time.perf_counter()
            payload = {
                "text": "Latency test. One two three four five six seven eight nine ten.",
                "voice": "sage",
                "params": {
                    "response_format": "wav"
                }
            }
            
            print(f"📤 Sending TTS request: {payload['text'][:30]}...")
            await ws.send(json.dumps(payload))
            
            first_chunk_received = False
            total_bytes = 0
            chunk_count = 0
            
            # Listen for responses
            async for msg in ws:
                if not first_chunk_received:
                    ttfb_ms = (time.perf_counter() - t0) * 1000
                    print(f"🎯 TTFB → {ttfb_ms:.0f} ms")
                    first_chunk_received = True
                
                if isinstance(msg, bytes):
                    # Audio chunk received
                    chunk_count += 1
                    total_bytes += len(msg)
                    print(f"🎵 Audio chunk {chunk_count}: {len(msg)} bytes")
                    
                    # Stop after a few chunks to prove streaming is working
                    if chunk_count >= 3:
                        print(f"✅ Streaming verified! Received {chunk_count} chunks ({total_bytes} bytes)")
                        break
                        
                elif isinstance(msg, str):
                    # Text message (control/status)
                    try:
                        data = json.loads(msg)
                        msg_type = data.get("type", "unknown")
                        print(f"📨 Control message: {msg_type}")
                        
                        if msg_type == "tts-done":
                            print(f"✅ TTS completed, total size: {data.get('total_size', 'unknown')} bytes")
                            break
                        elif msg_type == "error":
                            print(f"❌ Error: {data.get('detail', 'Unknown error')}")
                            break
                            
                    except json.JSONDecodeError:
                        print(f"📨 Raw message: {msg}")
                        
    except websockets.exceptions.ConnectionRefused:
        print("❌ Connection refused. Is the server running on localhost:8000?")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    return True

def main():
    """Run the WebSocket TTS test."""
    print("🧪 WebSocket TTS Streaming Test")
    print("=" * 40)
    
    success = asyncio.run(test_tts_streaming())
    
    print("\n" + "=" * 40)
    if success:
        print("✅ Test completed successfully!")
        print("💡 Check server logs for '🎵 FIRST-CHUNK LATENCY' messages")
    else:
        print("❌ Test failed")
        sys.exit(1)

if __name__ == "__main__":
    main()