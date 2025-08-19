// test/utils/feature_flags_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_therapist_app/utils/feature_flags.dart';

void main() {
  group('FeatureFlags TTS Streaming', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      await FeatureFlags.init();
    });

    test('should default incremental TTS to false', () {
      expect(FeatureFlags.useIncrementalTts, isFalse);
    });

    test('should be able to enable incremental TTS', () async {
      await FeatureFlags.setEnabled(FeatureFlags.enableIncrementalTts, true);
      expect(FeatureFlags.useIncrementalTts, isTrue);
    });

    test('should be able to toggle incremental TTS', () async {
      // Start with default (false)
      expect(FeatureFlags.useIncrementalTts, isFalse);
      
      // Toggle to true
      await FeatureFlags.toggleIncrementalTts();
      expect(FeatureFlags.useIncrementalTts, isTrue);
      
      // Toggle back to false
      await FeatureFlags.toggleIncrementalTts();
      expect(FeatureFlags.useIncrementalTts, isFalse);
    });

    test('should persist incremental TTS setting', () async {
      // Enable the flag
      await FeatureFlags.setEnabled(FeatureFlags.enableIncrementalTts, true);
      expect(FeatureFlags.useIncrementalTts, isTrue);
      
      // Simulate app restart by re-initializing
      await FeatureFlags.init();
      expect(FeatureFlags.useIncrementalTts, isTrue);
    });

    test('should reset incremental TTS to default', () async {
      // Enable the flag
      await FeatureFlags.setEnabled(FeatureFlags.enableIncrementalTts, true);
      expect(FeatureFlags.useIncrementalTts, isTrue);
      
      // Reset to defaults
      await FeatureFlags.resetToDefaults();
      expect(FeatureFlags.useIncrementalTts, isFalse);
    });
  });
}