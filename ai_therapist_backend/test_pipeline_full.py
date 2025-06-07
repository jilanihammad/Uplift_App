import asyncio
import logging
from datetime import datetime

from app.services.streaming_pipeline import EnhancedAsyncPipeline, FlowControlConfig, StreamingMessage
from app.services.llm_manager import llm_manager

logging.basicConfig(level=logging.INFO)

async def test_full_pipeline():
    """Test complete flow: User input → LLM → TTS → Audio"""
    
    print("🧪 Testing FULL pipeline (LLM + TTS)...")
    
    try:
        # 1. Create and start pipeline
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config, llm_manager)
        await pipeline.start()
        print("✅ Pipeline started")
        
        # 2. Create user message (will trigger LLM processing)
        user_message = StreamingMessage(
            message_id="full_test_001",
            conversation_id="test_conv",
            user_message="Hello Maya, how are you today?",  # User's question
            metadata={
                "is_tts_only": False,  # 🔑 KEY: Full LLM processing needed
                "voice": "nova",
                "system_prompt": "You are Maya, a helpful AI assistant.",
                "temperature": 0.7
            }
        )
        
        # 3. Send message
        success = await pipeline.add_message(user_message)
        print(f"✅ User message queued: {success}")
        
        # 4. Wait longer for LLM + TTS processing
        print("⏳ Waiting for LLM response generation + TTS...")
        await asyncio.sleep(10)  # LLM takes longer than just TTS
        
        # 5. Check metrics
        metrics = pipeline.get_metrics()
        print(f"📊 Messages processed: {metrics['throughput']['messages_processed']}")
        print(f"📊 Chunks generated: {metrics['throughput']['chunks_generated']}")
        print(f"📊 Audio chunks sent: {metrics['throughput']['audio_chunks_sent']}")
        print(f"📊 LLM latency: {metrics['timing']['avg_llm_latency_ms']:.1f}ms")
        print(f"📊 TTS latency: {metrics['timing']['avg_tts_latency_ms']:.1f}ms")
        print(f"📊 Time to first audio: {metrics['timing']['time_to_first_audio_ms']:.1f}ms")
        
        # 6. Success criteria
        if (metrics['throughput']['messages_processed'] > 0 and 
            metrics['throughput']['audio_chunks_sent'] > 0):
            print("🎉 SUCCESS: Full pipeline working!")
            success_result = True
        else:
            print("❌ FAILED: Pipeline not generating audio")
            success_result = False
        
        await pipeline.stop()
        return success_result
        
    except Exception as e:
        print(f"❌ Full pipeline test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    result = asyncio.run(test_full_pipeline())
    if result:
        print("\n🚀 Ready for Step 3: WebSocket Integration!")
    else:
        print("\n🔧 Fix issues before proceeding") 