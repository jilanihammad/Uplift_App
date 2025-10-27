#!/usr/bin/env python3
"""Quick test to verify Gemini Live duplex endpoint is accessible."""

import asyncio
import json
import websockets

async def test_gemini_live_endpoint():
    uri = "ws://localhost:8000/ws/gemini/live?userId=test-user"

    print(f"🔌 Attempting to connect to {uri}...")

    try:
        # Add headers that the server might expect
        extra_headers = {
            "Origin": "http://localhost:8000",
            "User-Agent": "test-client"
        }
        async with websockets.connect(uri, additional_headers=extra_headers) as websocket:
            print("✅ Connected successfully!")

            # Wait for ready message
            response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
            data = json.loads(response)
            print(f"📨 Received: {data}")

            if data.get("type") == "ready":
                print("✅ Gemini Live duplex mode is ENABLED and ready!")
                return True
            elif data.get("type") == "error":
                print(f"❌ Error: {data.get('detail')}")
                return False

    except asyncio.TimeoutError:
        print("❌ Timeout waiting for server response")
        return False
    except websockets.exceptions.WebSocketException as e:
        print(f"❌ WebSocket error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    result = asyncio.run(test_gemini_live_endpoint())
    exit(0 if result else 1)
