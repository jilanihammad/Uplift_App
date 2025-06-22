// lib/di/modules/services_module.dart

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../../services/theme_service.dart';
import '../../services/preferences_service.dart';
import '../../services/navigation_service.dart';

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