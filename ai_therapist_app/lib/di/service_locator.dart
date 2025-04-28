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

import '../utils/connectivity_checker.dart';

final serviceLocator = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Check if already initialized
  if (serviceLocator.isRegistered<PrefsManager>()) {
    return;
  }

  // Register ConfigService, ApiClient, TherapyService in main.dart now
  // REMOVE: final configService = ConfigService();
  // REMOVE: serviceLocator.registerSingleton<ConfigService>(configService);

  // Register Firebase service (assuming synchronous or handled elsewhere)
  serviceLocator.registerSingleton<FirebaseService>(FirebaseService());

  // Register BackendService (assuming synchronous or handled elsewhere)
  serviceLocator.registerSingleton<BackendService>(BackendService());

  // REMOVE: final baseUrl = configService.llmApiEndpoint;
  // REMOVE: debugPrint(...);

  // Local Data Sources
  serviceLocator.registerLazySingleton<PrefsManager>(() => PrefsManager());
  serviceLocator.registerLazySingleton<AppDatabase>(() => AppDatabase());
  serviceLocator.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // Initialize PrefsManager (keep this sync init here)
  final prefsManager = serviceLocator<PrefsManager>();
  await prefsManager.init();

  // Remote Data Source - REMOVE ApiClient registration, will be done in main.dart
  // REMOVE: serviceLocator.registerSingleton<ApiClient>(ApiClient(
  // REMOVE:       configService: configService,
  // REMOVE:     ));

  // Repositories - REMOVE registrations needing ApiClient, will be done in main.dart
  // REMOVE: serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
  // REMOVE:       apiClient: serviceLocator<ApiClient>(),
  // REMOVE:     ));
  // REMOVE: serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
  // REMOVE:       apiClient: serviceLocator<ApiClient>(),
  // REMOVE:     ));
  // REMOVE: serviceLocator.registerLazySingleton<SessionRepository>(() => SessionRepository(
  // REMOVE:       apiClient: serviceLocator<ApiClient>(),
  // REMOVE:       appDatabase: serviceLocator<AppDatabase>(),
  // REMOVE:     ));
  // REMOVE: serviceLocator.registerLazySingleton<MessageRepository>(() => MessageRepository(
  // REMOVE:       apiClient: serviceLocator<ApiClient>(),
  // REMOVE:       appDatabase: serviceLocator<AppDatabase>(),
  // REMOVE:     ));

  // Services - Register ones NOT initialized async in main.dart
  // REMOVE: serviceLocator.registerLazySingleton<AuthService>(() => AuthService()); // Assume needs repo
  serviceLocator
      .registerLazySingleton<NotificationService>(() => NotificationService());
  serviceLocator
      .registerLazySingleton<ConnectivityChecker>(() => ConnectivityChecker());
  serviceLocator
      .registerLazySingleton<PreferencesService>(() => PreferencesService());
  serviceLocator.registerLazySingleton<ThemeService>(() => ThemeService());
  serviceLocator.registerLazySingleton<VoiceService>(
      () => VoiceService()); // Keep if init is simple/separate
  // REMOVE: serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService());
  serviceLocator.registerLazySingleton<MemoryService>(
      () => MemoryService()); // Keep if init is simple/separate
  serviceLocator
      .registerLazySingleton<TherapyGraphService>(() => TherapyGraphService());
  serviceLocator.registerLazySingleton<ProgressService>(() => ProgressService(
      notificationService: serviceLocator<NotificationService>()));
  serviceLocator.registerLazySingleton<UserProfileService>(
      () => UserProfileService()); // Keep if init handled separately
  serviceLocator.registerLazySingleton<OnboardingService>(
      () => OnboardingService()); // Keep if init handled separately
}
