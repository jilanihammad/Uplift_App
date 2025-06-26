// lib/di/service_locator.dart
import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';
import 'dependency_container.dart';
import 'modules/services_module.dart';

import '../data/datasources/remote/api_client.dart';
import '../data/datasources/local/prefs_manager.dart';
import '../data/datasources/local/app_database.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';
import '../services/langchain/custom_langchain.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/message_repository.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart' as service_ns;
import '../services/voice_service.dart';
import '../services/therapy_service.dart';
import 'interfaces/i_therapy_service.dart';
import '../services/preferences_service.dart';
import '../services/progress_service.dart';
import '../services/user_profile_service.dart';
import '../services/onboarding_service.dart';
import '../services/auth_coordinator.dart';
import '../services/memory_service.dart' as service_ms;
import '../services/therapy_graph_service.dart' as service_tgs;
import '../services/config_service.dart';
import '../services/firebase_service.dart';
import '../services/backend_service.dart';
import '../services/theme_service.dart';
import '../services/navigation_service.dart';

import '../utils/connectivity_checker.dart';
import 'interfaces/i_api_client.dart';
import 'interfaces/i_app_database.dart';
import 'interfaces/i_database_operation_manager.dart';
import '../data/datasources/local/database_provider.dart';
import '../services/memory_manager.dart';
import '../services/message_processor.dart';
import '../services/audio_generator.dart';
import 'package:ai_therapist_app/utils/database_helper.dart';
import '../services/groq_service.dart';
import '../services/vad_manager.dart';
import 'modules/audio_services_module.dart';
import 'interfaces/i_tts_service.dart';
import 'interfaces/i_audio_file_manager.dart';

/// Global GetIt instance for dependency injection
final serviceLocator = GetIt.instance;

/// Dependency Registration Status - helps track initialized services
/// and prevent duplicate or missing registrations
class DependencyStatus {
  static bool coreServicesRegistered = false;
  static bool apiDependenciesRegistered = false;
  static bool firebaseServicesRegistered = false;

  // Service initialization status tracking
  static final Map<String, bool> initializedServices = {};

  /// Reset all status flags (useful for testing)
  static void reset() {
    coreServicesRegistered = false;
    apiDependenciesRegistered = false;
    firebaseServicesRegistered = false;
    initializedServices.clear();
  }

  /// Mark a service as initialized
  static void markInitialized(String serviceName) {
    initializedServices[serviceName] = true;
    debugPrint('Service marked as initialized: $serviceName');
  }

  /// Check if a service is initialized
  static bool isInitialized(String serviceName) {
    return initializedServices[serviceName] ?? false;
  }
}

/// Main service locator setup function
///
/// This function registers core services that don't have complex initialization
/// or dependencies. Services with async initialization or dependencies on
/// other services are registered in main.dart.
///
/// Registration follows this order:
/// 1. Core utility services (sync initialization)
/// 2. Data sources (local storage, database)
/// 3. Simple services without dependencies
///
/// NOT registered here (these are registered in main.dart):
/// - ConfigService (async initialization)
/// - ApiClient (depends on ConfigService)
/// - Repositories (depend on ApiClient)
/// - AuthService, TherapyService (depend on repositories)
/// - Firebase-dependent services (complex async initialization)
Future<void> setupServiceLocator() async {
  // Prevent duplicate registration if already called
  if (DependencyStatus.coreServicesRegistered) {
    debugPrint(
        'Core services already registered, skipping setupServiceLocator()');
    return;
  }

  try {
    debugPrint('Starting core service registration...');

    // Register utilities first
    if (!serviceLocator.isRegistered<DatabaseOperationManager>()) {
      serviceLocator.registerSingleton<DatabaseOperationManager>(
          DatabaseOperationManager());
      debugPrint(
          'Registered DatabaseOperationManager to manage database operations');
    }

    // Register interface mapping for DatabaseOperationManager
    if (!serviceLocator.isRegistered<IDatabaseOperationManager>()) {
      serviceLocator.registerLazySingleton<IDatabaseOperationManager>(
        () => serviceLocator<DatabaseOperationManager>(),
      );
      debugPrint('Registered IDatabaseOperationManager interface');
    }

    // Register data sources
    if (!serviceLocator.isRegistered<AppDatabase>()) {
      serviceLocator.registerSingleton<AppDatabase>(AppDatabase());
      debugPrint('Registered AppDatabase');
    }

    // Register interface mapping for AppDatabase
    if (!serviceLocator.isRegistered<IAppDatabase>()) {
      serviceLocator.registerLazySingleton<IAppDatabase>(
        () => serviceLocator<AppDatabase>(),
      );
      debugPrint('Registered IAppDatabase interface');
    }

    // ===== FIREBASE SERVICE (Base registration only) =====
    // Skip registration if firebase_core is not available / imported
    // This allows the app to run without Firebase during development
    if (!serviceLocator.isRegistered<FirebaseService>()) {
      serviceLocator.registerSingleton<FirebaseService>(FirebaseService());
      debugPrint('Registered FirebaseService (base instance)');
    }

    // ===== BACKEND SERVICE =====
    if (!serviceLocator.isRegistered<BackendService>()) {
      serviceLocator.registerSingleton<BackendService>(BackendService());
      debugPrint('Registered BackendService');
    }

    // ===== LOCAL DATA SOURCES =====
    // These services are registered and initialized here because they're
    // fundamental and other services depend on them

    // PrefsManager (handles shared preferences)
    if (!serviceLocator.isRegistered<PrefsManager>()) {
      serviceLocator.registerLazySingleton<PrefsManager>(() => PrefsManager());
      final prefsManager = serviceLocator<PrefsManager>();
      await prefsManager.init();
      debugPrint('Registered and initialized PrefsManager');
    }

    // Register DatabaseProvider that uses AppDatabase
    if (!serviceLocator.isRegistered<DatabaseProvider>()) {
      serviceLocator
          .registerLazySingleton<DatabaseProvider>(() => DatabaseProvider());
      debugPrint('Registered DatabaseProvider');
    }

    // ===== UTILITY SERVICES =====
    // These services have minimal dependencies and simple initialization

    if (!serviceLocator.isRegistered<ConnectivityChecker>()) {
      serviceLocator.registerLazySingleton<ConnectivityChecker>(
          () => ConnectivityChecker());
      debugPrint('Registered ConnectivityChecker');
    }

    if (!serviceLocator.isRegistered<service_ns.NotificationService>()) {
      serviceLocator.registerLazySingleton<service_ns.NotificationService>(
          () => service_ns.NotificationService());
      debugPrint('Registered NotificationService');
    }

    if (!serviceLocator.isRegistered<PreferencesService>()) {
      serviceLocator.registerLazySingleton<PreferencesService>(
          () => PreferencesService());
      debugPrint('Registered PreferencesService');
    }

    if (!serviceLocator.isRegistered<ThemeService>()) {
      serviceLocator.registerLazySingleton<ThemeService>(() => ThemeService(
        preferencesService: serviceLocator<PreferencesService>(),
      ));
      debugPrint('Registered ThemeService with dependency injection');
    }

    // ===== SIMPLE DOMAIN SERVICES =====
    // These services have minimal dependencies but may need initialization later

    if (!serviceLocator.isRegistered<service_ms.MemoryService>()) {
      serviceLocator.registerLazySingleton<service_ms.MemoryService>(
          () => service_ms.MemoryService(
                databaseProvider: serviceLocator<DatabaseProvider>(),
              ));
      debugPrint('Registered MemoryService with constructor injection');
    }

    // Register new refactored services
    if (!serviceLocator.isRegistered<MemoryManager>()) {
      serviceLocator.registerLazySingleton<MemoryManager>(() {
        debugPrint('Creating MemoryManager instance (lazy initialization)');
        final manager = MemoryManager(
          memoryService: serviceLocator<service_ms.MemoryService>(),
        );

        // Initialize only if needed when first accessed
        manager.initializeOnlyIfNeeded().then((_) {
          DependencyStatus.markInitialized('MemoryManager');
          debugPrint('MemoryManager initialized on first access');
        });

        return manager;
      });
      debugPrint('Registered MemoryManager with true lazy initialization');
    }

    // ===== REGISTER ConversationBufferMemory (if not already done elsewhere) =====
    // This is a dependency for MessageProcessor
    if (!serviceLocator.isRegistered<ConversationBufferMemory>()) {
      serviceLocator.registerLazySingleton<ConversationBufferMemory>(
        // This will now unambiguously refer to the one from custom_langchain.dart
        () => ConversationBufferMemory(maxMessages: 20),
      );
      debugPrint('Registered ConversationBufferMemory');
    }

    // ===== REGISTER MessageProcessor (BEFORE TherapyService) =====
    // Break circular dependency by registering MessageProcessor first
    if (!serviceLocator.isRegistered<MessageProcessor>()) {
      serviceLocator.registerLazySingleton<MessageProcessor>(() {
        debugPrint('Creating MessageProcessor instance (lazy initialization)');

        final processor = MessageProcessor(
          voiceSessionBloc: null, // Will be set later to avoid circular dependency
          conversationHistory: serviceLocator<ConversationBufferMemory>(),
          configService: serviceLocator<ConfigService>(),
          groqService: serviceLocator<GroqService>(),
        );

        DependencyStatus.markInitialized('MessageProcessor');
        debugPrint('MessageProcessor instance created and marked initialized.');
        return processor;
      });
      debugPrint('Registered MessageProcessor without circular dependencies');
    }

    // NOTE: TherapyService will be registered in registerApiDependentServices() 
    // after ApiClient is available

    if (!serviceLocator.isRegistered<AudioGenerator>()) {
      // Use lazy singleton to prevent immediate initialization
      serviceLocator.registerLazySingleton<AudioGenerator>(() {
        debugPrint('Creating AudioGenerator instance (lazy initialization)');
        final generator = AudioGenerator(
          ttsService: serviceLocator<ITTSService>(),
          audioFileManager: serviceLocator<IAudioFileManager>(),
          apiClient: serviceLocator<ApiClient>(),
        );

        // Initialize only if needed when first accessed
        generator.initializeOnlyIfNeeded().then((_) {
          DependencyStatus.markInitialized('AudioGenerator');
          debugPrint('AudioGenerator initialized on first access');
          
          // Set up TTS state callback to coordinate with VoiceService
          // This is done after initialization to avoid circular dependency issues
          try {
            final voiceService = serviceLocator<VoiceService>();
            generator.setTTSStateCallback((isSpeaking) {
              voiceService.updateTTSSpeakingState(isSpeaking);
            });
            debugPrint('AudioGenerator TTS state callback connected to VoiceService');
            
            // Set up VAD pause/resume callbacks to prevent echo-loop
            generator.setVADCallbacks(
              pauseCallback: () async => await voiceService.pauseVAD(),
              resumeCallback: () async => await voiceService.resumeVAD(),
            );
            debugPrint('AudioGenerator VAD callbacks connected to VoiceService');
          } catch (e) {
            debugPrint('Warning: Could not connect AudioGenerator callbacks: $e');
          }
        });

        return generator;
      });
      debugPrint('Registered AudioGenerator with true lazy initialization');
    }

    // Register the original monolithic VoiceService (still needed by AudioGenerator)
    if (!serviceLocator.isRegistered<VoiceService>()) {
      serviceLocator.registerLazySingleton<VoiceService>(() {
        debugPrint('Creating VoiceService instance (lazy initialization)');
        final service = VoiceService(
          apiClient: serviceLocator<ApiClient>(),
        );

        // Initialize only if needed when first accessed
        service.initializeOnlyIfNeeded().then((_) {
          DependencyStatus.markInitialized('VoiceService');
          debugPrint('VoiceService initialized on first access');
        });

        return service;
      });
      debugPrint('Registered VoiceService with true lazy initialization');
    }

    // Register refactored audio services using AudioServicesModule
    // This provides the new focused, single-responsibility services via IVoiceService
    AudioServicesModule.registerServices(serviceLocator);
    
    // Mark audio services as initialized for dependency tracking
    DependencyStatus.markInitialized('AudioServicesModule');
    debugPrint('Registered refactored audio services via AudioServicesModule');

    if (!serviceLocator.isRegistered<service_tgs.TherapyGraphService>()) {
      serviceLocator.registerLazySingleton<service_tgs.TherapyGraphService>(
          () => service_tgs.TherapyGraphService());
      debugPrint('Registered TherapyGraphService');
    }

    if (!serviceLocator.isRegistered<ProgressService>()) {
      serviceLocator.registerLazySingleton<ProgressService>(() =>
          ProgressService(
              notificationService:
                  serviceLocator<service_ns.NotificationService>()));
      debugPrint('Registered ProgressService');
    }

    if (!serviceLocator.isRegistered<UserProfileService>()) {
      serviceLocator.registerLazySingleton<UserProfileService>(
          () => UserProfileService());
      debugPrint('Registered UserProfileService');
    }

    // Register OnboardingService
    if (!serviceLocator.isRegistered<OnboardingService>()) {
      serviceLocator.registerLazySingleton<OnboardingService>(() => OnboardingService());
      debugPrint('Registered OnboardingService');
    }
    
    // Register AuthCoordinator with OnboardingService dependency
    if (!serviceLocator.isRegistered<AuthCoordinator>()) {
      serviceLocator.registerLazySingleton<AuthCoordinator>(() => AuthCoordinator(
        onboardingService: serviceLocator<OnboardingService>(),
      ));
      debugPrint('Registered AuthCoordinator');
    }
    
    // Register AuthService with dependencies (migrated to dependency injection)
    if (!serviceLocator.isRegistered<AuthService>()) {
      serviceLocator.registerLazySingleton<AuthService>(() => AuthService(
        userProfileService: serviceLocator<UserProfileService>(),
        authEventHandler: serviceLocator<AuthCoordinator>(),
      ));
      debugPrint('Registered AuthService with dependency injection');
    }

    // Initialize the coordinator
    try {
      final authCoordinator = serviceLocator<AuthCoordinator>();
      await authCoordinator.init();
      debugPrint('Initialized AuthCoordinator');
    } catch (e) {
      debugPrint('Error initializing AuthCoordinator: $e');
    }

    // TherapyService registration moved to registerApiDependentServices() to avoid duplicates

    // Register NavigationService
    if (!serviceLocator.isRegistered<NavigationService>()) {
      serviceLocator
          .registerLazySingleton<NavigationService>(() => NavigationService());
      debugPrint('Registered NavigationService');
    }

    // Register GroqService
    if (!serviceLocator.isRegistered<GroqService>()) {
      serviceLocator.registerLazySingleton<GroqService>(() => GroqService());
      debugPrint('Registered GroqService');
    }

    // Register VADManager for voice session Bloc and services
    if (!serviceLocator.isRegistered<VADManager>()) {
      serviceLocator.registerLazySingleton<VADManager>(() => VADManager());
      debugPrint('Registered VADManager');
    }

    // Register Phase 5/6 interface mappings from ServicesModule
    await ServicesModule.register(serviceLocator);
    debugPrint('ServicesModule interface registrations complete');

    // Initialize the new DependencyContainer
    await DependencyContainer().initialize();
    debugPrint('DependencyContainer initialized');

    // Mark core services as registered
    DependencyStatus.coreServicesRegistered = true;
    debugPrint('Core service registration complete');
  } catch (e, stackTrace) {
    debugPrint('ERROR during setupServiceLocator: $e');
    debugPrint('Stack trace: $stackTrace');
    rethrow; // Re-throw to allow caller to handle the error
  }
}

/// Register API-dependent services
///
/// This should be called after ConfigService is initialized
/// Note: This is called from main.dart in _initializeConfigAndApi()
Future<void> registerApiDependentServices(
    ConfigService configService, ApiClient apiClient) async {
  if (DependencyStatus.apiDependenciesRegistered) {
    debugPrint('API dependencies already registered');
    return;
  }

  try {
    // Register ConfigService and ApiClient
    if (!serviceLocator.isRegistered<ConfigService>()) {
      serviceLocator.registerSingleton<ConfigService>(configService);
      debugPrint('Registered ConfigService');
    }

    if (!serviceLocator.isRegistered<ApiClient>()) {
      serviceLocator.registerSingleton<ApiClient>(apiClient);
      debugPrint('Registered ApiClient');
    }

    // Register interface mapping for ApiClient
    if (!serviceLocator.isRegistered<IApiClient>()) {
      serviceLocator.registerLazySingleton<IApiClient>(
        () => serviceLocator<ApiClient>(),
      );
      debugPrint('Registered IApiClient interface');
    }

    // Register repositories that depend on ApiClient and AppDatabase
    if (!serviceLocator.isRegistered<AuthRepository>()) {
      serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
            apiClient: serviceLocator<IApiClient>(),
          ));
      debugPrint('Registered AuthRepository with injected IApiClient');
    }

    if (!serviceLocator.isRegistered<UserRepository>()) {
      serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
            apiClient: serviceLocator<IApiClient>(),
          ));
      debugPrint('Registered UserRepository with IApiClient');
    }

    if (!serviceLocator.isRegistered<SessionRepository>()) {
      serviceLocator
          .registerLazySingleton<SessionRepository>(() => SessionRepository(
                apiClient: serviceLocator<IApiClient>(),
                appDatabase: serviceLocator<IAppDatabase>(),
              ));
      debugPrint('Registered SessionRepository with interfaces');
    }

    if (!serviceLocator.isRegistered<MessageRepository>()) {
      serviceLocator
          .registerLazySingleton<MessageRepository>(() => MessageRepository(
                apiClient: serviceLocator<IApiClient>(),
                appDatabase: serviceLocator<IAppDatabase>(),
              ));
      debugPrint('Registered MessageRepository with interfaces');
    }

    // Register TherapyService concrete implementation first
    if (!serviceLocator.isRegistered<TherapyService>()) {
      serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService(
            messageProcessor: serviceLocator<MessageProcessor>(),
            audioGenerator: serviceLocator<AudioGenerator>(),
            memoryManager: serviceLocator<MemoryManager>(),
            apiClient: serviceLocator<ApiClient>(),
          ));
      debugPrint('Registered TherapyService concrete implementation');
    }

    // Register interface mapping after concrete service is available
    if (!serviceLocator.isRegistered<ITherapyService>()) {
      serviceLocator.registerLazySingleton<ITherapyService>(
        () => serviceLocator<TherapyService>(),
      );
      debugPrint('Registered ITherapyService interface mapping');
    }

    // Re-register interface mappings now that concrete services are available
    await ServicesModule.register(serviceLocator);
    debugPrint('ServicesModule interface mappings updated after API services');

    DependencyStatus.apiDependenciesRegistered = true;
    debugPrint('API-dependent service registration complete');
  } catch (e, stackTrace) {
    debugPrint('ERROR during registerApiDependentServices: $e');
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  }
}

/// Check if all required dependencies are registered
///
/// This is useful for validating the DI setup before app launch
bool validateDependencies() {
  final requiredDependencies = <Type>[
    PrefsManager,
    AppDatabase,
    DatabaseProvider,
    FirebaseService,
    ConfigService,
    ApiClient,
    TherapyService,
    AuthService,
  ];

  final missing = <String>[];

  for (final dependencyType in requiredDependencies) {
    try {
      serviceLocator.get(type: dependencyType);
    } catch (e) {
      missing.add(dependencyType.toString());
    }
  }

  if (missing.isNotEmpty) {
    debugPrint('WARNING: Missing required dependencies: ${missing.join(', ')}');
    return false;
  }

  return true;
}
