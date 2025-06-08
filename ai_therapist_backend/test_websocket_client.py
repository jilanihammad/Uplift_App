import asyncio
import json
import websockets

async def test_websocket_client():
    """Simple test client to verify WebSocket integration"""
    
    uri = "ws://localhost:8000/voice-chat"  # Your FastAPI URL
    
    try:
        async with websockets.connect(uri) as websocket:
            print("🔗 Connected to WebSocket")
            
            # 1. Receive init frame
            init_message = await websocket.recv()
            init_data = json.loads(init_message)
            print(f"📋 Received init: {init_data['type']}")
            
            # 2. Send test message
            test_message = {
                "type": "user_message",
                "text": "Hello Maya, please introduce yourself",
                "conversation_id": "test_conversation"
            }
            
            await websocket.send(json.dumps(test_message))
            print("📤 Sent test message")
            
            # 3. Listen for audio chunks
            audio_chunks_received = 0
            timeout_count = 0
            
            while timeout_count < 20:  # 20 second timeout
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=1.0)
                    data = json.loads(message)
                    
                    if data["type"] == "audio":
                        audio_chunks_received += 1
                        print(f"🔊 Received audio chunk {audio_chunks_received}")
                        
                    elif data["type"] == "complete":
                        print(f"✅ Completed! Total chunks: {data['total_chunks']}")
                        break
                        
                    elif data["type"] == "checkpoint":
                        print(f"📍 Checkpoint: {data['chunks_sent']} chunks sent")
                        
                except asyncio.TimeoutError:
                    timeout_count += 1
                    continue
            
            print(f"🎉 Test completed! Received {audio_chunks_received} audio chunks")
            
    except Exception as e:
        print(f"❌ WebSocket test failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_websocket_client()) 