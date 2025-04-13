// test/therapy_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/memory_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/therapy_graph_service.dart';
import 'package:ai_therapist_app/services/therapy_conversation_graph.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/models/conversation_memory.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:get_it/get_it.dart';

// Import generated mock classes
import 'therapy_service_test.mocks.dart';

// Generate mocks for our dependencies
@GenerateMocks([ApiClient, MemoryService, VoiceService, TherapyGraphService])
void main() {
  late TherapyService therapyService;
  late MockApiClient mockApiClient;
  late MockMemoryService mockMemoryService;
  late MockVoiceService mockVoiceService;
  late MockTherapyGraphService mockTherapyGraphService;
  
  setUp(() async {
    // First, make sure GetIt is properly reset
    if (GetIt.I.isRegistered<ApiClient>()) {
      GetIt.I.unregister<ApiClient>();
    }
    if (GetIt.I.isRegistered<MemoryService>()) {
      GetIt.I.unregister<MemoryService>();
    }
    if (GetIt.I.isRegistered<VoiceService>()) {
      GetIt.I.unregister<VoiceService>();
    }
    if (GetIt.I.isRegistered<TherapyGraphService>()) {
      GetIt.I.unregister<TherapyGraphService>();
    }
    if (GetIt.I.isRegistered<TherapyService>()) {
      GetIt.I.unregister<TherapyService>();
    }
    
    // Create mock instances
    mockApiClient = MockApiClient();
    mockMemoryService = MockMemoryService();
    mockVoiceService = MockVoiceService();
    mockTherapyGraphService = MockTherapyGraphService();
    
    // Register mocks with GetIt
    GetIt.I.registerSingleton<ApiClient>(mockApiClient);
    GetIt.I.registerSingleton<MemoryService>(mockMemoryService);
    GetIt.I.registerSingleton<VoiceService>(mockVoiceService);
    GetIt.I.registerSingleton<TherapyGraphService>(mockTherapyGraphService);
    
    // Setup basic mocked behavior
    when(mockMemoryService.getMemoryContext()).thenAnswer((_) async => 'Test memory context');
    when(mockMemoryService.addInteraction(any, any, any)).thenAnswer((_) async => {});
    when(mockVoiceService.initialize()).thenAnswer((_) async => {});
    when(mockVoiceService.generateAudio(any, isAiSpeaking: anyNamed('isAiSpeaking')))
        .thenAnswer((_) async => 'test_audio_path.mp3');
    
    // Creating a dummy TherapyNode to return from the mock
    final dummyNode = TherapyNode(
      id: 'introduction',
      name: 'Introduction',
      description: 'Introduction node',
      metadata: {
        'techniques': ['active_listening'],
        'tools': ['breathing_exercise'],
      },
    );
    
    when(mockTherapyGraphService.getCurrentNode()).thenReturn(dummyNode);
    
    // Initialize therapy service with mocks properly registered
    therapyService = TherapyService();
    
    // We need to register the TherapyService after creating it
    if (!GetIt.I.isRegistered<TherapyService>()) {
      GetIt.I.registerSingleton<TherapyService>(therapyService);
    }
  });

  group('TherapyService Tests', () {
    test('Should initialize correctly', () async {
      // Act
      await therapyService.init();
      
      // Assert - just ensure no exceptions are thrown
      expect(true, isTrue);
    });
    
    test('Should process user message correctly', () async {
      // Arrange
      await therapyService.init();
      
      // Setup the mock API client with proper named parameter syntax
      when(mockApiClient.post(
        any,
        body: anyNamed('body'),
      )).thenAnswer((_) => Future.value({'response': 'I understand you feel anxious about work.'}));
      
      // Act
      final result = await therapyService.processUserMessage("I'm feeling anxious about my work.");
      
      // Assert
      expect(result, isNotEmpty);
      expect(result, 'I understand you feel anxious about work.');
    });

    test('Should provide correct audio response', () async {
      // Arrange
      await therapyService.init();
      
      // Setup the mock API client with proper named parameter syntax
      when(mockApiClient.post(
        any,
        body: anyNamed('body'),
      )).thenAnswer((_) => Future.value({'response': 'Test AI response'}));
      
      // Act
      final result = await therapyService.processUserMessageWithAudio("How can I manage stress?");
      
      // Assert
      expect(result, isA<Map<String, dynamic>>());
      expect(result['text'], 'Test AI response');
      expect(result['audioPath'], equals('test_audio_path.mp3'));
    });
  });
}