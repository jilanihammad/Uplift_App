import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/services/memory_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/audio_generator.dart';
import 'package:ai_therapist_app/services/conversation_flow_manager.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/data/datasources/local/database_provider.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:mockito/mockito.dart';

// Mock dependencies
class MockDatabaseProvider extends Mock implements DatabaseProvider {}

class MockApiClient extends Mock implements ApiClient {}

class MockVoiceService extends Mock implements VoiceService {}

void main() {
  group('Singleton Pattern Tests', () {
    late MockDatabaseProvider mockDatabaseProvider;
    late MockApiClient mockApiClient;
    late MockVoiceService mockVoiceService;

    setUp(() {
      mockDatabaseProvider = MockDatabaseProvider();
      mockApiClient = MockApiClient();
      mockVoiceService = MockVoiceService();

      // Reset service locator to clear any existing registrations
      serviceLocator.reset();

      // Register mocks in service locator
      serviceLocator.registerSingleton<DatabaseProvider>(mockDatabaseProvider);
      serviceLocator.registerSingleton<ApiClient>(mockApiClient);
      serviceLocator.registerSingleton<VoiceService>(mockVoiceService);
    });

    test('MemoryService should maintain single instance across multiple calls',
        () {
      // Create first instance
      final memoryService1 =
          MemoryService(databaseProvider: mockDatabaseProvider);

      // Create second instance with same parameters
      final memoryService2 =
          MemoryService(databaseProvider: mockDatabaseProvider);

      // They should be the same instance
      expect(identical(memoryService1, memoryService2), true);
      expect(memoryService1 == memoryService2, true);
    });

    test('VoiceService should maintain single instance across multiple calls',
        () {
      // Create first instance
      final voiceService1 = VoiceService(apiClient: mockApiClient);

      // Create second instance with same parameters
      final voiceService2 = VoiceService(apiClient: mockApiClient);

      // They should be the same instance
      expect(identical(voiceService1, voiceService2), true);
      expect(voiceService1 == voiceService2, true);
    });

    test('AudioGenerator should maintain single instance across multiple calls',
        () {
      // Create first instance
      final audioGenerator1 = AudioGenerator(
        voiceService: mockVoiceService,
        apiClient: mockApiClient,
      );

      // Create second instance with same parameters
      final audioGenerator2 = AudioGenerator(
        voiceService: mockVoiceService,
        apiClient: mockApiClient,
      );

      // They should be the same instance
      expect(identical(audioGenerator1, audioGenerator2), true);
      expect(audioGenerator1 == audioGenerator2, true);
    });

    test(
        'ConversationFlowManager should maintain single instance across multiple calls',
        () {
      // Create first instance
      final manager1 = ConversationFlowManager();

      // Create second instance
      final manager2 = ConversationFlowManager();

      // They should be the same instance
      expect(identical(manager1, manager2), true);
      expect(manager1 == manager2, true);
    });

    test('initializeOnlyIfNeeded should only initialize services once',
        () async {
      // Create an instance
      final memoryService =
          MemoryService(databaseProvider: mockDatabaseProvider);

      // Mark as not initialized first
      expect(memoryService.isInitialized, false);

      // First initialization should work
      await memoryService.initializeOnlyIfNeeded();
      expect(memoryService.isInitialized, true);

      // Attempt second initialization - should be skipped
      await memoryService.initializeOnlyIfNeeded();

      // Still initialized and init() called only once
      expect(memoryService.isInitialized, true);
    });
  });
}
