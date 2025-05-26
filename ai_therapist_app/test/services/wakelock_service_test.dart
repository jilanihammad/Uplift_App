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

    test('should refresh wakelock when enabled', () async {
      await WakelockService.enable();
      await WakelockService.refresh();
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isTrue);
    });

    test('should handle refresh when disabled', () async {
      await WakelockService.disable();
      // Should not throw an error
      await WakelockService.refresh();
      final isEnabled = await WakelockService.isEnabled;
      expect(isEnabled, isFalse);
    });
  });
}
