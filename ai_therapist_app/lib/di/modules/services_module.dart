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
import '../../services/message_processor.dart';
import '../../services/audio_generator.dart';
import '../../services/memory_manager.dart';
import '../../services/memory_service.dart' as memory_svc;
import '../../services/therapy_service.dart';
import '../../blocs/voice_session_bloc.dart' as voice_bloc;
import '../../services/langchain/custom_langchain.dart' as langchain;
import '../interfaces/i_therapy_service.dart';
import '../../services/auth_coordinator.dart';
import '../../services/auth_service.dart';
import '../../services/onboarding_service.dart';
import '../../data/datasources/local/database_provider.dart';
import '../interfaces/i_memory_manager.dart';

/// Services dependency module
/// Registers application services with proper dependency injection
class ServicesModule {
  static Future<void> register(GetIt locator) async {
    // Prevent duplicate registration
    if (locator.isRegistered<IThemeService>()) {
      return;
    }

    // Only register interface mappings for services already registered in service_locator.dart
    
    // Register interface for PreferencesService (already registered)
    if (!locator.isRegistered<IPreferencesService>()) {
      locator.registerLazySingleton<IPreferencesService>(
        () => locator<PreferencesService>(),
      );
    }

    // Register interface for ThemeService (already registered)
    if (!locator.isRegistered<IThemeService>()) {
      locator.registerLazySingleton<IThemeService>(
        () => locator<ThemeService>(),
      );
    }

    // Register interface for NavigationService (already registered)
    if (!locator.isRegistered<INavigationService>()) {
      locator.registerLazySingleton<INavigationService>(
        () => locator<NavigationService>(),
      );
    }

    // Register interface for ProgressService (already registered)
    if (!locator.isRegistered<IProgressService>()) {
      locator.registerLazySingleton<IProgressService>(
        () => locator<ProgressService>(),
      );
    }
    // Register interface for UserProfileService (already registered)
    if (!locator.isRegistered<IUserProfileService>()) {
      locator.registerLazySingleton<IUserProfileService>(
        () => locator<UserProfileService>(),
      );
    }

    // Register interface for GroqService (already registered)
    if (!locator.isRegistered<IGroqService>()) {
      locator.registerLazySingleton<IGroqService>(
        () => locator<GroqService>(),
      );
    }

    // Register interface for SessionRepository (already registered)
    if (!locator.isRegistered<ISessionRepository>()) {
      locator.registerLazySingleton<ISessionRepository>(
        () => locator<SessionRepository>(),
      );
    }

    // Register interface for TTSService (already registered via AudioServicesModule)
    if (!locator.isRegistered<ITTSService>()) {
      locator.registerLazySingleton<ITTSService>(
        () => locator<TTSService>(),
      );
    }

    // Register interface for WebSocketAudioManager (already registered via AudioServicesModule)
    if (!locator.isRegistered<IWebSocketAudioManager>()) {
      locator.registerLazySingleton<IWebSocketAudioManager>(
        () => locator<WebSocketAudioManager>(),
      );
    }
    // Register interface for OnboardingService (already registered)
    if (!locator.isRegistered<IOnboardingService>()) {
      locator.registerLazySingleton<IOnboardingService>(
        () => locator<OnboardingService>(),
      );
    }

    // Register interface for AuthCoordinator (already registered)
    if (!locator.isRegistered<IAuthEventHandler>()) {
      locator.registerLazySingleton<IAuthEventHandler>(
        () => locator<AuthCoordinator>(),
      );
    }

    // Register interface for AuthService (already registered)
    if (!locator.isRegistered<IAuthService>()) {
      locator.registerLazySingleton<IAuthService>(
        () => locator<AuthService>(),
      );
    }

    // Register interface for MemoryManager (already registered)
    if (!locator.isRegistered<IMemoryManager>()) {
      locator.registerLazySingleton<IMemoryManager>(
        () => locator<MemoryManager>(),
      );
    }
    // Register interface for TherapyService (only if concrete service is registered)
    if (!locator.isRegistered<ITherapyService>() && locator.isRegistered<TherapyService>()) {
      locator.registerLazySingleton<ITherapyService>(
        () => locator<TherapyService>(),
      );
    }
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