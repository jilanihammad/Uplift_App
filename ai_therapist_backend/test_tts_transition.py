#!/usr/bin/env python3
"""
Test script to verify TTS transition from VoiceService wrapper to direct LLMManager
Tests both paths side-by-side for comparison
"""
import os
import sys
import asyncio
import time
import traceback

# Add the app directory to path
sys.path.append(os.path.join(os.path.dirname(__file__)))

async def test_tts_transition():
    """Test both VoiceService wrapper and direct LLMManager paths"""
    print("🧪 Testing TTS Transition: VoiceService → LLMManager")
    print("=" * 60)
    
    try:
        # Import services
        print("🔄 Importing services...")
        try:
            from app.services.voice_service import voice_service
            print("✅ VoiceService imported successfully")
        except ImportError as e:
            print(f"❌ Failed to import VoiceService: {e}")
            return 1
        
        try:
            from app.services.llm_manager import llm_manager
            print("✅ LLMManager imported successfully")
        except ImportError as e:
            print(f"❌ Failed to import LLMManager: {e}")
            return 1
        
        # Check if TTS is available
        print("🔄 Checking TTS availability...")
        if not voice_service.available:
            print("❌ VoiceService reports TTS unavailable - check API keys")
            return 1
        print("✅ TTS is available")
        
        test_text = "Hello, this is a test of TTS transition from VoiceService to LLMManager."
        test_params = {"response_format": "wav", "voice": "nova"}
        
        # Test 1: Original VoiceService wrapper path
        print("\n🔧 Test 1: VoiceService WRAPPER path")
        print("-" * 40)
        
        # Force wrapper mode
        os.environ["USE_DIRECT_LLM_MANAGER"] = "false"
        # Reinitialize to pick up env change
        voice_service.use_direct_llm_manager = False
        
        start_time = time.time()
        try:
            wrapper_url = await voice_service.generate_speech(test_text, test_params)
            wrapper_time = time.time() - start_time
            print(f"✅ WRAPPER: Success - {wrapper_url} ({wrapper_time:.2f}s)")
        except Exception as e:
            print(f"❌ WRAPPER: Failed - {str(e)}")
            wrapper_time = None
        
        # Test 2: Direct LLMManager path  
        print("\n🚀 Test 2: Direct LLMManager path")
        print("-" * 40)
        
        # Force direct mode
        os.environ["USE_DIRECT_LLM_MANAGER"] = "true"
        # Reinitialize to pick up env change
        voice_service.use_direct_llm_manager = True
        
        start_time = time.time()
        try:
            direct_url = await voice_service.generate_speech(test_text, test_params)
            direct_time = time.time() - start_time
            print(f"✅ DIRECT: Success - {direct_url} ({direct_time:.2f}s)")
        except Exception as e:
            print(f"❌ DIRECT: Failed - {str(e)}")
            direct_time = None
        
        # Performance comparison
        print("\n📊 Performance Comparison")
        print("-" * 40)
        if wrapper_time and direct_time:
            diff = abs(wrapper_time - direct_time)
            faster = "DIRECT" if direct_time < wrapper_time else "WRAPPER"
            print(f"WRAPPER: {wrapper_time:.2f}s")
            print(f"DIRECT:  {direct_time:.2f}s")
            print(f"Difference: {diff:.2f}s ({faster} is faster)")
        else:
            print("Could not compare - one or both tests failed")
        
        # Test 3: Streaming comparison (if time permits)
        print("\n🌊 Test 3: Streaming TTS (Quick Test)")
        print("-" * 40)
        
        short_text = "Quick streaming test."
        
        # Test wrapper streaming
        os.environ["USE_DIRECT_LLM_MANAGER"] = "false"
        voice_service.use_direct_llm_manager = False
        
        try:
            chunk_count = 0
            async for chunk in voice_service.stream_speech(short_text, test_params):
                chunk_count += 1
                if chunk_count >= 3:  # Only test first few chunks
                    break
            print(f"✅ WRAPPER Streaming: {chunk_count} chunks received")
        except Exception as e:
            print(f"❌ WRAPPER Streaming: Failed - {str(e)}")
        
        # Test direct streaming
        os.environ["USE_DIRECT_LLM_MANAGER"] = "true"
        voice_service.use_direct_llm_manager = True
        
        try:
            chunk_count = 0
            async for chunk in voice_service.stream_speech(short_text, test_params):
                chunk_count += 1
                if chunk_count >= 3:  # Only test first few chunks
                    break
            print(f"✅ DIRECT Streaming: {chunk_count} chunks received")
        except Exception as e:
            print(f"❌ DIRECT Streaming: Failed - {str(e)}")
            
        print("\n" + "=" * 60)
        print("✅ TTS Transition Test Completed!")
        print("\n💡 How to use the feature flag:")
        print("   - Set USE_DIRECT_LLM_MANAGER=false for VoiceService wrapper")
        print("   - Set USE_DIRECT_LLM_MANAGER=true for direct LLMManager")
        print("   - Both paths should work identically")
        print("   - Direct path has slightly less overhead")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    exit_code = asyncio.run(test_tts_transition())
    sys.exit(exit_code)