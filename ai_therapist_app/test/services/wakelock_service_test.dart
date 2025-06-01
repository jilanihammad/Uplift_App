import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/services/wakelock_service.dart';

void main() {
  group('WakelockService', () {
    tearDown(() async {
      // Clean up after each test
      await WakelockService.disable();
    });

    test('should enable wakelock successfully', () async {
      await WakelockService.enable();
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isTrue);
    });

    test('should disable wakelock successfully', () async {
      await WakelockService.enable();
      await WakelockService.disable();
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isFalse);
    });

    test('should handle multiple enable calls gracefully', () async {
      await WakelockService.enable();
      await WakelockService.enable(); // Should not throw
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isTrue);
    });

    test('should handle multiple disable calls gracefully', () async {
      await WakelockService.enable();
      await WakelockService.disable();
      await WakelockService.disable(); // Should not throw
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isFalse);
    });

    test('should handle disable when never enabled', () async {
      // Should not throw an error
      await WakelockService.disable();
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isFalse);
    });
  });
}
