#!/usr/bin/env python3
"""
Test script to verify that the streaming pipeline sends only one completion signal per message.

This script tests the message-level completion tracking logic to ensure that:
1. Multi-sentence messages only send ONE completion signal after all sentences are processed
2. Single-sentence messages send ONE completion signal
3. No duplicate completion signals are sent

Usage: python test_single_completion_signal.py
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, List, Any
import sys
import os

# Add the app directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))

from app.services.streaming_pipeline import (
    EnhancedAsyncPipeline, 
    StreamingMessage, 
    FlowControlConfig,
    CompletionSentinel,
    TextChunk,
    BoundaryType
)

# Mock LLM Manager for testing
class MockLLMManager:
    def __init__(self):
        self.call_count = 0
        
    async def get_chat_response(self, message: str, **kwargs) -> str:
        """Mock AI response that generates multiple sentences"""
        self.call_count += 1
        if "single" in message.lower():
            return "This is a single sentence response."
        elif "multi" in message.lower():
            return "This is sentence one. This is sentence two. This is sentence three."
        else:
            return "Default response with two sentences. This completes the response."
    
    async def stream_text_to_speech(self, text: str, **kwargs):
        """Mock TTS that yields base64 audio chunks"""
        # Simulate streaming audio chunks for each word
        words = text.split()
        for i, word in enumerate(words):
            # Simulate base64 audio data
            mock_audio = f"mock_audio_chunk_{i}_{word}".encode('utf-8')
            import base64
            yield base64.b64encode(mock_audio).decode('utf-8')
            await asyncio.sleep(0.01)  # Small delay to simulate real TTS

# Test WebSocket mock
class MockWebSocket:
    def __init__(self, client_id: str):
        self.client_id = client_id
        self.sent_messages: List[Dict[str, Any]] = []
        self.connected = True
        
    async def send_text(self, message: str):
        """Mock send_text that records sent messages"""
        data = json.loads(message)
        self.sent_messages.append(data)
        print(f"[{self.client_id}] SENT: {data}")
        
    async def send(self, message: str):
        """Alternative send method"""
        await self.send_text(message)
        
    def get_completion_signals(self) -> List[Dict[str, Any]]:
        """Get all completion signals sent to this client"""
        return [msg for msg in self.sent_messages if msg.get('type') == 'tts_complete']

async def test_single_completion_signal():
    """Test that only one completion signal is sent per message"""
    print("🧪 Testing Single Completion Signal Logic")
    print("=" * 60)
    
    # Configure logging
    logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')
    logger = logging.getLogger('test')
    
    # Create mock LLM manager
    mock_llm = MockLLMManager()
    
    # Create pipeline with test configuration
    config = FlowControlConfig(
        llm_queue_size=10,
        tts_queue_size=10,
        client_queue_size=20
    )
    
    pipeline = EnhancedAsyncPipeline(config, mock_llm, logger)
    await pipeline.start()
    
    try:
        # Create mock WebSocket clients
        client1 = MockWebSocket("client_1")
        client2 = MockWebSocket("client_2")
        
        # Register clients with pipeline
        await pipeline.register_client("client_1", client1)
        await pipeline.register_client("client_2", client2)
        
        print(f"✅ Pipeline started, clients registered")
        
        # Test Case 1: Single sentence message
        print("\n🔍 Test Case 1: Single Sentence Message")
        print("-" * 40)
        
        single_message = StreamingMessage(
            message_id="msg_single_001",
            conversation_id="test_conv_1",
            user_message="Generate a single sentence response",
            priority=1,
            metadata={
                "client_id": "client_1",
                "voice": "nova",
                "format": "wav",
                "test_case": "single_sentence"
            }
        )
        
        success = await pipeline.add_message(single_message)
        assert success, "Failed to add single sentence message"
        
        # Wait for processing
        await asyncio.sleep(3)
        
        # Check completion signals for single sentence
        client1_completions = client1.get_completion_signals()
        client2_completions = client2.get_completion_signals()
        
        print(f"Client 1 completion signals: {len(client1_completions)}")
        print(f"Client 2 completion signals: {len(client2_completions)}")
        
        for completion in client1_completions:
            print(f"  - {completion}")
        
        assert len(client1_completions) == 1, f"Expected 1 completion signal for single sentence, got {len(client1_completions)}"
        assert len(client2_completions) == 1, f"Expected 1 completion signal for single sentence, got {len(client2_completions)}"
        
        print("✅ Single sentence test passed")
        
        # Test Case 2: Multi-sentence message
        print("\n🔍 Test Case 2: Multi-Sentence Message")
        print("-" * 40)
        
        # Clear previous messages
        client1.sent_messages.clear()
        client2.sent_messages.clear()
        
        multi_message = StreamingMessage(
            message_id="msg_multi_002",
            conversation_id="test_conv_1",
            user_message="Generate a multi sentence response",
            priority=1,
            metadata={
                "client_id": "client_1",
                "voice": "nova",
                "format": "wav",
                "test_case": "multi_sentence"
            }
        )
        
        success = await pipeline.add_message(multi_message)
        assert success, "Failed to add multi-sentence message"
        
        # Wait for processing
        await asyncio.sleep(5)
        
        # Check completion signals for multi-sentence
        client1_completions = client1.get_completion_signals()
        client2_completions = client2.get_completion_signals()
        
        print(f"Client 1 completion signals: {len(client1_completions)}")
        print(f"Client 2 completion signals: {len(client2_completions)}")
        
        for completion in client1_completions:
            print(f"  - {completion}")
        
        assert len(client1_completions) == 1, f"Expected 1 completion signal for multi-sentence, got {len(client1_completions)}"
        assert len(client2_completions) == 1, f"Expected 1 completion signal for multi-sentence, got {len(client2_completions)}"
        
        print("✅ Multi-sentence test passed")
        
        # Test Case 3: Multiple concurrent messages
        print("\n🔍 Test Case 3: Multiple Concurrent Messages")
        print("-" * 40)
        
        # Clear previous messages
        client1.sent_messages.clear()
        client2.sent_messages.clear()
        
        messages = []
        for i in range(3):
            message = StreamingMessage(
                message_id=f"msg_concurrent_{i:03d}",
                conversation_id="test_conv_1",
                user_message=f"Message {i} with multi sentences",
                priority=1,
                metadata={
                    "client_id": "client_1",
                    "voice": "nova",
                    "format": "wav",
                    "test_case": f"concurrent_{i}"
                }
            )
            messages.append(message)
            
        # Add all messages
        for msg in messages:
            success = await pipeline.add_message(msg)
            assert success, f"Failed to add concurrent message {msg.message_id}"
            
        # Wait for all processing
        await asyncio.sleep(8)
        
        # Check completion signals
        client1_completions = client1.get_completion_signals()
        client2_completions = client2.get_completion_signals()
        
        print(f"Client 1 completion signals: {len(client1_completions)}")
        print(f"Client 2 completion signals: {len(client2_completions)}")
        
        # Should have exactly 3 completion signals (one per message)
        assert len(client1_completions) == 3, f"Expected 3 completion signals for concurrent messages, got {len(client1_completions)}"
        assert len(client2_completions) == 3, f"Expected 3 completion signals for concurrent messages, got {len(client2_completions)}"
        
        # Verify each completion has a unique message ID
        completion_message_ids = {completion['request_id'] for completion in client1_completions}
        assert len(completion_message_ids) == 3, f"Expected 3 unique message IDs, got {len(completion_message_ids)}"
        
        print("✅ Concurrent messages test passed")
        
        print("\n🎉 All tests passed! Single completion signal logic is working correctly.")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    finally:
        # Cleanup
        await pipeline.stop()
        print("✅ Pipeline stopped")
    
    return True

async def test_message_completion_tracking():
    """Test the internal message completion tracking logic"""
    print("\n🧪 Testing Message Completion Tracking Internals")
    print("=" * 60)
    
    # Configure logging
    logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')
    logger = logging.getLogger('test_internals')
    
    # Create mock LLM manager
    mock_llm = MockLLMManager()
    
    # Create pipeline
    config = FlowControlConfig()
    pipeline = EnhancedAsyncPipeline(config, mock_llm, logger)
    
    # Test the completion tracking logic directly
    message_id = "test_msg_001"
    
    # Simulate setting up message tracking for 3 sentences
    async with pipeline.message_completion_lock:
        pipeline.message_sentence_counts[message_id] = 3
        pipeline.message_completed_sentences[message_id] = 0
    
    print(f"✅ Set up message {message_id} expecting 3 sentences")
    
    # Test completing sentences one by one
    for sentence_num in range(1, 4):
        is_complete = await pipeline._check_and_handle_message_completion(message_id, f"sentence_{sentence_num}")
        expected_complete = (sentence_num == 3)  # Only last sentence should return True
        
        print(f"Sentence {sentence_num}: complete={is_complete}, expected={expected_complete}")
        assert is_complete == expected_complete, f"Sentence {sentence_num} completion mismatch"
    
    # Verify cleanup
    assert message_id not in pipeline.message_sentence_counts, "Message tracking not cleaned up"
    assert message_id not in pipeline.message_completed_sentences, "Completion tracking not cleaned up"
    
    print("✅ Message completion tracking test passed")

if __name__ == "__main__":
    async def main():
        try:
            # Run the tests
            success1 = await test_single_completion_signal()
            await test_message_completion_tracking()
            
            if success1:
                print("\n🎯 CONCLUSION: Single completion signal logic is working correctly!")
                print("The backend should only send ONE 'tts_complete' signal per AI response.")
            else:
                print("\n❌ CONCLUSION: Single completion signal logic has issues that need fixing.")
                
        except Exception as e:
            print(f"\n💥 Test execution failed: {e}")
            import traceback
            traceback.print_exc()
    
    asyncio.run(main())