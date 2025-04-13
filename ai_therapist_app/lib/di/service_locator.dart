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

import '../utils/connectivity_checker.dart';

final serviceLocator = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Check if already initialized to prevent duplicate registrations
  if (serviceLocator.isRegistered<PrefsManager>()) {
    return;
  }
  
  // Initialize configuration service first
  final configService = ConfigService();
  serviceLocator.registerSingleton<ConfigService>(configService);
  await configService.init();
  
  // Register Firebase service
  serviceLocator.registerSingleton<FirebaseService>(FirebaseService());
  
  // Get configuration from ConfigService
  final baseUrl = configService.llmApiEndpoint;

  // Local Data Sources
  serviceLocator.registerLazySingleton<PrefsManager>(() => PrefsManager());
  serviceLocator.registerLazySingleton<AppDatabase>(() => AppDatabase());
  serviceLocator.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // Initialize PrefsManager
  final prefsManager = serviceLocator<PrefsManager>();
  await prefsManager.init();

  // Remote Data Source
  serviceLocator.registerLazySingleton<ApiClient>(() => ApiClient(
    baseUrl: baseUrl,
  ));

  // Repositories
  serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
    baseUrl: baseUrl,
    apiClient: serviceLocator<ApiClient>(),
  ));

  serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
    apiClient: serviceLocator<ApiClient>(),
  ));

  serviceLocator.registerLazySingleton<SessionRepository>(() => SessionRepository(
    apiClient: serviceLocator<ApiClient>(),
    appDatabase: serviceLocator<AppDatabase>(),
  ));

  serviceLocator.registerLazySingleton<MessageRepository>(() => MessageRepository(
    apiClient: serviceLocator<ApiClient>(),
    appDatabase: serviceLocator<AppDatabase>(),
  ));

  // Services - register without initializing
  serviceLocator.registerLazySingleton<AuthService>(() => AuthService());
  serviceLocator.registerLazySingleton<NotificationService>(() => NotificationService());
  serviceLocator.registerLazySingleton<ConnectivityChecker>(() => ConnectivityChecker());
  serviceLocator.registerLazySingleton<PreferencesService>(() => PreferencesService());
  serviceLocator.registerLazySingleton<VoiceService>(() => VoiceService());
  serviceLocator.registerLazySingleton<TherapyService>(() => TherapyService());
  serviceLocator.registerLazySingleton<MemoryService>(() => MemoryService());
  serviceLocator.registerLazySingleton<TherapyGraphService>(() => TherapyGraphService());
  serviceLocator.registerLazySingleton<ProgressService>(() => ProgressService(
    notificationService: serviceLocator<NotificationService>()
  ));
  serviceLocator.registerLazySingleton<UserProfileService>(() => UserProfileService());
  serviceLocator.registerLazySingleton<OnboardingService>(() => OnboardingService());
  
  // Note: Initialization of services is now moved to main.dart
  // to properly handle initialization errors
}