// test_wav_header_fix.dart
// Test script to validate WAV header validation and fixing functionality

import 'dart:io';
import 'dart:typed_data';
import 'lib/utils/wav_header_utils.dart';

void main() async {
  print('🧪 Testing WAV Header Validation and Fixing\n');
  
  // Test 1: Create a sample WAV with invalid chunk size
  print('Test 1: Creating WAV with invalid 0xFFFFFFFF chunk size...');
  final invalidWav = createInvalidWavSample();
  
  print('Original header analysis:');
  WavHeaderUtils.logWavHeaderDetails(invalidWav, 'Invalid WAV');
  
  // Test 2: Fix the invalid WAV
  print('\nTest 2: Fixing invalid WAV header...');
  final fixedWav = WavHeaderUtils.validateAndFixWavHeader(invalidWav);
  
  print('Fixed header analysis:');
  WavHeaderUtils.logWavHeaderDetails(fixedWav, 'Fixed WAV');
  
  // Test 3: Test with valid WAV (should remain unchanged)
  print('\nTest 3: Testing with valid WAV (should remain unchanged)...');
  final validWav = createValidWavSample();
  
  print('Valid WAV original:');
  WavHeaderUtils.logWavHeaderDetails(validWav, 'Valid Original');
  
  final unchangedWav = WavHeaderUtils.validateAndFixWavHeader(validWav);
  final isUnchanged = listEquals(validWav, unchangedWav);
  print('Valid WAV after processing (unchanged: $isUnchanged):');
  WavHeaderUtils.logWavHeaderDetails(unchangedWav, 'Valid After Processing');
  
  // Test 4: Test with too-short data
  print('\nTest 4: Testing with too-short audio data...');
  final shortData = [1, 2, 3, 4, 5];
  final shortResult = WavHeaderUtils.validateAndFixWavHeader(shortData);
  print('Short data unchanged: ${listEquals(shortData, shortResult)}');
  
  // Test 5: Test with non-WAV data
  print('\nTest 5: Testing with non-WAV data...');
  final nonWavData = List.generate(100, (i) => i % 256);
  final nonWavResult = WavHeaderUtils.validateAndFixWavHeader(nonWavData);
  print('Non-WAV data unchanged: ${listEquals(nonWavData, nonWavResult)}');
  
  print('\n✅ All tests completed!');
}

/// Creates a WAV sample with invalid 0xFFFFFFFF chunk size
List<int> createInvalidWavSample() {
  final audioData = List.generate(1000, (i) => (i % 256)); // Dummy audio data
  final header = WavHeaderUtils.createWavHeader(dataSize: audioData.length);
  
  // Combine header and audio data
  final wavData = [...header, ...audioData];
  
  // Corrupt the RIFF chunk size (bytes 4-7) to 0xFFFFFFFF
  wavData[4] = 0xFF;
  wavData[5] = 0xFF;
  wavData[6] = 0xFF;
  wavData[7] = 0xFF;
  
  // Also corrupt the data chunk size (bytes 40-43) to 0xFFFFFFFF
  wavData[40] = 0xFF;
  wavData[41] = 0xFF;
  wavData[42] = 0xFF;
  wavData[43] = 0xFF;
  
  return wavData;
}

/// Creates a valid WAV sample
List<int> createValidWavSample() {
  final audioData = List.generate(500, (i) => (i % 256)); // Dummy audio data
  final header = WavHeaderUtils.createWavHeader(dataSize: audioData.length);
  
  return [...header, ...audioData];
}

/// Utility function to compare two lists
bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}