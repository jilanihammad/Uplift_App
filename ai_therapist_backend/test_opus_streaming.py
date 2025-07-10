#!/usr/bin/env python3
import requests
import os
import sys

def test_openai_opus():
    """Test direct OPUS format support from OpenAI TTS API"""
    print("Testing OpenAI TTS API with OPUS format...")
    
    # Use the same API key from the existing test
    api_key = "***REMOVED***"
    tts_model = "gpt-4o-mini-tts"
    voice = "sage"
    test_text = "Testing direct OPUS format from OpenAI TTS API. This should work without FFmpeg conversion."
    
    print(f"Using model: {tts_model}")
    print(f"Using voice: {voice}")
    print(f"Testing text: {test_text}")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    # Test different formats
    formats_to_test = ["opus", "wav", "mp3"]
    results = {}
    
    for fmt in formats_to_test:
        print(f"\n--- Testing format: {fmt} ---")
        
        data = {
            "model": tts_model,
            "input": test_text,
            "voice": voice,
            "response_format": fmt
        }
        
        url = "https://api.openai.com/v1/audio/speech"
        
        try:
            print(f"Sending request to OpenAI API for {fmt}...")
            response = requests.post(
                url,
                json=data,
                headers=headers,
                timeout=30
            )
            
            print(f"Response status code: {response.status_code}")
            print(f"Content-Type header: {response.headers.get('content-type', 'Not set')}")
            
            if response.status_code == 200:
                output_file = f"test_output.{fmt}"
                with open(output_file, "wb") as f:
                    f.write(response.content)
                
                file_size = os.path.getsize(output_file)
                print(f"Audio file saved with size: {file_size} bytes")
                
                # Basic format validation
                with open(output_file, "rb") as f:
                    header = f.read(16)
                    print(f"File header (hex): {header.hex()}")
                    
                    if fmt == "opus":
                        if header.startswith(b"OggS"):
                            print("✓ OPUS file has proper OGG container header")
                        else:
                            print("⚠ OPUS file doesn't start with OggS header")
                    elif fmt == "wav":
                        if header.startswith(b"RIFF") and b"WAVE" in header:
                            print("✓ WAV file has proper RIFF/WAVE header")
                        else:
                            print("⚠ WAV file doesn't have proper RIFF/WAVE header")
                
                results[fmt] = {"success": True, "size": file_size, "header": header.hex()}
                print(f"✓ {fmt.upper()} format test PASSED")
            else:
                print(f"Error response: {response.text}")
                results[fmt] = {"success": False, "error": response.text}
                print(f"✗ {fmt.upper()} format test FAILED")
        
        except Exception as e:
            print(f"Exception during {fmt} API call: {str(e)}")
            results[fmt] = {"success": False, "error": str(e)}
            print(f"✗ {fmt.upper()} format test FAILED")
    
    # Summary
    print("\n=== TEST SUMMARY ===")
    for fmt, result in results.items():
        if result["success"]:
            print(f"✓ {fmt.upper()}: SUCCESS ({result['size']} bytes)")
        else:
            print(f"✗ {fmt.upper()}: FAILED - {result.get('error', 'Unknown error')}")
    
    # Check if OPUS specifically works
    opus_works = results.get("opus", {}).get("success", False)
    if opus_works:
        print("\n🎉 OPUS format is supported by OpenAI TTS API!")
        print("Direct OPUS streaming should work without FFmpeg conversion.")
        return True
    else:
        print("\n❌ OPUS format is not supported by OpenAI TTS API.")
        print("FFmpeg conversion fallback will be needed.")
        return False

if __name__ == "__main__":
    success = test_openai_opus()
    sys.exit(0 if success else 1)