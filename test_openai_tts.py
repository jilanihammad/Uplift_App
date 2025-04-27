#!/usr/bin/env python
import requests
import os
import time

def test_openai_tts():
    print("Testing OpenAI TTS API...")
    
    # Get API key from environment
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("Error: OPENAI_API_KEY environment variable not set")
        return False
        
    tts_model = "gpt-4o-mini-tts"
    voice = "sage"
    text = "This is a test of the OpenAI TTS system."
    
    print(f"Using model: {tts_model}")
    print(f"Using voice: {voice}")
    print(f"API key available: {'Yes' if api_key else 'No'}")
    
    # OpenAI API URL
    url = "https://api.openai.com/v1/audio/speech"
    
    # Request headers
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    
    # Request payload
    payload = {
        "model": tts_model,
        "input": text,
        "voice": voice
    }
    
    print("Sending request to OpenAI API...")
    
    # Make the API call
    try:
        response = requests.post(url, headers=headers, json=payload)
        
        if response.status_code == 200:
            # Save the audio file
            filename = f"test_output_{int(time.time())}.mp3"
            with open(filename, "wb") as f:
                f.write(response.content)
                
            file_size = os.path.getsize(filename)
            print("Success! Saving audio file...")
            print(f"Audio file saved as: {filename}")
            print(f"Audio file saved with size: {file_size} bytes")
            return True
        else:
            print(f"Error: API call failed with status code {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return False

if __name__ == "__main__":
    test_openai_tts() 