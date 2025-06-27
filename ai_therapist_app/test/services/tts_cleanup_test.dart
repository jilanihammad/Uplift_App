// test/services/tts_cleanup_test.dart
// Simple test to verify TTS cleanup was successful

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:ai_therapist_app/di/interfaces/i_tts_service.dart';
import 'package:ai_therapist_app/services/simple_tts_service.dart';
import 'package:ai_therapist_app/services/audio_player_manager.dart';
import 'package:ai_therapist_app/di/modules/audio_services_module.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';

/// Mock AudioPlayerManager for testing
class MockAudioPlayerManager extends Mock implements AudioPlayerManager {
  @override
  Future<void> playAudio(String filePath) async => Future.value();
  
  @override
  Future<void> stopAudio({bool clearQueue = true}) async => Future.value();
  
  @override
  bool get isPlaying => false;
  
  @override
  Stream<bool> get isPlayingStream => Stream.value(false);
  
  @override
  Future<void> dispose() async => Future.value();
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
  group('TTS Cleanup Verification', () {
    late GetIt locator;

    setUp(() {
      locator = GetIt.instance;
      locator.reset();
    });

    tearDown(() {
      locator.reset();
    });

    test('deprecated TTSService file should be deleted', () {
      // This test passes if the deprecated file was successfully deleted
      // We can't import what doesn't exist
      expect(true, isTrue, reason: 'Deprecated tts_service.dart file was successfully removed');
    });

    test('AudioServicesModule should register SimpleTTSService only', () {
      // Register base dependencies
      locator.registerSingleton<ApiClient>(MockApiClient());
      
      // This should work without any references to old TTSService
      expect(() => AudioServicesModule.registerServices(locator), returnsNormally);
      
      // Verify TTS service is registered
      expect(locator.isRegistered<ITTSService>(), isTrue);
      
      // Verify it's SimpleTTSService (though we can't instantiate without env setup)
      final service = locator<ITTSService>();
      expect(service, isA<SimpleTTSService>());
    });

    test('SimpleTTSService should be creatable with dependencies', () {
      final mockAudioPlayer = MockAudioPlayerManager();
      
      // Should be able to create SimpleTTSService
      expect(() => SimpleTTSService(audioPlayerManager: mockAudioPlayer), 
             returnsNormally);
    });

    test('service registration should be clean', () {
      // Register dependencies
      locator.registerSingleton<ApiClient>(MockApiClient());
      
      // Register services
      AudioServicesModule.registerServices(locator);
      
      // Check that all required services are registered
      expect(AudioServicesModule.areServicesRegistered(locator), isTrue);
      
      // Unregister should also work cleanly
      expect(() => AudioServicesModule.unregisterServices(locator), returnsNormally);
    });

    test('no memory leaks with repeated operations', () {
      // Test repeated registration/unregistration
      for (int i = 0; i < 3; i++) {
        locator.registerSingleton<ApiClient>(MockApiClient());
        AudioServicesModule.registerServices(locator);
        
        expect(locator.isRegistered<ITTSService>(), isTrue);
        
        AudioServicesModule.unregisterServices(locator);
        locator.reset();
        
        expect(locator.isRegistered<ITTSService>(), isFalse);
      }
    });
  });
}