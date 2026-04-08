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
import '../../services/session_schedule_service.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/websocket_audio_manager.dart';
import '../../services/memory_manager.dart';
import '../../services/therapy_service.dart';
import '../../services/auth_coordinator.dart';
import '../../services/auth_service.dart';
import '../../services/onboarding_service.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/auth_repository.dart';
class ServicesModule {
  static Future<void> register(GetIt locator) async {
    if (locator.isRegistered<IThemeService>()) {
      return;
    }
    if (!locator.isRegistered<IPreferencesService>()) {
      locator.registerLazySingleton<IPreferencesService>(
        () => locator<PreferencesService>(),
      );
    }
    if (!locator.isRegistered<IThemeService>()) {
      locator.registerLazySingleton<IThemeService>(
        () => locator<ThemeService>(),
      );
    }
    if (!locator.isRegistered<INavigationService>()) {
      locator.registerLazySingleton<INavigationService>(
        () => locator<NavigationService>(),
      );
    }
    if (!locator.isRegistered<IProgressService>()) {
      locator.registerLazySingleton<IProgressService>(
        () => locator<ProgressService>(),
      );
    }
    if (!locator.isRegistered<IUserProfileService>()) {
      locator.registerLazySingleton<IUserProfileService>(
        () => locator<UserProfileService>(),
      );
    }
    if (!locator.isRegistered<IGroqService>()) {
      locator.registerLazySingleton<IGroqService>(
        () => locator<GroqService>(),
      );
    }
    if (locator.isRegistered<SessionScheduleService>() &&
        !locator.isRegistered<ISessionScheduleService>()) {
      locator.registerLazySingleton<ISessionScheduleService>(
        () => locator<SessionScheduleService>(),
      );
    }
    if (!locator.isRegistered<ISessionRepository>()) {
      locator.registerLazySingleton<ISessionRepository>(
        () => locator<SessionRepository>(),
      );
    }
    if (!locator.isRegistered<IUserRepository>()) {
      locator.registerLazySingleton<IUserRepository>(
        () => locator<UserRepository>(),
      );
    }
    if (!locator.isRegistered<IMessageRepository>()) {
      locator.registerLazySingleton<IMessageRepository>(
        () => locator<MessageRepository>(),
      );
    }
    if (!locator.isRegistered<IAuthRepository>()) {
      locator.registerLazySingleton<IAuthRepository>(
        () => locator<AuthRepository>(),
      );
    }
    if (!locator.isRegistered<IWebSocketAudioManager>()) {
      locator.registerLazySingleton<IWebSocketAudioManager>(
        () => locator<WebSocketAudioManager>(),
      );
    }
    if (!locator.isRegistered<IOnboardingService>()) {
      locator.registerLazySingleton<IOnboardingService>(
        () => locator<OnboardingService>(),
      );
    }
    if (!locator.isRegistered<IAuthEventHandler>()) {
      locator.registerLazySingleton<IAuthEventHandler>(
        () => locator<AuthCoordinator>(),
      );
    }
    if (!locator.isRegistered<IAuthService>()) {
      locator.registerLazySingleton<IAuthService>(
        () => locator<AuthService>(),
      );
    }
    if (!locator.isRegistered<IMemoryManager>()) {
      locator.registerLazySingleton<IMemoryManager>(
        () => locator<MemoryManager>(),
      );
    }
    if (!locator.isRegistered<ITherapyService>() &&
        locator.isRegistered<TherapyService>()) {
      locator.registerLazySingleton<ITherapyService>(
        () => locator<TherapyService>(),
      );
    }
  }
  static void registerMocks(GetIt locator) {
    locator.registerLazySingleton<IThemeService>(() => _MockThemeService());
    locator.registerLazySingleton<ThemeService>(
      () => locator<IThemeService>() as ThemeService,
    );
  }
}
class _MockThemeService extends IThemeService {
  ThemeMode _themeMode = ThemeMode.light;
  @override
  ThemeMode get themeMode => _themeMode;
  @override
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  @override
  Future<void> init() async {
  }
  @override
  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
  @override
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
  @override
  ThemeData get theme =>
      _themeMode == ThemeMode.dark ? ThemeData.dark() : ThemeData.light();
}
