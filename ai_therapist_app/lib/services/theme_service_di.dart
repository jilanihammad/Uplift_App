// lib/services/theme_service_di.dart

import 'package:flutter/material.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';

/// Refactored ThemeService using dependency injection instead of service locator
/// This demonstrates the pattern we'll use to replace service locator usage
class ThemeServiceDI extends ChangeNotifier {
  final PreferencesService _preferencesService;

  // Constructor injection - dependency is provided explicitly
  ThemeServiceDI({
    required PreferencesService preferencesService,
  }) : _preferencesService = preferencesService;

  // Get theme mode
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // Initialize theme service
  Future<void> init() async {
    // Get dark mode preference from PreferencesService
    final darkModeEnabled =
        _preferencesService.preferences?.darkModeEnabled ?? false;
    _themeMode = darkModeEnabled ? ThemeMode.dark : ThemeMode.light;
  }

  // Toggle theme
  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;

    // Save preference
    await _preferencesService.updateSinglePreference(
      darkModeEnabled: _themeMode == ThemeMode.dark,
    );

    // Notify listeners
    notifyListeners();
  }

  // Set specific theme
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;

    // Save preference
    await _preferencesService.updateSinglePreference(
      darkModeEnabled: _themeMode == ThemeMode.dark,
    );

    // Notify listeners
    notifyListeners();
  }

  // Get current theme data
  ThemeData get theme =>
      _themeMode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
}

/// Example of how to register this service in a dependency module
/// This would go in a services module file
/*
class ThemeModule {
  static void register(GetIt locator) {
    locator.registerLazySingleton<ThemeServiceDI>(
      () => ThemeServiceDI(
        preferencesService: locator<PreferencesService>(),
      ),
    );
  }
}
*/

/// Example of how to use this service with dependency injection
/// Instead of using service locator pattern
/// Use: final themeService = DependencyContainer().get<ThemeServiceDI>();
/// Or inject it via constructor: ThemeServiceDI themeService;
