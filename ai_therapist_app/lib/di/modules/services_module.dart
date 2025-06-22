// lib/di/modules/services_module.dart

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../../services/theme_service.dart';
import '../../services/preferences_service.dart';
import '../../services/navigation_service.dart';
import '../../services/progress_service.dart';
import '../../services/user_profile_service.dart';
import '../../services/groq_service.dart';
import '../../services/config_service.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/datasources/local/app_database.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/notification_service.dart' as service_ns;
import '../../services/tts_service.dart';
import '../../services/audio_player_manager.dart';
import '../../services/websocket_audio_manager.dart';

/// Services dependency module
/// Registers application services with proper dependency injection
class ServicesModule {
  static Future<void> register(GetIt locator) async {
    // Prevent duplicate registration
    if (locator.isRegistered<IThemeService>()) {
      return;
    }

    // Register PreferencesService with interface
    if (!locator.isRegistered<PreferencesService>()) {
      locator.registerLazySingleton<PreferencesService>(
        () => PreferencesService(),
      );
    }
    
    // Register interface for PreferencesService
    locator.registerLazySingleton<IPreferencesService>(
      () => locator<PreferencesService>(),
    );

    // Register ThemeService with dependency injection
    locator.registerLazySingleton<IThemeService>(
      () => ThemeService(
        preferencesService: locator<PreferencesService>(),
      ),
    );

    // Also register concrete class for backward compatibility
    locator.registerLazySingleton<ThemeService>(
      () => locator<IThemeService>() as ThemeService,
    );

    // Register NavigationService (no dependencies)
    locator.registerLazySingleton<NavigationService>(
      () => NavigationService(),
    );
    
    // Register interface for NavigationService
    locator.registerLazySingleton<INavigationService>(
      () => locator<NavigationService>(),
    );

    // Register ProgressService with dependency injection
    locator.registerLazySingleton<ProgressService>(
      () => ProgressService(
        notificationService: locator<service_ns.NotificationService>(),
      ),
    );
    
    // Register interface for ProgressService
    locator.registerLazySingleton<IProgressService>(
      () => locator<ProgressService>(),
    );

    // Register UserProfileService (no dependencies)
    locator.registerLazySingleton<UserProfileService>(
      () => UserProfileService(),
    );
    
    // Register interface for UserProfileService
    locator.registerLazySingleton<IUserProfileService>(
      () => locator<UserProfileService>(),
    );

    // Register GroqService with dependencies from core module
    locator.registerLazySingleton<GroqService>(
      () => GroqService(
        configService: locator<ConfigService>(),
        apiClient: locator<ApiClient>(),
      ),
    );
    
    // Register interface for GroqService
    locator.registerLazySingleton<IGroqService>(
      () => locator<GroqService>(),
    );

    // Register SessionRepository with dependencies from core module
    locator.registerLazySingleton<SessionRepository>(
      () => SessionRepository(
        apiClient: locator<ApiClient>(),
        appDatabase: locator<AppDatabase>(),
      ),
    );
    
    // Register interface for SessionRepository
    locator.registerLazySingleton<ISessionRepository>(
      () => locator<SessionRepository>(),
    );

    // Register AudioPlayerManager (no dependencies)
    locator.registerLazySingleton<AudioPlayerManager>(
      () => AudioPlayerManager(),
    );

    // Register TTSService with dependencies
    locator.registerLazySingleton<TTSService>(
      () => TTSService(
        audioPlayerManager: locator<AudioPlayerManager>(),
        apiClient: locator<ApiClient>(),
      ),
    );
    
    // Register interface for TTSService
    locator.registerLazySingleton<ITTSService>(
      () => locator<TTSService>(),
    );

    // Register WebSocketAudioManager with dependencies
    locator.registerLazySingleton<WebSocketAudioManager>(
      () => WebSocketAudioManager(
        apiClient: locator<ApiClient>(),
      ),
    );
    
    // Register interface for WebSocketAudioManager
    locator.registerLazySingleton<IWebSocketAudioManager>(
      () => locator<WebSocketAudioManager>(),
    );
  }

  static void registerMocks(GetIt locator) {
    // Register mock implementations for testing
    locator.registerLazySingleton<IThemeService>(() => _MockThemeService());
    locator.registerLazySingleton<ThemeService>(
      () => locator<IThemeService>() as ThemeService,
    );
  }
}

// Mock implementation for testing
class _MockThemeService extends IThemeService {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  ThemeMode get themeMode => _themeMode;

  @override
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  @override
  Future<void> init() async {
    // Mock initialization
  }

  @override
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  @override
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  @override
  ThemeData get theme => _themeMode == ThemeMode.dark 
      ? ThemeData.dark() 
      : ThemeData.light();
}