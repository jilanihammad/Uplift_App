#!/usr/bin/env python3
"""
Test script for AI Therapist backend audio optimization.
This script makes requests to the backend to verify the audio format changes.
"""

import requests
import json
import os
import time
import sys

# Configuration
BASE_URL = "https://ai-therapist-backend-385290373302.us-central1.run.app"  # Replace with your backend URL
TEST_DIR = "test_results"

def ensure_test_dir():
    """Create test directory if it doesn't exist"""
    if not os.path.exists(TEST_DIR):
        os.makedirs(TEST_DIR)

def test_tts_request(text, params, filename):
    """Make a TTS request and save the result"""
    print(f"\nTesting TTS with params: {params}")
    print(f"Text: '{text}'")
    
    # Prepare request body
    data = {
        "text": text,
        **params
    }
    
    # Make the request
    try:
        start_time = time.time()
        response = requests.post(
            f"{BASE_URL}/voice/synthesize",
            json=data,
            headers={"Content-Type": "application/json"}
        )
        request_time = time.time() - start_time
        
        # Process response
        if response.status_code == 200:
            try:
                result = response.json()
                audio_url = result.get("url")
                
                if audio_url:
                    # Download the audio file
                    download_start = time.time()
                    audio_response = requests.get(f"{BASE_URL}{audio_url}")
                    download_time = time.time() - download_start
                    
                    if audio_response.status_code == 200:
                        # Save the audio file
                        extension = ".ogg" if params.get("format", "") in ["ogg_opus", "opus"] else ".mp3"
                        file_path = os.path.join(TEST_DIR, f"{filename}{extension}")
                        
                        with open(file_path, "wb") as f:
                            f.write(audio_response.content)
                        
                        # Print results
                        file_size = len(audio_response.content)
                        print(f"✓ Success! Audio file saved to {file_path}")
                        print(f"  Request time: {request_time:.2f}s")
                        print(f"  Download time: {download_time:.2f}s")
                        print(f"  File size: {file_size/1024:.2f} KB")
                        return {
                            "success": True,
                            "file_size": file_size,
                            "request_time": request_time,
                            "download_time": download_time,
                            "file_path": file_path
                        }
                    else:
                        print(f"✗ Failed to download audio file: {audio_response.status_code}")
                else:
                    print(f"✗ No audio URL in response: {result}")
            except Exception as e:
                print(f"✗ Error processing response: {str(e)}")
        else:
            print(f"✗ Request failed with status code: {response.status_code}")
            print(f"  Response: {response.text}")
            
    except Exception as e:
        print(f"✗ Request error: {str(e)}")
    
    return {"success": False}

def compare_results(results):
    """Compare the results of different tests"""
    if len(results) < 2:
        print("\nNot enough successful tests to compare results")
        return
    
    print("\n----- COMPARISON RESULTS -----")
    
    # Find the MP3 result to use as baseline
    mp3_result = next((r for r in results if r["params"].get("format") == "mp3" or r["params"].get("format") is None), None)
    
    if not mp3_result:
        print("No MP3 test to use as baseline for comparison")
        return
    
    mp3_size = mp3_result["result"]["file_size"]
    mp3_time = mp3_result["result"]["request_time"] + mp3_result["result"]["download_time"]
    
    print(f"\nBaseline (MP3): {mp3_size/1024:.2f} KB, {mp3_time:.2f}s total time")
    
    for test in results:
        if test["name"] == mp3_result["name"]:
            continue
            
        format_name = test["params"].get("format", "default")
        size = test["result"]["file_size"]
        time_total = test["result"]["request_time"] + test["result"]["download_time"]
        
        size_reduction = (1 - (size / mp3_size)) * 100
        time_reduction = (1 - (time_total / mp3_time)) * 100
        
        print(f"\n{test['name']}:")
        print(f"  Format: {format_name}")
        print(f"  File size: {size/1024:.2f} KB ({size_reduction:.1f}% smaller than MP3)")
        print(f"  Total time: {time_total:.2f}s ({time_reduction:.1f}% faster than MP3)")

def main():
    """Run the TTS tests"""
    ensure_test_dir()
    
    print("=== AI Therapist Backend Audio Optimization Test ===")
    print(f"Using backend URL: {BASE_URL}")
    
    # Test text
    text = "This is a test of the AI therapist voice generation system with optimized audio settings. How does this sound compared to the original format?"
    
    # Tests to run
    tests = [
        {
            "name": "MP3 Format (Baseline)",
            "params": {"voice": "sage", "format": "mp3"},
            "filename": "test_mp3"
        },
        {
            "name": "Opus Format (Default Settings)",
            "params": {"voice": "sage", "format": "ogg_opus"},
            "filename": "test_opus_default"
        },
        {
            "name": "Opus Format (Higher Bitrate)",
            "params": {"voice": "sage", "format": "ogg_opus", "bitrate": "32k"},
            "filename": "test_opus_32k"
        },
        {
            "name": "Opus Format (Lower Bitrate)",
            "params": {"voice": "sage", "format": "ogg_opus", "bitrate": "16k"},
            "filename": "test_opus_16k"
        }
    ]
    
    successful_results = []
    
    # Run each test
    for test in tests:
        result = test_tts_request(text, test["params"], test["filename"])
        if result["success"]:
            successful_results.append({
                "name": test["name"],
                "params": test["params"],
                "result": result
            })
    
    # Compare results
    if successful_results:
        compare_results(successful_results)
    else:
        print("\nNo successful tests to compare")

if __name__ == "__main__":
    main() 