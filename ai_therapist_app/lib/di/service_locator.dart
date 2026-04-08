// lib/di/service_locator.dart
import 'dart:async';
import 'package:get_it/get_it.dart';
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
import 'interfaces/i_progress_service.dart';
import 'interfaces/i_session_repository.dart';
import '../config/llm_config.dart';
import '../models/tts_config.dart';
import 'interfaces/i_app_database.dart';
import 'interfaces/i_database.dart';
import 'interfaces/i_database_operation_manager.dart';
import 'interfaces/i_session_schedule_service.dart';
import '../data/datasources/local/database_provider.dart';
import '../services/memory_manager.dart';
import '../services/session_finalization_service.dart';
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
import '../services/audio_format_negotiator.dart';
import '../services/facades/chat_voice_facade.dart';
import '../services/facades/voice_mode_facade.dart';
import '../services/pipeline/voice_pipeline_controller.dart';
import '../services/pipeline/voice_pipeline_dependencies.dart';
final serviceLocator = GetIt.instance;
final Completer<void> _setupCompleter = Completer<void>();
bool _setupStarted = false;
class DependencyStatus {
  static bool coreServicesRegistered = false;
  static bool apiDependenciesRegistered = false;
  static bool firebaseServicesRegistered = false;
  static final Map<String, bool> initializedServices = {};
  static void reset() {
    coreServicesRegistered = false;
    apiDependenciesRegistered = false;
    firebaseServicesRegistered = false;
    initializedServices.clear();
  }
  static void markInitialized(String serviceName) {
    initializedServices[serviceName] = true;
  }
  static bool isInitialized(String serviceName) {
    return initializedServices[serviceName] ?? false;
  }
}
void _registerAudioInfra(GetIt locator, bool useRefactoredVoicePipeline) {
  if (!locator.isRegistered<AudioPlayerManager>()) {
    locator.registerLazySingleton<AudioPlayerManager>(() {
      return AudioPlayerManager(audioSettings: locator<IAudioSettings>());
    });
  }
  if (!locator.isRegistered<ITTSService>()) {
    locator.registerLazySingleton<ITTSService>(() {
      final simpleTTSService = SimpleTTSService(
        audioPlayerManager: locator<AudioPlayerManager>(),
      );
      // Legacy voice pipeline wiring (refactored pipeline wires via VoiceModeFacade)
      if (!useRefactoredVoicePipeline) {
        Future.microtask(() {
          try {
            if (locator.isRegistered<VoiceService>()) {
              simpleTTSService.setVoiceServiceUpdateCallback(
                  locator<VoiceService>().updateTTSSpeakingState);
            }
            if (locator.isRegistered<VoiceSessionBloc>()) {
              simpleTTSService.setGetCurrentGenerationCallback(
                  () => locator<VoiceSessionBloc>().currentGeneration);
            }
          } catch (_) {}
        });
      }
      return simpleTTSService;
    });
  }
  if (!locator.isRegistered<IAudioFileManager>()) {
    locator.registerLazySingleton<IAudioFileManager>(() => AudioFileManager());
  }
}
Future<void> setupServiceLocator({
  bool useRefactoredVoicePipeline = false,
}) async {
  if (_setupCompleter.isCompleted) {
    return _setupCompleter.future; // Return existing completion
  }
  if (_setupStarted) {
    return _setupCompleter.future; // Wait for ongoing setup
  }
  _setupStarted = true;
  try {
    if (!serviceLocator.isRegistered<DatabaseOperationManager>()) {
      serviceLocator.registerSingleton<DatabaseOperationManager>(
          DatabaseOperationManager());
    }
    if (!serviceLocator.isRegistered<IDatabaseOperationManager>()) {
      serviceLocator.registerLazySingleton<IDatabaseOperationManager>(
        () => serviceLocator<DatabaseOperationManager>(),
      );
    }
    if (!serviceLocator.isRegistered<AppDatabase>()) {
      serviceLocator.registerSingleton<AppDatabase>(AppDatabase());
    }
    if (!serviceLocator.isRegistered<UserContextService>()) {
      serviceLocator.registerLazySingleton<UserContextService>(
        () => UserContextService(),
      );
    }
    if (!serviceLocator.isRegistered<IAppDatabase>()) {
      serviceLocator.registerLazySingleton<IAppDatabase>(
        () => serviceLocator<AppDatabase>(),
      );
    }
    if (!serviceLocator.isRegistered<IDatabase>()) {
      serviceLocator.registerLazySingleton<IDatabase>(
        () => _DatabaseAdapter(serviceLocator<AppDatabase>()),
      );
    }
    // ===== FIREBASE SERVICE (Base registration only) =====
    if (!serviceLocator.isRegistered<FirebaseService>()) {
      serviceLocator.registerSingleton<FirebaseService>(FirebaseService());
    }
    // ===== BACKEND SERVICE =====
    if (!serviceLocator.isRegistered<BackendService>()) {
      serviceLocator.registerSingleton<BackendService>(BackendService());
    }
    // ===== LOCAL DATA SOURCES =====
    if (!serviceLocator.isRegistered<PrefsManager>()) {
      serviceLocator.registerLazySingleton<PrefsManager>(() => PrefsManager());
      final prefsManager = serviceLocator<PrefsManager>();
      await prefsManager.init();
    }
    if (!serviceLocator.isRegistered<DatabaseProvider>()) {
      serviceLocator.registerLazySingleton<DatabaseProvider>(
        () => DatabaseProvider(),
      );
    }
    // ===== UTILITY SERVICES =====
    if (!serviceLocator.isRegistered<ConnectivityChecker>()) {
      serviceLocator.registerLazySingleton<ConnectivityChecker>(
          () => ConnectivityChecker());
    }
    if (!serviceLocator.isRegistered<service_ns.NotificationService>()) {
      serviceLocator.registerLazySingleton<service_ns.NotificationService>(
          () => service_ns.NotificationService());
    }
    if (!serviceLocator.isRegistered<PreferencesService>()) {
      serviceLocator.registerLazySingleton<PreferencesService>(
          () => PreferencesService());
    }
    if (!serviceLocator.isRegistered<ThemeService>()) {
      serviceLocator.registerLazySingleton<ThemeService>(() => ThemeService(
            preferencesService: serviceLocator<PreferencesService>(),
          ));
    }
    // ===== SIMPLE DOMAIN SERVICES =====
    // ===== REGISTER ConversationBufferMemory (if not already done elsewhere) =====
    if (!serviceLocator.isRegistered<ConversationBufferMemory>()) {
      serviceLocator.registerLazySingleton<ConversationBufferMemory>(
        () => ConversationBufferMemory(maxMessages: 20),
      );
    }
    // NOTE: MessageProcessor and TherapyService will be registered in
    if (!serviceLocator.isRegistered<AudioGenerator>()) {
      serviceLocator.registerLazySingleton<AudioGenerator>(() {
        final generator = AudioGenerator(
          ttsService: serviceLocator<ITTSService>(),
          audioFileManager: serviceLocator<IAudioFileManager>(),
          apiClient: serviceLocator<ApiClient>(),
        );
        generator.initializeOnlyIfNeeded().then((_) {
          DependencyStatus.markInitialized('AudioGenerator');
          if (useRefactoredVoicePipeline) {
          } else {
            try {
              final voiceService = serviceLocator<VoiceService>();
              generator.setTTSStateCallback((isSpeaking) {
                voiceService.updateTTSSpeakingState(isSpeaking);
              });
            } catch (_) {}
          }
        });
        return generator;
      });
    }
    if (!serviceLocator.isRegistered<IAudioSettings>()) {
      serviceLocator
          .registerLazySingleton<IAudioSettings>(() => AudioSettings());
    }
    _registerAudioInfra(serviceLocator, useRefactoredVoicePipeline);
    if (useRefactoredVoicePipeline) {
      // Note: TTS service already registered above
      AudioServicesModule.registerServices(serviceLocator);
      if (!serviceLocator.isRegistered<VoiceService>()) {
        serviceLocator.registerLazySingleton<VoiceService>(() {
          final service = VoiceService(
            apiClient: serviceLocator<ApiClient>(),
            audioSettings: serviceLocator<IAudioSettings>(),
          );
          service.initializeOnlyIfNeeded().then((_) {
            DependencyStatus.markInitialized('VoiceService');
          });
          return service;
        });
      }
      DependencyStatus.markInitialized('AudioServicesModule');
    } else {
      if (!serviceLocator.isRegistered<VoiceService>()) {
        serviceLocator.registerLazySingleton<VoiceService>(() {
          final service = VoiceService(
            apiClient: serviceLocator<ApiClient>(),
            audioSettings: serviceLocator<IAudioSettings>(),
          );
          service.initializeOnlyIfNeeded().then((_) {
            DependencyStatus.markInitialized('VoiceService');
          });
          return service;
        });
      }
    }
    if (!serviceLocator.isRegistered<VoicePipelineControllerFactory>()) {
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
        }) {
          return VoicePipelineController(
            dependencies: dependencies,
            micMutedGetter: micMutedGetter ?? defaultMicGetter,
          );
        };
      });
    }
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
    }
    if (!serviceLocator.isRegistered<ChatVoiceFacade>()) {
      serviceLocator.registerFactory<ChatVoiceFacade>(() => ChatVoiceFacade(
            therapyService: serviceLocator<ITherapyService>(),
          ));
    }
    if (!serviceLocator.isRegistered<service_tgs.TherapyGraphService>()) {
      serviceLocator.registerLazySingleton<service_tgs.TherapyGraphService>(
          () => service_tgs.TherapyGraphService());
    }
    if (!serviceLocator.isRegistered<ProgressService>()) {
      serviceLocator
          .registerLazySingleton<ProgressService>(() => ProgressService(
                notificationService:
                    serviceLocator<service_ns.NotificationService>(),
                databaseProvider: serviceLocator<DatabaseProvider>(),
              ));
    }
    if (!serviceLocator.isRegistered<UserProfileService>()) {
      serviceLocator.registerLazySingleton<UserProfileService>(
          () => UserProfileService());
    }
    if (!serviceLocator.isRegistered<service_ms.MemoryService>()) {
      serviceLocator.registerLazySingleton<service_ms.MemoryService>(
        () => service_ms.MemoryService(
          databaseProvider: serviceLocator<DatabaseProvider>(),
          apiClient: serviceLocator<ApiClient>(),
          userProfileService: serviceLocator<UserProfileService>(),
        ),
      );
    }
    if (!serviceLocator.isRegistered<MemoryManager>()) {
      serviceLocator.registerLazySingleton<MemoryManager>(() {
        final manager = MemoryManager(
          memoryService: serviceLocator<service_ms.MemoryService>(),
        );
        return manager;
      });
    }
    if (!serviceLocator.isRegistered<OnboardingService>()) {
      serviceLocator
          .registerLazySingleton<OnboardingService>(() => OnboardingService());
    }
    if (!serviceLocator.isRegistered<AuthCoordinator>()) {
      serviceLocator
          .registerLazySingleton<AuthCoordinator>(() => AuthCoordinator(
                onboardingService: serviceLocator<OnboardingService>(),
              ));
    }
    if (!serviceLocator.isRegistered<AuthService>()) {
      serviceLocator.registerLazySingleton<AuthService>(() => AuthService(
            userProfileService: serviceLocator<UserProfileService>(),
            authEventHandler: serviceLocator<AuthCoordinator>(),
          ));
    }
    try {
      final authCoordinator = serviceLocator<AuthCoordinator>();
      await authCoordinator.init();
    } catch (_) {}
    if (!serviceLocator.isRegistered<NavigationService>()) {
      serviceLocator
          .registerLazySingleton<NavigationService>(() => NavigationService());
    }
    if (!serviceLocator.isRegistered<GroqService>()) {
      serviceLocator.registerLazySingleton<GroqService>(() => GroqService());
    }
    if (!serviceLocator.isRegistered<VADManager>()) {
      serviceLocator.registerLazySingleton<VADManager>(() => VADManager());
    }
    await ServicesModule.register(serviceLocator);
    await DependencyContainer().initialize();
    DependencyStatus.coreServicesRegistered = true;
    _setupCompleter.complete();
  } catch (e, stackTrace) {
    _setupCompleter.completeError(e, stackTrace);
    rethrow; // Re-throw to allow caller to handle the error
  }
}
Future<void> registerApiDependentServices(
    ConfigService configService, ApiClient apiClient) async {
  if (DependencyStatus.apiDependenciesRegistered) {
    DependencyContainer.markReady();
    return;
  }
  final stopwatch = Stopwatch()..start();
  try {
    if (!serviceLocator.isRegistered<ConfigService>()) {
      serviceLocator.registerSingleton<ConfigService>(configService);
    }
    if (!serviceLocator.isRegistered<ApiClient>()) {
      serviceLocator.registerSingleton<ApiClient>(apiClient);
    }
    _prefetchTTSConfigNonBlocking(apiClient);
    if (!serviceLocator.isRegistered<IApiClient>()) {
      serviceLocator.registerLazySingleton<IApiClient>(
        () => serviceLocator<ApiClient>(),
      );
    }
    if (!serviceLocator.isRegistered<SessionScheduleService>()) {
      serviceLocator.registerLazySingleton<SessionScheduleService>(
        () => SessionScheduleService(
          apiClient: serviceLocator<IApiClient>(),
          prefsManager: serviceLocator<PrefsManager>(),
        ),
      );
    }
    if (!serviceLocator.isRegistered<ISessionScheduleService>()) {
      serviceLocator.registerLazySingleton<ISessionScheduleService>(
        () => serviceLocator<SessionScheduleService>(),
      );
    }
    if (!serviceLocator.isRegistered<AuthRepository>()) {
      serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
            apiClient: serviceLocator<IApiClient>(),
          ));
    }
    if (!serviceLocator.isRegistered<UserRepository>()) {
      serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
            apiClient: serviceLocator<IApiClient>(),
          ));
    }
    if (!serviceLocator.isRegistered<SessionRepository>()) {
      serviceLocator
          .registerLazySingleton<SessionRepository>(() => SessionRepository(
                apiClient: serviceLocator<IApiClient>(),
                appDatabase: serviceLocator<IAppDatabase>(),
                userContextService: serviceLocator<UserContextService>(),
              ));
    }
    if (!serviceLocator.isRegistered<MessageRepository>()) {
      serviceLocator
          .registerLazySingleton<MessageRepository>(() => MessageRepository(
                apiClient: serviceLocator<IApiClient>(),
                appDatabase: serviceLocator<IAppDatabase>(),
                userContextService: serviceLocator<UserContextService>(),
              ));
    }
    if (!serviceLocator.isRegistered<MessageProcessor>()) {
      serviceLocator.registerLazySingleton<MessageProcessor>(() {
        final processor = MessageProcessor(
          conversationHistory: serviceLocator<ConversationBufferMemory>(),
          configService: serviceLocator<ConfigService>(),
          groqService: serviceLocator<GroqService>(),
          apiClient: serviceLocator<ApiClient>(),
        );
        DependencyStatus.markInitialized('MessageProcessor');
        return processor;
      });
    }
    if (!serviceLocator.isRegistered<TherapyService>()) {
      serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService(
            messageProcessor: serviceLocator<MessageProcessor>(),
            audioGenerator: serviceLocator<AudioGenerator>(),
            memoryManager: serviceLocator<MemoryManager>(),
            apiClient: serviceLocator<ApiClient>(),
          ));
    }
    if (!serviceLocator.isRegistered<ITherapyService>()) {
      serviceLocator.registerLazySingleton<ITherapyService>(
        () => serviceLocator<TherapyService>(),
      );
    }
    await ServicesModule.register(serviceLocator);
    if (!serviceLocator.isRegistered<SessionFinalizationService>()) {
      serviceLocator
          .registerLazySingleton<SessionFinalizationService>(() =>
              SessionFinalizationService(
                therapyService: serviceLocator<ITherapyService>(),
                progressService: serviceLocator<IProgressService>(),
                sessionRepository: serviceLocator<ISessionRepository>(),
                userContextService: serviceLocator<UserContextService>(),
                apiClient: serviceLocator<IApiClient>(),
              ));
    }
    DependencyStatus.apiDependenciesRegistered = true;
    stopwatch.stop();
    DependencyContainer.markReady();
    if (serviceLocator.isRegistered<ITTSService>()) {
      unawaited(serviceLocator<ITTSService>().initialize());
    }
  } catch (e, stackTrace) {
    DependencyContainer.markFailed(e, stackTrace);
    rethrow;
  }
}
void _prefetchTTSConfigNonBlocking(ApiClient apiClient) {
  unawaited(() async {
    try {
      final TtsConfigDto? remoteTtsConfig = await apiClient.fetchTtsConfig();
      if (remoteTtsConfig != null && remoteTtsConfig.provider.isNotEmpty) {
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
        AudioFormatNegotiator.updateFromConfig(log: true);
        try {
          final ttsService = DependencyContainer().ttsService;
          ttsService.setCachedTTSConfig();
        } catch (e) {}
      }
    } catch (_) {}
  }());
}
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
    return false;
  }
  return true;
}
class _DatabaseAdapter implements IDatabase {
  final AppDatabase _database;
  _DatabaseAdapter(this._database);
  @override
  Future<void> initialize() async {
    await _database.database; // This will initialize the database
  }
  @override
  Future<void> close() async {
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
