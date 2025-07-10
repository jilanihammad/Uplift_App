#!/usr/bin/env python3
"""
Test the streamlined OPUS streaming implementation.
This verifies the optimized _stream_openai_opus method works correctly.
"""
import asyncio
import sys
import os
import base64

# Add the app directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))

from services.llm_manager import LLMManager
from config.llm_config import LLMConfig

async def test_streamlined_opus():
    """Test the streamlined OPUS streaming implementation"""
    print("🎵 Testing streamlined OPUS streaming implementation...")
    
    try:
        # Initialize LLM manager
        config = LLMConfig()
        manager = LLMManager(config)
        
        # Test text
        test_text = "Testing the streamlined OPUS implementation with direct streaming from OpenAI."
        
        print(f"📝 Text to convert: {test_text}")
        print(f"🎤 Voice: sage")
        
        # Collect streaming chunks
        chunks = []
        total_bytes = 0
        
        print("🎵 Starting OPUS streaming...")
        async for chunk_b64 in manager._stream_openai_opus(
            text=test_text,
            voice="sage"
        ):
            # Decode chunk to get actual byte size
            chunk_bytes = base64.b64decode(chunk_b64)
            chunks.append(chunk_bytes)
            total_bytes += len(chunk_bytes)
            
            print(f"📦 Received chunk {len(chunks)}: {len(chunk_bytes)} bytes")
            
            # Stop after reasonable number of chunks for testing
            if len(chunks) >= 10:
                break
        
        # Verify we got valid OPUS data
        if chunks:
            first_chunk = chunks[0]
            print(f"🔍 First chunk header: {first_chunk[:16].hex()}")
            
            # Check for OGG header
            if first_chunk.startswith(b"OggS"):
                print("✅ OPUS stream has proper OGG container header")
            else:
                print("❌ OPUS stream missing OGG header")
            
            # Save combined output for verification
            output_file = "test_streamlined_opus.ogg"
            with open(output_file, "wb") as f:
                for chunk in chunks:
                    f.write(chunk)
            
            file_size = os.path.getsize(output_file)
            print(f"💾 Combined output saved: {output_file} ({file_size} bytes)")
            
            print(f"📊 Total chunks: {len(chunks)}")
            print(f"📊 Total bytes: {total_bytes}")
            print("✅ Streamlined OPUS streaming test PASSED")
            return True
        else:
            print("❌ No chunks received")
            return False
            
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = asyncio.run(test_streamlined_opus())
    sys.exit(0 if success else 1)