#\!/usr/bin/env python3
"""
Integration test to verify no .wav.wav files are created in the TTS pipeline.
"""

import os
import sys
import tempfile
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from app.utils.audio_path import ensure_wav, ensure_basename_no_extension


def test_double_extension_prevention():
    """Test that the double extension bug is fixed."""
    print("Testing double extension prevention...")
    
    # The specific case from the bug report
    problematic = "tts_stream_tts_1751231363434044"
    result = ensure_wav(problematic)
    
    print(f"Input: {problematic}")
    print(f"Output: {result}")
    
    # Verify correct extension
    expected = "tts_stream_tts_1751231363434044.wav"
    assert result == expected, f"Expected {expected}, got {result}"
    
    # Verify no double extension
    assert not result.endswith('.wav.wav'), f"Double extension created: {result}"
    
    # Test double application (the bug scenario)
    double_applied = ensure_wav(result)
    assert double_applied == result, "Double application should be idempotent"
    
    print("✅ Double extension bug is fixed\!")
    return True


def test_file_creation():
    """Test actual file creation doesn't create .wav.wav files."""
    print("\nTesting file creation...")
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Create files using ensure_wav
        test_files = ["audio", "recording", "tts_12345"]
        
        for base_name in test_files:
            file_path = ensure_wav(os.path.join(temp_dir, base_name))
            
            # Create the file
            with open(file_path, 'w') as f:
                f.write("test")
                
            print(f"Created: {os.path.basename(file_path)}")
        
        # Check for .wav.wav files (CI gate pattern)
        double_wav_files = []
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                if file.endswith('.wav.wav'):
                    double_wav_files.append(file)
        
        if double_wav_files:
            print(f"❌ Found .wav.wav files: {double_wav_files}")
            return False
        
        print("✅ No .wav.wav files found\!")
        return True


if __name__ == "__main__":
    print("=" * 50)
    print("VERIFYING TTS DOUBLE EXTENSION FIX")
    print("=" * 50)
    
    success1 = test_double_extension_prevention()
    success2 = test_file_creation()
    
    print("\n" + "=" * 50)
    if success1 and success2:
        print("🎉 ALL TESTS PASSED\!")
        print("The double extension bug is fixed.")
        sys.exit(0)
    else:
        print("❌ Some tests failed.")
        sys.exit(1)
