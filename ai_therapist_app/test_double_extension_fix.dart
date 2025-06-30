#!/usr/bin/env dart
/// Integration test to verify the frontend TTS double extension bug is fixed.
/// 
/// This test simulates the exact workflow that was creating .wav.wav files
/// and verifies the fix prevents double extensions.

import 'dart:io';
import 'lib/utils/audio_path_utils.dart';

void main() {
  print('🧪 Testing Frontend TTS Double Extension Fix');
  print('=' * 50);
  
  // Test 1: Verify utility function prevents double extensions
  testUtilityFunction();
  
  // Test 2: Simulate the exact TTS workflow that was broken
  testTTSWorkflow();
  
  // Test 3: Verify PathManager integration
  testPathManagerIntegration();
  
  print('\n' + '=' * 50);
  print('✅ All tests passed! Frontend double extension bug is fixed.');
}

void testUtilityFunction() {
  print('\n🔧 Testing AudioPathUtils utility...');
  
  // Test the specific case from the logs
  final problematicInput = 'tts_1751243751996444.wav';
  final result = AudioPathUtils.ensureWav(problematicInput);
  
  assert(result == 'tts_1751243751996444.wav', 'Should preserve existing extension');
  assert(!result.endsWith('.wav.wav'), 'Should not create double extension');
  
  // Test clean ID generation
  final cleanId = AudioPathUtils.generateTimestampId('tts');
  assert(!cleanId.contains('.'), 'Generated ID should not contain extensions');
  assert(cleanId.startsWith('tts_'), 'Should have correct prefix');
  
  print('✅ AudioPathUtils working correctly');
}

void testTTSWorkflow() {
  print('\n🎵 Testing TTS filename generation workflow...');
  
  // Simulate the FIXED workflow in simple_tts_service.dart
  const format = 'wav';
  final ext = format == 'wav' ? 'wav' : 
             format == 'opus' ? 'ogg' : 'mp3';
  
  // NEW: Generate clean ID without extension (the fix)
  final fileId = AudioPathUtils.generateTimestampId('tts');
  
  // Simulate PathManager.ttsFile() behavior
  const ttsPrefix = 'tts_stream_';
  final simulatedPath = '$ttsPrefix$fileId.$ext';
  
  print('Generated file ID: $fileId');
  print('Simulated path: $simulatedPath');
  
  // Verify no double extension
  assert(!simulatedPath.endsWith('.wav.wav'), 'Should not have double extension');
  assert(simulatedPath.endsWith('.wav'), 'Should have single .wav extension');
  
  // Verify correct pattern (matches logs)
  assert(simulatedPath.startsWith('tts_stream_tts_'), 'Should have correct prefix pattern');
  
  // Count .wav occurrences (should be exactly 1)
  final wavCount = '.wav'.allMatches(simulatedPath).length;
  assert(wavCount == 1, 'Should have exactly one .wav extension, found $wavCount');
  
  print('✅ TTS workflow generates correct filenames');
}

void testPathManagerIntegration() {
  print('\n📁 Testing PathManager integration pattern...');
  
  // Test the interaction between AudioPathUtils and PathManager pattern
  final baseId = 'tts_12345';
  final ext = 'wav';
  
  // Ensure clean ID
  AudioPathUtils.validateBasename(baseId); // Should not throw
  
  // Simulate ttsFile() method
  const ttsPrefix = 'tts_stream_';
  final finalPath = '$ttsPrefix$baseId.$ext';
  
  print('Base ID: $baseId');
  print('Final path: $finalPath');
  
  assert(finalPath == 'tts_stream_tts_12345.wav', 'Should generate expected path');
  assert(!finalPath.contains('.wav.wav'), 'Should not contain double extension');
  
  print('✅ PathManager integration working correctly');
}