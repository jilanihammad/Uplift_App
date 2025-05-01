// lib/di/service_locator.dart
import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/remote/api_client.dart';
import '../data/datasources/local/prefs_manager.dart';
import '../data/datasources/local/app_database.dart';
import '../data/datasources/local/database_helper.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/message_repository.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../services/therapy_service.dart';
import '../services/preferences_service.dart';
import '../services/progress_service.dart';
import '../services/user_profile_service.dart';
import '../services/onboarding_service.dart';
import '../services/memory_service.dart';
import '../services/therapy_graph_service.dart';
import '../services/config_service.dart';
import '../services/firebase_service.dart';
import '../services/backend_service.dart';
import '../services/theme_service.dart';
import '../services/navigation_service.dart';

import '../utils/connectivity_checker.dart';
import '../data/datasources/local/database_provider.dart';
import '../services/memory_manager.dart';
import '../services/message_processor.dart';
import '../services/audio_generator.dart';
import '../services/conversation_flow_manager.dart';

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

    // ===== FIREBASE SERVICE (Base registration only) =====
    // Note: Actual initialization happens in main.dart
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

    // Database services
    if (!serviceLocator.isRegistered<AppDatabase>()) {
      serviceLocator.registerLazySingleton<AppDatabase>(() => AppDatabase());
      debugPrint('Registered AppDatabase');
    }

    // Register DatabaseProvider that uses AppDatabase
    if (!serviceLocator.isRegistered<DatabaseProvider>()) {
      serviceLocator
          .registerLazySingleton<DatabaseProvider>(() => DatabaseProvider());
      debugPrint('Registered DatabaseProvider');
    }

    // Register DatabaseHelper for backward compatibility
    // This is needed until all references are migrated to DatabaseProvider
    if (!serviceLocator.isRegistered<DatabaseHelper>()) {
      serviceLocator
          .registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());
      debugPrint('Registered DatabaseHelper (legacy adapter)');
    }

    // DatabaseHelper is being removed since its functionality
    // is now consolidated into AppDatabase

    // ===== UTILITY SERVICES =====
    // These services have minimal dependencies and simple initialization

    if (!serviceLocator.isRegistered<ConnectivityChecker>()) {
      serviceLocator.registerLazySingleton<ConnectivityChecker>(
          () => ConnectivityChecker());
      debugPrint('Registered ConnectivityChecker');
    }

    if (!serviceLocator.isRegistered<NotificationService>()) {
      serviceLocator.registerLazySingleton<NotificationService>(
          () => NotificationService());
      debugPrint('Registered NotificationService');
    }

    if (!serviceLocator.isRegistered<PreferencesService>()) {
      serviceLocator.registerLazySingleton<PreferencesService>(
          () => PreferencesService());
      debugPrint('Registered PreferencesService');
    }

    if (!serviceLocator.isRegistered<ThemeService>()) {
      serviceLocator.registerLazySingleton<ThemeService>(() => ThemeService());
      debugPrint('Registered ThemeService');
    }

    // ===== SIMPLE DOMAIN SERVICES =====
    // These services have minimal dependencies but may need initialization later

    if (!serviceLocator.isRegistered<MemoryService>()) {
      serviceLocator.registerLazySingleton<MemoryService>(() => MemoryService(
            databaseProvider: serviceLocator<DatabaseProvider>(),
          ));
      debugPrint('Registered MemoryService with constructor injection');
    }

    // Register new refactored services
    if (!serviceLocator.isRegistered<MemoryManager>()) {
      serviceLocator.registerLazySingleton<MemoryManager>(() {
        debugPrint('Creating MemoryManager instance (lazy initialization)');
        final manager = MemoryManager(
          memoryService: serviceLocator<MemoryService>(),
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

    if (!serviceLocator.isRegistered<MessageProcessor>()) {
      serviceLocator.registerLazySingleton<MessageProcessor>(() {
        debugPrint('Creating MessageProcessor instance (lazy initialization)');
        final processor = MessageProcessor(
          apiClient: serviceLocator<ApiClient>(),
        );

        // Nothing to initialize for MessageProcessor
        DependencyStatus.markInitialized('MessageProcessor');

        return processor;
      });
      debugPrint('Registered MessageProcessor with constructor injection');
    }

    if (!serviceLocator.isRegistered<AudioGenerator>()) {
      // Use lazy singleton to prevent immediate initialization
      serviceLocator.registerLazySingleton<AudioGenerator>(() {
        debugPrint('Creating AudioGenerator instance (lazy initialization)');
        final generator = AudioGenerator(
          voiceService: serviceLocator<VoiceService>(),
          apiClient: serviceLocator<ApiClient>(),
        );

        // Initialize only if needed when first accessed
        generator.initializeOnlyIfNeeded().then((_) {
          DependencyStatus.markInitialized('AudioGenerator');
          debugPrint('AudioGenerator initialized on first access');
        });

        return generator;
      });
      debugPrint('Registered AudioGenerator with true lazy initialization');
    }

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

    if (!serviceLocator.isRegistered<TherapyGraphService>()) {
      serviceLocator.registerLazySingleton<TherapyGraphService>(
          () => TherapyGraphService());
      debugPrint('Registered TherapyGraphService');
    }

    if (!serviceLocator.isRegistered<ProgressService>()) {
      serviceLocator.registerLazySingleton<ProgressService>(() =>
          ProgressService(
              notificationService: serviceLocator<NotificationService>()));
      debugPrint('Registered ProgressService');
    }

    if (!serviceLocator.isRegistered<UserProfileService>()) {
      serviceLocator.registerLazySingleton<UserProfileService>(
          () => UserProfileService());
      debugPrint('Registered UserProfileService');
    }

    // Register AuthService first without OnboardingService
    if (!serviceLocator.isRegistered<AuthService>()) {
      serviceLocator.registerLazySingleton<AuthService>(() => AuthService());
      debugPrint('Registered AuthService');
    }

    // Register OnboardingService with AuthService injected
    if (!serviceLocator.isRegistered<OnboardingService>()) {
      final authService = serviceLocator<AuthService>();
      serviceLocator.registerLazySingleton<OnboardingService>(
          () => OnboardingService(authService: authService));
      debugPrint('Registered OnboardingService with AuthService');

      // Connect the AuthService back to OnboardingService to break circular dependency
      final onboardingService = serviceLocator<OnboardingService>();
      authService.setOnboardingService(onboardingService);
      debugPrint('Connected AuthService to OnboardingService');
    }

    // Register services that depend on repositories
    if (!serviceLocator.isRegistered<TherapyService>()) {
      serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService(
            messageProcessor: serviceLocator<MessageProcessor>(),
            audioGenerator: serviceLocator<AudioGenerator>(),
            memoryManager: serviceLocator<MemoryManager>(),
            apiClient: serviceLocator<ApiClient>(),
          ));
      debugPrint('Registered TherapyService with constructor injection');
    }

    // Register NavigationService
    if (!serviceLocator.isRegistered<NavigationService>()) {
      serviceLocator
          .registerLazySingleton<NavigationService>(() => NavigationService());
      debugPrint('Registered NavigationService');
    }

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

    // Register repositories that depend on ApiClient and AppDatabase
    if (!serviceLocator.isRegistered<AuthRepository>()) {
      serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
            apiClient: serviceLocator<ApiClient>(),
          ));
      debugPrint('Registered AuthRepository with injected ApiClient');
    }

    if (!serviceLocator.isRegistered<UserRepository>()) {
      serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
            apiClient: serviceLocator<ApiClient>(),
          ));
      debugPrint('Registered UserRepository');
    }

    if (!serviceLocator.isRegistered<SessionRepository>()) {
      serviceLocator
          .registerLazySingleton<SessionRepository>(() => SessionRepository(
                apiClient: serviceLocator<ApiClient>(),
                appDatabase: serviceLocator<AppDatabase>(),
              ));
      debugPrint('Registered SessionRepository');
    }

    if (!serviceLocator.isRegistered<MessageRepository>()) {
      serviceLocator
          .registerLazySingleton<MessageRepository>(() => MessageRepository(
                apiClient: serviceLocator<ApiClient>(),
                appDatabase: serviceLocator<AppDatabase>(),
              ));
      debugPrint('Registered MessageRepository');
    }

    // Register services that depend on repositories
    if (!serviceLocator.isRegistered<TherapyService>()) {
      serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService(
            messageProcessor: serviceLocator<MessageProcessor>(),
            audioGenerator: serviceLocator<AudioGenerator>(),
            memoryManager: serviceLocator<MemoryManager>(),
            apiClient: serviceLocator<ApiClient>(),
          ));
      debugPrint('Registered TherapyService with constructor injection');
    }

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
