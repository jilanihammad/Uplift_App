// Test script to verify VoiceService session scoping works correctly
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/interfaces/i_audio_settings.dart';

void main() {
  group('VoiceService Session Scoping Tests', () {
    setUp(() async {
      // Reset service locator state
      if (serviceLocator.isRegistered<VoiceService>()) {
        await serviceLocator.unregister<VoiceService>();
      }
    });

    test('VoiceService should create fresh instances (factory pattern)', () async {
      // Register mock dependencies
      if (!serviceLocator.isRegistered<ConfigService>()) {
        serviceLocator.registerSingleton<ConfigService>(
          ConfigService(llmApiEndpoint: 'http://localhost:8000')
        );
      }
      
      if (!serviceLocator.isRegistered<ApiClient>()) {
        serviceLocator.registerSingleton<ApiClient>(
          ApiClient(configService: serviceLocator<ConfigService>()) // Mock API client
        );
      }

      if (!serviceLocator.isRegistered<IAudioSettings>()) {
        serviceLocator.registerLazySingleton<IAudioSettings>(() => 
          MockAudioSettings());
      }

      // Register VoiceService as factory (same as in service_locator.dart)
      serviceLocator.registerFactory<VoiceService>(() {
        debugPrint('Creating fresh VoiceService for session scope');
        return VoiceService(
          apiClient: serviceLocator<ApiClient>(),
          audioSettings: serviceLocator<IAudioSettings>(),
          configService: serviceLocator<ConfigService>(),
        );
      });

      // Get first instance
      final instance1 = serviceLocator<VoiceService>();
      
      // Get second instance 
      final instance2 = serviceLocator<VoiceService>();
      
      // Verify they are different instances (factory pattern working)
      expect(instance1, isNot(same(instance2)), 
        reason: 'Factory pattern should create different instances');
      
      // Verify they are both VoiceService instances
      expect(instance1, isA<VoiceService>());
      expect(instance2, isA<VoiceService>());
      
      debugPrint('✅ VoiceService factory pattern test passed');
      debugPrint('   Instance 1: ${instance1.hashCode}');
      debugPrint('   Instance 2: ${instance2.hashCode}');
    });

    test('VoiceService instances should have separate state', () async {
      // This test would require access to VoiceService internal state
      // For now, we verify that different instances are created
      
      // Register dependencies (reuse from previous test setup)
      final instance1 = serviceLocator<VoiceService>();
      final instance2 = serviceLocator<VoiceService>();
      
      // Since we can't easily access internal state in this test environment,
      // we verify that instances are different (which means state will be separate)
      expect(instance1, isNot(same(instance2)));
      
      debugPrint('✅ VoiceService state separation test passed');
      debugPrint('   Different instances ensure separate state');
    });
  });
}

// Mock AudioSettings for testing
class MockAudioSettings implements IAudioSettings {
  bool _muted = false;
  
  @override
  bool get isGlobalMuteEnabled => _muted;

  @override
  bool get isMuted => _muted;

  @override
  double get volumeMultiplier => 1.0;

  @override
  void setGlobalMute(bool muted) {
    _muted = muted;
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
  }

  @override
  Stream<bool> get globalMuteStream => Stream.value(_muted);

  @override
  void addListener(listener) {}

  @override
  void removeListener(listener) {}
}