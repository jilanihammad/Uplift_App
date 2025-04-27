#!/usr/bin/env python
import requests
import os

def test_openai_tts():
    print("Testing OpenAI TTS API...")
    
    api_key = "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"
    tts_model = "gpt-4o-mini-tts"
    voice = "sage"
    test_text = "This is a test of the OpenAI text to speech API."
    
    print(f"Using model: {tts_model}")
    print(f"Using voice: {voice}")
    print(f"API key (first/last 5 chars): {api_key[:5]}...{api_key[-5:]}")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    data = {
        "model": tts_model,
        "input": test_text,
        "voice": voice,
        "response_format": "mp3"
    }
    
    url = "https://api.openai.com/v1/audio/speech"
    
    try:
        print("Sending request to OpenAI API...")
        response = requests.post(
            url,
            json=data,
            headers=headers,
            timeout=30
        )
        
        print(f"Response status code: {response.status_code}")
        
        if response.status_code == 200:
            print("Success! Saving audio file...")
            with open("test_output.mp3", "wb") as f:
                f.write(response.content)
            
            file_size = os.path.getsize("test_output.mp3")
            print(f"Audio file saved with size: {file_size} bytes")
            print("Test PASSED ✓")
            return True
        else:
            print(f"Error response: {response.text}")
            print("Test FAILED ✗")
            return False
    
    except Exception as e:
        print(f"Exception during API call: {str(e)}")
        print("Test FAILED ✗")
        return False

if __name__ == "__main__":
    test_openai_tts() 