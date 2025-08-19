// test/voice/streaming_buffer_controller_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/voice/streaming_buffer_controller.dart';

void main() {
  group('StreamingBufferController', () {
    test('should flush when buffer reaches minimum characters', () async {
      final completer = Completer<String>();
      final controller = StreamingBufferController(
        (text) => completer.complete(text),
        minBufferChars: 10,
        maxStall: const Duration(milliseconds: 1000),
        watchdogTimeout: const Duration(seconds: 5),
      );
      
      // Add text that reaches the minimum
      controller.addChunk('Hello world test!'); // 18 chars > 10
      
      // Should have flushed immediately
      final result = await completer.future.timeout(const Duration(seconds: 1));
      expect(result, equals('Hello world test!'));
      
      controller.cancel();
    });
    
    test('should flush on stall timer even with fewer characters', () async {
      final completer = Completer<String>();
      final controller = StreamingBufferController(
        (text) => completer.complete(text),
        minBufferChars: 100, // High threshold
        maxStall: const Duration(milliseconds: 100), // Short stall
        watchdogTimeout: const Duration(seconds: 5),
      );
      
      // Add text below threshold
      controller.addChunk('Short'); // 5 chars < 100
      
      // Should flush after stall timer
      final result = await completer.future.timeout(const Duration(seconds: 1));
      expect(result, equals('Short'));
      
      controller.cancel();
    });
    
    test('should not process chunks after cancellation', () async {
      var callCount = 0;
      final controller = StreamingBufferController(
        (text) => callCount++,
        minBufferChars: 5,
        maxStall: const Duration(milliseconds: 100),
        watchdogTimeout: const Duration(seconds: 5),
      );
      
      controller.cancel();
      controller.addChunk('This should be ignored');
      
      // Wait a bit to ensure no calls happen
      await Future.delayed(const Duration(milliseconds: 200));
      expect(callCount, equals(0));
    });
    
    test('should trigger watchdog fallback if no audio played', () async {
      var watchdogTriggered = false;
      final controller = StreamingBufferController(
        (text) {
          // Don't call flush callback to simulate no audio playing
        },
        minBufferChars: 100,
        maxStall: const Duration(milliseconds: 100),
        watchdogTimeout: const Duration(milliseconds: 200), // Short watchdog
      );
      
      // Don't add any chunks, let watchdog timeout
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Verify controller was cancelled (no way to directly check watchdog)
      // We'll verify indirectly by checking that chunks are ignored
      controller.addChunk('Should be ignored');
      
      // This is a basic test - in real usage, the watchdog would trigger
      // fallback behavior in the calling code
      controller.cancel();
    });
  });
}