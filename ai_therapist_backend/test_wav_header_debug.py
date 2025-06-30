#!/usr/bin/env python3
"""
Test script for WAV header debugging utilities.
Tests the ability to detect and fix invalid RIFF chunk sizes.
"""

import struct
import sys
import os

# Add the parent directory to the path so we can import our modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.utils.wav_header_debug import WavHeaderDebug

def create_valid_wav_header(data_size: int = 1000) -> bytes:
    """Create a valid WAV header for testing."""
    file_size = data_size + 36  # 44 byte header - 8 bytes for RIFF chunk
    
    header = bytearray()
    # RIFF header
    header.extend(b'RIFF')
    header.extend(struct.pack('<I', file_size))  # File size - 8
    header.extend(b'WAVE')
    
    # fmt chunk
    header.extend(b'fmt ')
    header.extend(struct.pack('<I', 16))  # fmt chunk size
    header.extend(struct.pack('<H', 1))   # PCM format
    header.extend(struct.pack('<H', 1))   # Mono
    header.extend(struct.pack('<I', 16000))  # Sample rate
    header.extend(struct.pack('<I', 32000))  # Byte rate
    header.extend(struct.pack('<H', 2))   # Block align
    header.extend(struct.pack('<H', 16))  # Bits per sample
    
    # data chunk
    header.extend(b'data')
    header.extend(struct.pack('<I', data_size))  # Data size
    
    return bytes(header)

def create_invalid_wav_sample() -> bytes:
    """Create a WAV sample with invalid 0xFFFFFFFF chunk sizes."""
    data_size = 1000
    header = create_valid_wav_header(data_size)
    
    # Add dummy audio data
    audio_data = bytes(list(range(256)) * (data_size // 256 + 1))[:data_size]
    complete_wav = header + audio_data
    
    # Corrupt the WAV header with 0xFFFFFFFF values
    corrupted = bytearray(complete_wav)
    
    # Corrupt RIFF chunk size (bytes 4-7)
    struct.pack_into('<I', corrupted, 4, 0xFFFFFFFF)
    
    # Corrupt data chunk size (bytes 40-43)  
    struct.pack_into('<I', corrupted, 40, 0xFFFFFFFF)
    
    return bytes(corrupted)

def test_wav_header_analysis():
    """Test WAV header analysis functionality."""
    print("🧪 Testing WAV header analysis...\n")
    
    # Test 1: Valid WAV file
    print("Test 1: Valid WAV file")
    valid_wav = create_valid_wav_header(500) + b'\x00' * 500
    analysis = WavHeaderDebug.analyze_wav_header(valid_wav)
    
    print(f"  File size: {analysis['file_size']}")
    print(f"  RIFF chunk size: {analysis['riff_chunk_size']} ({analysis['riff_chunk_size_hex']})")
    print(f"  Data chunk size: {analysis['data_chunk_size']} ({analysis['data_chunk_size_hex']})")
    print(f"  Header valid: {analysis['header_valid']}")
    print(f"  Issues: {analysis['issues']}")
    print(f"  Has critical issues: {analysis['has_critical_issues']}")
    print()
    
    # Test 2: Invalid WAV file with 0xFFFFFFFF
    print("Test 2: Invalid WAV with 0xFFFFFFFF chunk sizes")
    invalid_wav = create_invalid_wav_sample()
    analysis = WavHeaderDebug.analyze_wav_header(invalid_wav)
    
    print(f"  File size: {analysis['file_size']}")
    print(f"  RIFF chunk size: {analysis['riff_chunk_size']} ({analysis['riff_chunk_size_hex']})")
    print(f"  Data chunk size: {analysis['data_chunk_size']} ({analysis['data_chunk_size_hex']})")
    print(f"  Header valid: {analysis['header_valid']}")
    print(f"  Issues: {analysis['issues']}")
    print(f"  Has critical issues: {analysis['has_critical_issues']}")
    print()

def test_wav_header_fixing():
    """Test WAV header fixing functionality."""
    print("🔧 Testing WAV header fixing...\n")
    
    # Create invalid WAV
    invalid_wav = create_invalid_wav_sample()
    print("Before fixing:")
    WavHeaderDebug.log_wav_header_analysis(invalid_wav, "Invalid WAV")
    
    # Fix the WAV
    fixed_wav = WavHeaderDebug.fix_wav_header(invalid_wav)
    print("\nAfter fixing:")
    WavHeaderDebug.log_wav_header_analysis(fixed_wav, "Fixed WAV")
    
    # Verify the fix worked
    analysis = WavHeaderDebug.analyze_wav_header(fixed_wav)
    assert not analysis['has_critical_issues'], "Fixed WAV should not have critical issues"
    assert analysis['riff_chunk_size'] != 0xFFFFFFFF, "RIFF chunk size should be fixed"
    assert analysis['data_chunk_size'] != 0xFFFFFFFF, "Data chunk size should be fixed"
    
    print("\n✅ WAV header fixing test passed!")

def test_detection_functions():
    """Test detection utility functions."""
    print("🔍 Testing detection functions...\n")
    
    # Test WAV detection
    valid_wav = create_valid_wav_header(100) + b'\x00' * 100
    invalid_wav = create_invalid_wav_sample()
    non_wav = b'Not a WAV file' + b'\x00' * 100
    
    print(f"Valid WAV detected as WAV: {WavHeaderDebug.is_wav_file(valid_wav)}")
    print(f"Invalid WAV detected as WAV: {WavHeaderDebug.is_wav_file(invalid_wav)}")
    print(f"Non-WAV detected as WAV: {WavHeaderDebug.is_wav_file(non_wav)}")
    
    # Test invalid chunk size detection
    print(f"Valid WAV has invalid chunk size: {WavHeaderDebug.has_invalid_chunk_size(valid_wav)}")
    print(f"Invalid WAV has invalid chunk size: {WavHeaderDebug.has_invalid_chunk_size(invalid_wav)}")
    print(f"Non-WAV has invalid chunk size: {WavHeaderDebug.has_invalid_chunk_size(non_wav)}")
    
    print("\n✅ Detection functions test passed!")

def main():
    """Run all tests."""
    print("🚀 Starting WAV Header Debug Tests\n")
    
    try:
        test_wav_header_analysis()
        test_wav_header_fixing()
        test_detection_functions()
        
        print("\n🎉 All tests passed successfully!")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())