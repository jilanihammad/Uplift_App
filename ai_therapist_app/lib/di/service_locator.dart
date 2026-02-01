// lib/di/service_locator.dart
import 'dart:async';
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
import 'interfaces/i_audio_settings.dart';
import '../services/audio_settings.dart';
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
import '../services/session_schedule_service.dart';
import '../services/user_context_service.dart';

import '../utils/connectivity_checker.dart';
import 'interfaces/i_api_client.dart';
import '../config/llm_config.dart';
import '../models/tts_config.dart';
import 'interfaces/i_app_database.dart';
import 'interfaces/i_database.dart';
import 'interfaces/i_database_operation_manager.dart';
import 'interfaces/i_session_schedule_service.dart';
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
import '../services/simple_tts_service.dart';
import '../services/audio_player_manager.dart';
import '../services/audio_file_manager.dart';
import '../blocs/voice_session_bloc.dart';
import '../blocs/voice_session/voice_session.dart' as new_voice_session;
import '../services/audio_format_negotiator.dart';
import '../services/facades/chat_voice_facade.dart';
import '../services/facades/voice_mode_facade.dart';
import '../services/pipeline/voice_pipeline_controller.dart';
import '../services/pipeline/voice_pipeline_dependencies.dart';

/// Global GetIt instance for dependency injection
final serviceLocator = GetIt.instance;

/// Phase 2.2.5: Sync-once setup to prevent duplicate registrations and race conditions
final Completer<void> _setupCompleter = Completer<void>();
bool _setupStarted = false;

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

/// Register Audio Infrastructure (always needed by AudioGenerator)
/// Ensures ITTSService and IAudioFileManager are available regardless of feature flag state
void _registerAudioInfra(GetIt locator, bool useRefactoredVoicePipeline) {
  // Register AudioPlayerManager first (required by SimpleTTSService)
  if (!locator.isRegistered<AudioPlayerManager>()) {
    locator.registerLazySingleton<AudioPlayerManager>(() {
      debugPrint(
          'Registering AudioPlayerManager for audio infrastructure with AudioSettings');
      return AudioPlayerManager(audioSettings: locator<IAudioSettings>());
    });
  }

  // Register ITTSService (needed by AudioGenerator)
  if (!locator.isRegistered<ITTSService>()) {
    if (useRefactoredVoicePipeline) {
      debugPrint('🔄 Registering SimpleTTSService for NEW pipeline');
    } else {
      debugPrint('🔄 Registering SimpleTTSService for LEGACY pipeline');
    }

    locator.registerLazySingleton<ITTSService>(() {
      // Create SimpleTTSService with VoiceService callback for TTS-VAD coordination
      final simpleTTSService = SimpleTTSService(
        audioPlayerManager: locator<AudioPlayerManager>(),
      );

      // Wire the VoiceService callback after both services are available
      // This is done lazily to avoid circular dependency during registration
      Future.microtask(() {
        try {
          if (useRefactoredVoicePipeline) {
            debugPrint(
                'ℹ️ SimpleTTSService defers VoiceService wiring to VoiceModeFacade');
            return;
          }

          // For legacy pipeline, wire to legacy VoiceService
          if (locator.isRegistered<VoiceService>()) {
            final voiceService = locator<VoiceService>();
            simpleTTSService.setVoiceServiceUpdateCallback(
                voiceService.updateTTSSpeakingState);
            // TIMING FIX: Wire generation callback to VoiceSessionBloc for TTS completion timing checks
            // Note: VoiceSessionBloc will be registered later, so we defer this wiring
            Future.microtask(() {
              try {
                if (locator.isRegistered<VoiceSessionBloc>()) {
                  final voiceSessionBloc = locator<VoiceSessionBloc>();
                  simpleTTSService.setGetCurrentGenerationCallback(
                      () => voiceSessionBloc.currentGeneration);
                  debugPrint(
                      '✅ SimpleTTSService generation callback wired to VoiceSessionBloc');
                }
              } catch (e) {
                debugPrint('Warning: Could not wire generation callback: $e');
              }
            });
            debugPrint(
                '✅ SimpleTTSService wired to legacy VoiceService for TTS-VAD coordination');
          }
        } catch (e) {
          debugPrint(
              'Warning: Could not wire SimpleTTSService for TTS-VAD coordination: $e');
        }
      });

      return simpleTTSService;
    });
    debugPrint('✅ ITTSService registered successfully');
  }

  // Register IAudioFileManager (needed by AudioGenerator)
  if (!locator.isRegistered<IAudioFileManager>()) {
    debugPrint('🔄 Registering AudioFileManager for audio infrastructure');
    locator.registerLazySingleton<IAudioFileManager>(() => AudioFileManager());
    debugPrint('✅ IAudioFileManager registered successfully');
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
///
/// @param useRefactoredVoicePipeline Feature flag to control voice service registration
Future<void> setupServiceLocator({
  bool useRefactoredVoicePipeline = false,
  bool enableVoicePipelineController = false,
}) async {
  // Phase 2.2.5: Sync-once pattern prevents race conditions and duplicate logging
  if (_setupCompleter.isCompleted) {
    return _setupCompleter.future; // Return existing completion
  }

  if (_setupStarted) {
    return _setupCompleter.future; // Wait for ongoing setup
  }

  _setupStarted = true;

  try {
    debugPrint('Starting core service registration...');
    debugPrint(
        'Feature flag useRefactoredVoicePipeline: $useRefactoredVoicePipeline');
    debugPrint(
        'Feature flag voicePipelineControllerEnabled: $enableVoicePipelineController');

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

    if (!serviceLocator.isRegistered<UserContextService>()) {
      serviceLocator.registerLazySingleton<UserContextService>(
        () => UserContextService(),
      );
      debugPrint('Registered UserContextService');
    }

    // Register interface mapping for AppDatabase
    if (!serviceLocator.isRegistered<IAppDatabase>()) {
      serviceLocator.registerLazySingleton<IAppDatabase>(
        () => serviceLocator<AppDatabase>(),
      );
      debugPrint('Registered IAppDatabase interface');
    }

    // Register interface mapping for IDatabase (required by SessionDetailsScreen)
    if (!serviceLocator.isRegistered<IDatabase>()) {
      serviceLocator.registerLazySingleton<IDatabase>(
        () => _DatabaseAdapter(serviceLocator<AppDatabase>()),
      );
      debugPrint('Registered IDatabase interface');
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
      serviceLocator.registerLazySingleton<DatabaseProvider>(
        () => DatabaseProvider(),
      );
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

    // ===== REGISTER ConversationBufferMemory (if not already done elsewhere) =====
    // This is a dependency for MessageProcessor
    if (!serviceLocator.isRegistered<ConversationBufferMemory>()) {
      serviceLocator.registerLazySingleton<ConversationBufferMemory>(
        // This will now unambiguously refer to the one from custom_langchain.dart
        () => ConversationBufferMemory(maxMessages: 20),
      );
      debugPrint('Registered ConversationBufferMemory');
    }

    // NOTE: MessageProcessor and TherapyService will be registered in
    // registerApiDependentServices() after ApiClient is available

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
          if (useRefactoredVoicePipeline) {
            debugPrint(
                'ℹ️ AudioGenerator defers TTS callback wiring to VoiceModeFacade');
          } else {
            try {
              final voiceService = serviceLocator<VoiceService>();
              generator.setTTSStateCallback((isSpeaking) {
                voiceService.updateTTSSpeakingState(isSpeaking);
              });
              debugPrint(
                  'AudioGenerator TTS state callback connected to VoiceService');

              // VAD callbacks removed - no longer needed with new TTS architecture
              debugPrint(
                  'AudioGenerator VAD callbacks disabled (legacy workaround removed)');
            } catch (e) {
              debugPrint(
                  'Warning: Could not connect AudioGenerator callbacks: $e');
            }
          }
        });

        return generator;
      });
      debugPrint('Registered AudioGenerator with true lazy initialization');
    }

    // === AUDIO SETTINGS REGISTRATION (Required by all audio services) ===
    if (!serviceLocator.isRegistered<IAudioSettings>()) {
      serviceLocator
          .registerLazySingleton<IAudioSettings>(() => AudioSettings());
      debugPrint('✅ Registered IAudioSettings for global mute functionality');
    }

    // === AUDIO INFRASTRUCTURE REGISTRATION (Always needed by AudioGenerator) ===
    _registerAudioInfra(serviceLocator, useRefactoredVoicePipeline);

    // === VOICE SERVICE REGISTRATION (Feature Flag Controlled) ===
    if (useRefactoredVoicePipeline) {
      debugPrint('🔄 Using NEW refactored voice pipeline');

      // Register refactored audio services using AudioServicesModule
      // Note: TTS service already registered above
      AudioServicesModule.registerServices(serviceLocator);

      // ALSO register legacy VoiceService for AutoListeningCoordinator coordination
      // This allows VoiceSessionCoordinator to coordinate VAD through legacy service
      if (!serviceLocator.isRegistered<VoiceService>()) {
        serviceLocator.registerLazySingleton<VoiceService>(() {
          debugPrint(
              'Creating legacy VoiceService for AutoListeningCoordinator coordination');
          final service = VoiceService(
            apiClient: serviceLocator<ApiClient>(),
            audioSettings: serviceLocator<IAudioSettings>(),
          );

          // Initialize only if needed when first accessed
          service.initializeOnlyIfNeeded().then((_) {
            DependencyStatus.markInitialized('VoiceService');
            debugPrint('Legacy VoiceService initialized for VAD coordination');
          });

          return service;
        });
        debugPrint('✅ Legacy VoiceService registered for VAD coordination');
      }

      // Mark audio services as initialized for dependency tracking
      DependencyStatus.markInitialized('AudioServicesModule');
      debugPrint(
          '✅ Registered refactored audio services via AudioServicesModule');
    } else {
      debugPrint('🔄 Using LEGACY VoiceService');

      // Register the original monolithic VoiceService (legacy)
      if (!serviceLocator.isRegistered<VoiceService>()) {
        serviceLocator.registerLazySingleton<VoiceService>(() {
          debugPrint('Creating VoiceService instance (lazy initialization)');
          final service = VoiceService(
            apiClient: serviceLocator<ApiClient>(),
            audioSettings: serviceLocator<IAudioSettings>(),
          );

          // Initialize only if needed when first accessed
          service.initializeOnlyIfNeeded().then((_) {
            DependencyStatus.markInitialized('VoiceService');
            debugPrint('VoiceService initialized on first access');
          });

          return service;
        });
        debugPrint(
            '✅ Registered legacy VoiceService with true lazy initialization');
      }
    }

    // === VOICE PIPELINE CONTROLLER REGISTRATION ===
    if (enableVoicePipelineController &&
        !serviceLocator.isRegistered<VoicePipelineControllerFactory>()) {
      serviceLocator.registerFactory<VoicePipelineControllerFactory>(() {
        bool defaultMicGetter() {
          if (!serviceLocator.isRegistered<IAudioSettings>()) {
            return false;
          }
          return serviceLocator<IAudioSettings>().isMuted;
        }

        return ({
          required VoicePipelineDependencies dependencies,
          bool Function()? micMutedGetter,
          bool Function()? canStartListening,
        }) {
          return VoicePipelineController(
            dependencies: dependencies,
            micMutedGetter: micMutedGetter ?? defaultMicGetter,
            canStartListening: canStartListening,
          );
        };
      });
      debugPrint('✅ Registered VoicePipelineController factory');
    }

    // === NEW VOICE SESSION BLOC REGISTRATION ===
    if (!serviceLocator.isRegistered<new_voice_session.VoiceSessionBloc>()) {
      serviceLocator.registerFactory<new_voice_session.VoiceSessionBloc>(() {
        // Get the pipeline controller factory and create instance
        VoicePipelineController? controller;
        if (serviceLocator.isRegistered<VoicePipelineControllerFactory>()) {
          final factory = serviceLocator<VoicePipelineControllerFactory>();
          final voiceService = serviceLocator<VoiceService>();
          final audioPlayerManager = serviceLocator<AudioPlayerManager>();
          final recordingManager = voiceService.getRecordingManager();
          
          controller = factory(
            dependencies: VoicePipelineDependencies(
              voiceService: voiceService,
              audioPlayerManager: audioPlayerManager,
              recordingManager: recordingManager,
            ),
          );
        }
        
        return new_voice_session.VoiceSessionBloc(
          pipelineController: controller,
          therapyService: serviceLocator<ITherapyService>(),
        );
      });
      debugPrint('✅ Registered new VoiceSessionBloc factory');
    }

    // === SESSION FACADE REGISTRATIONS ===
    if (!serviceLocator.isRegistered<VoiceModeFacade>()) {
      serviceLocator.registerFactory<VoiceModeFacade>(() {
        final rawTtsService = serviceLocator<ITTSService>();
        final simpleTtsService = rawTtsService is SimpleTTSService
            ? rawTtsService
            : throw StateError(
                'VoiceModeFacade requires SimpleTTSService instance, found ${rawTtsService.runtimeType}');

        return VoiceModeFacade(
          voiceService: serviceLocator<VoiceService>(),
          ttsService: simpleTtsService,
          therapyService: serviceLocator<ITherapyService>(),
        );
      });
      debugPrint('✅ Registered VoiceModeFacade factory');
    }

    if (!serviceLocator.isRegistered<ChatVoiceFacade>()) {
      serviceLocator.registerFactory<ChatVoiceFacade>(() => ChatVoiceFacade(
            therapyService: serviceLocator<ITherapyService>(),
          ));
      debugPrint('✅ Registered ChatVoiceFacade factory');
    }

    if (!serviceLocator.isRegistered<service_tgs.TherapyGraphService>()) {
      serviceLocator.registerLazySingleton<service_tgs.TherapyGraphService>(
          () => service_tgs.TherapyGraphService());
      debugPrint('Registered TherapyGraphService');
    }

    if (!serviceLocator.isRegistered<ProgressService>()) {
      serviceLocator
          .registerLazySingleton<ProgressService>(() => ProgressService(
                notificationService:
                    serviceLocator<service_ns.NotificationService>(),
                databaseProvider: serviceLocator<DatabaseProvider>(),
              ));
      debugPrint('Registered ProgressService');
    }

    if (!serviceLocator.isRegistered<UserProfileService>()) {
      serviceLocator.registerLazySingleton<UserProfileService>(
          () => UserProfileService());
      debugPrint('Registered UserProfileService');
    }

    if (!serviceLocator.isRegistered<service_ms.MemoryService>()) {
      serviceLocator.registerLazySingleton<service_ms.MemoryService>(
        () => service_ms.MemoryService(
          databaseProvider: serviceLocator<DatabaseProvider>(),
          apiClient: serviceLocator<ApiClient>(),
          userProfileService: serviceLocator<UserProfileService>(),
        ),
      );
      debugPrint('Registered MemoryService with backend sync dependencies');
    }

    if (!serviceLocator.isRegistered<MemoryManager>()) {
      serviceLocator.registerLazySingleton<MemoryManager>(() {
        debugPrint('Creating MemoryManager instance (lazy initialization)');
        final manager = MemoryManager(
          memoryService: serviceLocator<service_ms.MemoryService>(),
        );
        debugPrint(
            'MemoryManager instance created - initialization deferred until first use');
        return manager;
      });
      debugPrint('Registered MemoryManager with backend-aware MemoryService');
    }

    // Register OnboardingService
    if (!serviceLocator.isRegistered<OnboardingService>()) {
      serviceLocator
          .registerLazySingleton<OnboardingService>(() => OnboardingService());
      debugPrint('Registered OnboardingService');
    }

    // Register AuthCoordinator with OnboardingService dependency
    if (!serviceLocator.isRegistered<AuthCoordinator>()) {
      serviceLocator
          .registerLazySingleton<AuthCoordinator>(() => AuthCoordinator(
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

    // Phase 2.2.5: Complete the sync-once setup
    _setupCompleter.complete();
  } catch (e, stackTrace) {
    debugPrint('ERROR during setupServiceLocator: $e');
    debugPrint('Stack trace: $stackTrace');

    // Phase 2.2.5: Complete with error for sync-once pattern
    _setupCompleter.completeError(e, stackTrace);
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
    DependencyContainer.markReady();
    return;
  }

  final stopwatch = Stopwatch()..start();
  debugPrint('[Startup] Background init started');

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

    // GOLD STANDARD: Opportunistic prefetch (non-blocking)
    // Fire-and-forget TTS config prefetch - doesn't block startup
    _prefetchTTSConfigNonBlocking(apiClient);

    // Register interface mapping for ApiClient
    if (!serviceLocator.isRegistered<IApiClient>()) {
      serviceLocator.registerLazySingleton<IApiClient>(
        () => serviceLocator<ApiClient>(),
      );
      debugPrint('Registered IApiClient interface');
    }

    // Register services that depend on the ApiClient now that it is available
    if (!serviceLocator.isRegistered<SessionScheduleService>()) {
      serviceLocator.registerLazySingleton<SessionScheduleService>(
        () => SessionScheduleService(
          apiClient: serviceLocator<IApiClient>(),
          prefsManager: serviceLocator<PrefsManager>(),
        ),
      );
      debugPrint('Registered SessionScheduleService');
    }

    if (!serviceLocator.isRegistered<ISessionScheduleService>()) {
      serviceLocator.registerLazySingleton<ISessionScheduleService>(
        () => serviceLocator<SessionScheduleService>(),
      );
      debugPrint('Registered ISessionScheduleService interface binding');
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
                userContextService: serviceLocator<UserContextService>(),
              ));
      debugPrint('Registered SessionRepository with interfaces');
    }

    if (!serviceLocator.isRegistered<MessageRepository>()) {
      serviceLocator
          .registerLazySingleton<MessageRepository>(() => MessageRepository(
                apiClient: serviceLocator<IApiClient>(),
                appDatabase: serviceLocator<IAppDatabase>(),
                userContextService: serviceLocator<UserContextService>(),
              ));
      debugPrint('Registered MessageRepository with interfaces');
    }

    // Register MessageProcessor now that ApiClient is available
    // (MessageProcessor needs ApiClient for LLM calls)
    if (!serviceLocator.isRegistered<MessageProcessor>()) {
      serviceLocator.registerLazySingleton<MessageProcessor>(() {
        debugPrint('Creating MessageProcessor instance (lazy initialization)');

        final processor = MessageProcessor(
          conversationHistory: serviceLocator<ConversationBufferMemory>(),
          configService: serviceLocator<ConfigService>(),
          groqService: serviceLocator<GroqService>(),
          apiClient: serviceLocator<ApiClient>(),
        );

        DependencyStatus.markInitialized('MessageProcessor');
        debugPrint('MessageProcessor instance created and marked initialized.');
        return processor;
      });
      debugPrint('Registered MessageProcessor with ApiClient from DI');
    }

    // Register TherapyService concrete implementation
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

    stopwatch.stop();
    debugPrint(
        '[Startup] Background init complete in ${stopwatch.elapsedMilliseconds}ms');
    DependencyContainer.markReady();

    // Optionally pre-warm latency-sensitive services
    if (serviceLocator.isRegistered<ITTSService>()) {
      unawaited(serviceLocator<ITTSService>().initialize());
    }
  } catch (e, stackTrace) {
    debugPrint('ERROR during registerApiDependentServices: $e');
    debugPrint('Stack trace: $stackTrace');
    DependencyContainer.markFailed(e, stackTrace);
    rethrow;
  }
}

/// GOLD STANDARD: Opportunistic TTS config prefetch (non-blocking)
///
/// Fires-and-forgets a TTS config fetch at startup. If it completes before
/// first TTS request, config is ready. If not, lazy fetch handles it.
/// This approach gives us zero startup blocking with best-case instant TTS.
void _prefetchTTSConfigNonBlocking(ApiClient apiClient) {
  unawaited(() async {
    try {
      debugPrint('[TTS Config] Prefetch started (non-blocking)');

      final TtsConfigDto? remoteTtsConfig = await apiClient.fetchTtsConfig();

      if (remoteTtsConfig != null && remoteTtsConfig.provider.isNotEmpty) {
        // Apply config to LLMConfig
        LLMConfig.applyRemoteTtsConfig(
          provider: remoteTtsConfig.provider,
          model: remoteTtsConfig.model,
          voice: remoteTtsConfig.voice,
          sampleRateHz: remoteTtsConfig.sampleRateHz,
          audioEncoding: remoteTtsConfig.audioEncoding,
          responseFormat: remoteTtsConfig.responseFormat,
          supportsStreaming: remoteTtsConfig.supportsStreaming,
          mode: remoteTtsConfig.mode,
          mimeType: remoteTtsConfig.mimeType,
        );

        // Refresh audio negotiation with new config
        AudioFormatNegotiator.updateFromConfig(log: true);

        // Mark config as cached in TTS service to skip lazy fetch
        try {
          final ttsService = DependencyContainer().ttsService;
          ttsService.setCachedTTSConfig();
        } catch (e) {
          debugPrint('[TTS Config] Warning: Could not mark config as cached: $e');
          // Non-fatal - lazy fetch will still work
        }

        debugPrint('[TTS Config] Prefetch succeeded and applied');
      } else {
        debugPrint('[TTS Config] Prefetch returned null/empty config');
      }
    } catch (e) {
      // Silent failure - lazy load will handle it on first TTS request
      debugPrint('[TTS Config] Prefetch failed (will lazy load on first TTS): $e');
    }
  }());
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

/// Adapter class to bridge AppDatabase to IDatabase interface
class _DatabaseAdapter implements IDatabase {
  final AppDatabase _database;

  _DatabaseAdapter(this._database);

  @override
  Future<void> initialize() async {
    await _database.database; // This will initialize the database
  }

  @override
  Future<void> close() async {
    // AppDatabase doesn't expose close method directly
  }

  @override
  bool get isOpen => true; // Assume open after initialization

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    final db = await _database.database;
    return await db.transaction((txn) async {
      return await action();
    });
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await _database.database;
    return await db.insert(table, data);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await _database.database;
    return await db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await _database.database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await _database.database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await _database.database;
    return await db.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawInsert(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawUpdate(sql, arguments);
  }

  @override
  Future<int> rawDelete(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawDelete(sql, arguments);
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    await db.execute(sql, arguments);
  }

  @override
  Future<bool> tableExists(String tableName) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<String>> getTableNames() async {
    final db = await _database.database;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return result.map((row) => row['name'] as String).toList();
  }

  @override
  Future<void> runMigration(int fromVersion, int toVersion) async {
    // Migration logic would be implemented here
  }

  @override
  int get version => 1; // Default version

  @override
  Future<void> batch(Future<void> Function() operations) async {
    final db = await _database.database;
    final batch = db.batch();
    await operations();
    await batch.commit();
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final db = await _database.database;
      await db.rawQuery('SELECT 1');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    return {
      'isOpen': isOpen,
      'version': version,
      'healthy': await healthCheck(),
    };
  }
}
