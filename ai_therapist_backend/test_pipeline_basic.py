import asyncio
import logging
from datetime import datetime

# Import your pipeline and existing services
from app.services.streaming_pipeline import EnhancedAsyncPipeline, FlowControlConfig, StreamingMessage
from app.services.llm_manager import llm_manager  # Your existing LLM manager

# Set up logging to see what's happening
logging.basicConfig(level=logging.INFO)

async def test_tts_only():
    """Test the simplest case: Maya's response → TTS → Audio chunks"""
    
    print("🧪 Testing TTS-only pipeline...")
    
    try:
        # 1. Create pipeline with default config
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config, llm_manager)
        
        # 2. Start the pipeline (this runs all the async tasks)
        await pipeline.start()
        print("✅ Pipeline started successfully")
        
        # 3. Create a test message (Maya's pre-written response)
        # This bypasses LLM and goes straight to TTS
        test_message = StreamingMessage(
            message_id="test_001",
            conversation_id="test_conv",
            user_message="Hello! I'm Maya, your AI assistant. How can I help you today?",
            metadata={
                "is_tts_only": True,  # 🔑 KEY: Skip LLM, go straight to TTS
                "voice": "nova"       # Safe OpenAI voice
            }
        )
        
        # 4. Add message to pipeline
        success = await pipeline.add_message(test_message)
        print(f"✅ Message queued: {success}")
        
        if not success:
            print("❌ Failed to queue message - check logs")
            return False
        
        # 5. Wait for processing (audio generation takes time)
        print("⏳ Waiting for TTS processing...")
        await asyncio.sleep(5)  # Give it time to process
        
        # 6. Check metrics to see if anything happened
        metrics = pipeline.get_metrics()
        print(f"📊 Messages processed: {metrics['throughput']['messages_processed']}")
        print(f"📊 Chunks generated: {metrics['throughput']['chunks_generated']}")
        print(f"📊 Audio chunks sent: {metrics['throughput']['audio_chunks_sent']}")
        print(f"📊 Pipeline state: {metrics['pipeline_state']}")
        
        # 7. Success criteria
        if metrics['throughput']['messages_processed'] > 0:
            print("🎉 SUCCESS: TTS-only pipeline working!")
            success_result = True
        else:
            print("❌ FAILED: No messages processed")
            success_result = False
        
        # 8. Clean shutdown
        await pipeline.stop()
        print("✅ Pipeline stopped cleanly")
        
        return success_result
        
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        return False

# Run the test
if __name__ == "__main__":
    result = asyncio.run(test_tts_only())
    if result:
        print("\n🚀 Ready for Step 2: Full Pipeline Test!")
    else:
        print("\n🔧 Fix issues before proceeding") 