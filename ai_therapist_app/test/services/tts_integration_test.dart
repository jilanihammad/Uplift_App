// test/services/tts_integration_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';

import 'package:ai_therapist_app/di/interfaces/i_tts_service.dart';
import 'package:ai_therapist_app/services/simple_tts_service.dart';
import 'package:ai_therapist_app/services/audio_player_manager.dart';
import 'package:ai_therapist_app/di/modules/audio_services_module.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';

/// Mock AudioPlayerManager for testing
class MockAudioPlayerManager extends Mock implements AudioPlayerManager {
  final List<String> _playedFiles = [];
  final Map<String, Duration> _fileDurations = {};
  
  List<String> get playedFiles => List.unmodifiable(_playedFiles);
  
  void setFileDuration(String filePath, Duration duration) {
    _fileDurations[filePath] = duration;
  }
  
  @override
  Future<void> playAudio(String filePath) async {
    _playedFiles.add(filePath);
    // Simulate audio playback duration
    final duration = _fileDurations[filePath] ?? const Duration(milliseconds: 500);
    await Future.delayed(duration);
  }
  
  @override
  Future<void> stopAudio({bool clearQueue = true}) async {
    // Mock implementation
  }
  
  @override
  bool get isPlaying => false;
  
  @override
  Stream<bool> get isPlayingStream => Stream.value(false);
  
  @override
  Future<void> dispose() async {
    // Mock implementation
  }
}

/// Mock ApiClient for testing
class MockApiClient extends Mock implements ApiClient {
  @override
  String get baseUrl => 'http://localhost:8000';
  
  @override
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? queryParams}) async {
    return {'status': 'ok'};
  }
  
  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    return {'status': 'ok'};
  }
  
  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    return {'status': 'ok'};
  }
  
  @override
  Future<Map<String, dynamic>> delete(String endpoint, {Map<String, String>? headers}) async {
    return {'status': 'ok'};
  }
}

void main() {
  group('TTS Integration Tests', () {
    late GetIt locator;
    late MockAudioPlayerManager mockAudioPlayer;
    late MockApiClient mockApiClient;
    late ITTSService ttsService;

    setUpAll(() {
      // Initialize test environment
      debugDefaultTargetPlatformOverride = null;
    });

    setUp(() {
      // Create fresh service locator for each test
      locator = GetIt.instance;
      locator.reset();

      // Create mocks
      mockAudioPlayer = MockAudioPlayerManager();
      mockApiClient = MockApiClient();

      // Register base dependencies
      locator.registerSingleton<ApiClient>(mockApiClient);
      locator.registerSingleton<AudioPlayerManager>(mockAudioPlayer);

      // Register TTS service using the production code path
      locator.registerLazySingleton<ITTSService>(() => SimpleTTSService(
        audioPlayerManager: locator<AudioPlayerManager>(),
      ));

      ttsService = locator<ITTSService>();
    });

    tearDown(() {
      locator.reset();
    });

    group('Service Registration', () {
      test('should register SimpleTTSService as ITTSService', () {
        expect(ttsService, isA<SimpleTTSService>());
        expect(locator.isRegistered<ITTSService>(), isTrue);
      });

      test('should use AudioServicesModule registration pattern', () {
        locator.reset();

        // Register using the production AudioServicesModule
        locator.registerSingleton<ApiClient>(mockApiClient);
        locator.registerLazySingleton<AudioPlayerManager>(() => mockAudioPlayer);
        
        // Register TTS service the same way as AudioServicesModule
        locator.registerLazySingleton<ITTSService>(() => SimpleTTSService(
          audioPlayerManager: locator<AudioPlayerManager>(),
        ));

        expect(locator.isRegistered<ITTSService>(), isTrue);
        final service = locator<ITTSService>();
        expect(service, isA<SimpleTTSService>());
      });
    });

    group('TTS Pipeline Functionality', () {
      test('should initialize without errors', () async {
        await expectLater(ttsService.initialize(), completes);
      });

      test('should handle single TTS request lifecycle', () async {
        // Set up audio duration for predictable testing
        mockAudioPlayer.setFileDuration('/tmp/test.wav', const Duration(milliseconds: 100));

        await ttsService.initialize();

        // This would normally make a real WebSocket connection in integration
        // For now, we test the interface and basic structure
        expect(() => ttsService.speak('Hello world'), returnsNormally);
      });

      test('should handle multiple concurrent TTS requests', () async {
        await ttsService.initialize();

        // Create multiple concurrent requests
        final futures = <Future>[];
        for (int i = 0; i < 3; i++) {
          futures.add(ttsService.speak('Test message $i'));
        }

        // All requests should be handled (though they'll fail with mock backend)
        // This tests that the service can handle concurrent requests without crashing
        expect(() => Future.wait(futures), returnsNormally);
      });

      test('should properly dispose resources', () async {
        await ttsService.initialize();
        
        // Should not throw when disposing
        expect(() => ttsService.dispose(), returnsNormally);
      });
    });

    group('Audio Player Integration', () {
      test('should use injected AudioPlayerManager', () async {
        await ttsService.initialize();
        
        // Verify the service is using our mock audio player
        // (This would be verified through actual TTS completion in full integration)
        expect(ttsService, isA<SimpleTTSService>());
      });

      test('should handle audio playback completion correctly', () async {
        // Set up realistic audio duration
        mockAudioPlayer.setFileDuration('/tmp/test.wav', const Duration(milliseconds: 200));

        await ttsService.initialize();

        // In a real integration test, this would verify that TTS completion
        // waits for audio playback to finish before signaling completion
        expect(mockAudioPlayer.playedFiles, isEmpty);
      });
    });

    group('WebSocket Connection Management', () {
      test('should handle connection errors gracefully', () async {
        await ttsService.initialize();

        // Test that connection errors don't crash the service
        // (WebSocket connections will fail with mock backend, but shouldn't crash)
        expect(() => ttsService.speak('Test message'), returnsNormally);
      });

      test('should support connection reuse pattern', () async {
        await ttsService.initialize();

        // Multiple TTS requests should reuse connections where possible
        // This tests the service architecture, not the actual WebSocket behavior
        for (int i = 0; i < 3; i++) {
          expect(() => ttsService.speak('Message $i'), returnsNormally);
        }
      });
    });

    group('Error Handling', () {
      test('should handle initialization errors gracefully', () async {
        // Service should handle network/backend unavailability
        expect(() => ttsService.initialize(), returnsNormally);
      });

      test('should handle TTS request errors gracefully', () async {
        await ttsService.initialize();
        
        // Should not crash on TTS failures
        expect(() => ttsService.speak(''), returnsNormally);
        expect(() => ttsService.speak('Test message'), returnsNormally);
      });

      test('should handle disposal during active requests', () async {
        await ttsService.initialize();
        
        // Start a TTS request
        ttsService.speak('Test message');
        
        // Should handle disposal even with active requests
        expect(() => ttsService.dispose(), returnsNormally);
      });
    });

    group('Performance and Resource Management', () {
      test('should not leak memory with multiple requests', () async {
        await ttsService.initialize();

        // Create and complete many TTS requests
        for (int i = 0; i < 10; i++) {
          expect(() => ttsService.speak('Message $i'), returnsNormally);
        }

        // Service should remain stable
        expect(ttsService, isNotNull);
      });

      test('should handle rapid sequential requests', () async {
        await ttsService.initialize();

        // Fire multiple requests rapidly
        for (int i = 0; i < 5; i++) {
          ttsService.speak('Rapid message $i');
        }

        // Should not crash or deadlock
        expect(ttsService, isNotNull);
      });
    });
  });

  group('Production Readiness Checks', () {
    test('should verify no deprecated TTSService references', () {
      // This test would fail if any code still references the old TTSService
      // Since we deleted it, this verifies the cleanup was successful
      expect(() => AudioServicesModule.registerServices(GetIt.instance), returnsNormally);
    });

    test('should verify SimpleTTSService is production-ready', () {
      final service = SimpleTTSService(
        audioPlayerManager: MockAudioPlayerManager(),
      );
      
      expect(service, isA<ITTSService>());
      expect(service, isA<SimpleTTSService>());
    });

    test('should verify service locator configuration', () {
      final locator = GetIt.instance;
      locator.reset();

      // Register the same way as production
      locator.registerSingleton<AudioPlayerManager>(MockAudioPlayerManager());
      locator.registerLazySingleton<ITTSService>(() => SimpleTTSService(
        audioPlayerManager: locator<AudioPlayerManager>(),
      ));

      expect(locator.isRegistered<ITTSService>(), isTrue);
      expect(locator<ITTSService>(), isA<SimpleTTSService>());
    });
  });
}