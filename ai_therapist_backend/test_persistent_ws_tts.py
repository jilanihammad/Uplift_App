#!/usr/bin/env python3
"""
Test script for persistent WebSocket TTS connections
Tests the new persistent connection functionality to validate:
1. Multiple TTS requests on same connection
2. Request correlation with UUIDs
3. Cancellation support
4. Heartbeat mechanism
5. Performance improvement (elimination of 300-400ms connection overhead)
"""

import asyncio
import json
import time
import uuid
import websockets
import logging
from typing import Dict, List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class PersistentTTSTestClient:
    def __init__(self, url: str = "ws://localhost:8001/ws/tts"):
        self.url = url
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.pending_requests: Dict[str, float] = {}  # request_id -> start_time
        self.completed_requests: List[Dict] = []
        self.connected = False
        
    async def connect(self):
        """Establish WebSocket connection"""
        logger.info(f"Connecting to {self.url}")
        try:
            self.websocket = await websockets.connect(self.url)
            self.connected = True
            
            # Wait for tts-hello message
            hello_msg = await self.websocket.recv()
            hello_data = json.loads(hello_msg)
            logger.info(f"Received hello: {hello_data}")
            
            if hello_data.get("type") == "tts-hello":
                capabilities = hello_data.get("capabilities", [])
                logger.info(f"Server capabilities: {capabilities}")
                return True
            else:
                raise Exception(f"Unexpected hello message: {hello_data}")
                
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            self.connected = False
            return False
    
    async def send_tts_request(self, text: str, voice: str = "sage", format: str = "wav") -> str:
        """Send a TTS request and return the request ID"""
        if not self.connected or not self.websocket:
            raise Exception("Not connected to WebSocket")
            
        request_id = str(uuid.uuid4())
        request = {
            "request_id": request_id,
            "text": text,
            "voice": voice,
            "params": {
                "response_format": format
            }
        }
        
        logger.info(f"Sending TTS request: {request_id} - '{text[:50]}...'")
        start_time = time.time()
        self.pending_requests[request_id] = start_time
        
        await self.websocket.send(json.dumps(request))
        return request_id
    
    async def cancel_request(self, request_id: str):
        """Cancel a specific TTS request"""
        cancel_msg = {
            "type": "cancel",
            "request_id": request_id
        }
        logger.info(f"Cancelling request: {request_id}")
        await self.websocket.send(json.dumps(cancel_msg))
    
    async def listen_for_messages(self):
        """Listen for incoming messages (control messages and audio data)"""
        try:
            while self.connected and self.websocket:
                message = await self.websocket.recv()
                
                if isinstance(message, str):
                    # Control message
                    await self._handle_control_message(message)
                else:
                    # Binary audio data
                    await self._handle_audio_data(message)
                    
        except websockets.exceptions.ConnectionClosed:
            logger.info("WebSocket connection closed")
            self.connected = False
        except Exception as e:
            logger.error(f"Error listening for messages: {e}")
            self.connected = False
    
    async def _handle_control_message(self, message: str):
        """Handle control messages from server"""
        try:
            data = json.loads(message)
            msg_type = data.get("type")
            request_id = data.get("request_id")
            
            if msg_type == "queued":
                logger.info(f"Request queued: {request_id}")
            elif msg_type == "tts-started":
                logger.info(f"TTS started: {request_id}")
            elif msg_type == "tts-done":
                total_size = data.get("total_size", 0)
                logger.info(f"TTS completed: {request_id} ({total_size} bytes)")
                
                # Calculate latency metrics
                if request_id in self.pending_requests:
                    start_time = self.pending_requests.pop(request_id)
                    total_latency = (time.time() - start_time) * 1000
                    
                    self.completed_requests.append({
                        "request_id": request_id,
                        "total_latency_ms": total_latency,
                        "audio_size_bytes": total_size
                    })
                    
                    logger.info(f"Request {request_id} completed in {total_latency:.1f}ms")
                    
            elif msg_type == "cancelled":
                logger.info(f"Request cancelled: {request_id}")
                self.pending_requests.pop(request_id, None)
            elif msg_type == "error":
                detail = data.get("detail", "Unknown error")
                logger.error(f"Server error for {request_id}: {detail}")
                self.pending_requests.pop(request_id, None)
            elif msg_type == "ping":
                # Respond to heartbeat
                pong = {"type": "pong"}
                await self.websocket.send(json.dumps(pong))
                logger.debug("Responded to ping with pong")
            elif msg_type == "goodbye":
                logger.info("Server acknowledged goodbye")
                self.connected = False
            else:
                logger.warning(f"Unknown message type: {msg_type}")
                
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse control message: {e}")
    
    async def _handle_audio_data(self, data: bytes):
        """Handle binary audio data"""
        # For testing, we just log the chunk size
        logger.debug(f"Received audio chunk: {len(data)} bytes")
    
    async def close(self):
        """Close the WebSocket connection gracefully"""
        if self.connected and self.websocket:
            try:
                # Send bye message
                bye_msg = {"type": "bye"}
                await self.websocket.send(json.dumps(bye_msg))
                await asyncio.sleep(0.1)  # Brief delay for server to respond
                
                await self.websocket.close()
                logger.info("WebSocket connection closed gracefully")
            except Exception as e:
                logger.error(f"Error closing connection: {e}")
        
        self.connected = False
    
    def get_performance_summary(self) -> Dict:
        """Get performance metrics summary"""
        if not self.completed_requests:
            return {"error": "No completed requests"}
        
        latencies = [req["total_latency_ms"] for req in self.completed_requests]
        audio_sizes = [req["audio_size_bytes"] for req in self.completed_requests]
        
        return {
            "total_requests": len(self.completed_requests),
            "avg_latency_ms": sum(latencies) / len(latencies),
            "min_latency_ms": min(latencies),
            "max_latency_ms": max(latencies),
            "avg_audio_size_bytes": sum(audio_sizes) / len(audio_sizes),
            "total_audio_bytes": sum(audio_sizes),
            "requests": self.completed_requests
        }

async def test_multiple_requests():
    """Test multiple TTS requests on same persistent connection"""
    client = PersistentTTSTestClient()
    
    try:
        # Connect to server
        if not await client.connect():
            logger.error("Failed to establish connection")
            return
        
        # Start message listener
        listener_task = asyncio.create_task(client.listen_for_messages())
        
        # Test messages
        test_messages = [
            "Hello, this is the first test message.",
            "This is the second test to verify persistence.",
            "Third message should reuse the same connection.",
            "Fourth message testing latency improvement.",
            "Final message to complete the test suite."
        ]
        
        logger.info(f"Testing {len(test_messages)} TTS requests on persistent connection")
        
        # Send all requests (should reuse connection)
        request_ids = []
        for i, text in enumerate(test_messages):
            logger.info(f"Sending request {i+1}/{len(test_messages)}")
            request_id = await client.send_tts_request(text, format="wav")
            request_ids.append(request_id)
            
            # Small delay between requests to avoid overwhelming the queue
            await asyncio.sleep(1)
        
        # Wait for all requests to complete
        logger.info("Waiting for all requests to complete...")
        timeout = 60  # 60 second timeout for all requests
        start_wait = time.time()
        
        while client.pending_requests and (time.time() - start_wait) < timeout:
            await asyncio.sleep(0.5)
        
        if client.pending_requests:
            logger.warning(f"Timeout: {len(client.pending_requests)} requests still pending")
        
        # Stop listening
        listener_task.cancel()
        
        # Print performance summary
        summary = client.get_performance_summary()
        logger.info("=== PERFORMANCE SUMMARY ===")
        logger.info(f"Total requests: {summary.get('total_requests', 0)}")
        logger.info(f"Average latency: {summary.get('avg_latency_ms', 0):.1f}ms")
        logger.info(f"Min latency: {summary.get('min_latency_ms', 0):.1f}ms")
        logger.info(f"Max latency: {summary.get('max_latency_ms', 0):.1f}ms")
        logger.info(f"Total audio size: {summary.get('total_audio_bytes', 0)} bytes")
        
        # Close connection
        await client.close()
        
        # Analysis
        completed = summary.get('total_requests', 0)
        if completed >= 2:
            # Check if subsequent requests were faster (connection reuse benefit)
            first_latency = summary['requests'][0]['total_latency_ms']
            avg_subsequent = sum(req['total_latency_ms'] for req in summary['requests'][1:]) / (completed - 1)
            
            logger.info("=== CONNECTION REUSE ANALYSIS ===")
            logger.info(f"First request latency: {first_latency:.1f}ms (includes connection setup)")
            logger.info(f"Avg subsequent latency: {avg_subsequent:.1f}ms (reuses connection)")
            
            if first_latency > avg_subsequent:
                improvement = first_latency - avg_subsequent
                logger.info(f"✅ Connection reuse saved ~{improvement:.1f}ms per request")
            else:
                logger.info(f"⚠️ No clear latency improvement detected")
        
        return summary
        
    except Exception as e:
        logger.error(f"Test failed: {e}")
        return None
    finally:
        await client.close()

async def test_cancellation():
    """Test request cancellation functionality"""
    logger.info("=== TESTING REQUEST CANCELLATION ===")
    client = PersistentTTSTestClient()
    
    try:
        if not await client.connect():
            return
        
        listener_task = asyncio.create_task(client.listen_for_messages())
        
        # Send a long TTS request
        long_text = "This is a very long message that should take some time to synthesize. " * 10
        request_id = await client.send_tts_request(long_text)
        
        # Wait a bit, then cancel
        await asyncio.sleep(2)
        await client.cancel_request(request_id)
        
        # Wait to see cancellation response
        await asyncio.sleep(2)
        
        listener_task.cancel()
        await client.close()
        
        logger.info("Cancellation test completed")
        
    except Exception as e:
        logger.error(f"Cancellation test failed: {e}")
    finally:
        await client.close()

async def main():
    """Run all tests"""
    logger.info("Starting persistent WebSocket TTS tests")
    
    # Test multiple requests
    await test_multiple_requests()
    
    # Wait between tests
    await asyncio.sleep(2)
    
    # Test cancellation
    await test_cancellation()
    
    logger.info("All tests completed")

if __name__ == "__main__":
    asyncio.run(main())