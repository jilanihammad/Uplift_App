import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_therapist_app/blocs/helpers/lifecycle_disable_manager.dart';

void main() {
  group('LifecycleDisableManager', () {
    late LifecycleDisableManager manager;

    setUp(() {
      manager = LifecycleDisableManager();
    });

    test('coalesces concurrent callers and waits for completion', () async {
      var callCount = 0;
      final disableCompleter = Completer<void>();

      final firstFuture = manager.ensure('pause', () async {
        callCount++;
        await disableCompleter.future;
      });

      expect(callCount, 1);

      final secondFuture = manager.ensure('hidden', () async {
        callCount++;
      });

      expect(callCount, 1, reason: 'second caller should reuse pending future');
      expect(identical(firstFuture, secondFuture), isTrue);

      disableCompleter.complete();
      await firstFuture;
      expect(callCount, 1);

      // Subsequent ensure should start a fresh disable run
      final thirdFuture = manager.ensure('resume', () async {
        callCount++;
      });

      await thirdFuture;
      expect(callCount, 2);
    });

    test('propagates errors and clears pending state', () async {
      await expectLater(
        manager.ensure('pause', () async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      // Next call should execute because pending was cleared after the error
      var ran = false;
      await manager.ensure('pause', () async {
        ran = true;
      });

      expect(ran, isTrue);
    });
  });
}
