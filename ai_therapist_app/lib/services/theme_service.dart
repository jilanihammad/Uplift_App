import 'package:flutter/material.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/i_theme_service.dart';

class ThemeService extends ChangeNotifier implements IThemeService {
  final PreferencesService _preferencesService;

  // Constructor with dependency injection
  ThemeService({
    PreferencesService? preferencesService,
  }) : _preferencesService = preferencesService ??
            DependencyContainer().get<PreferencesService>();

  // Get theme mode
  ThemeMode _themeMode = ThemeMode.light;

  @override
  ThemeMode get themeMode => _themeMode;

  @override
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // Initialize theme service
  @override
  Future<void> init() async {
    // Ensure PreferencesService is initialized first
    await _preferencesService.init();

    // Get dark mode preference from PreferencesService
    final darkModeEnabled =
        _preferencesService.preferences?.darkModeEnabled ?? true;
    _themeMode = darkModeEnabled ? ThemeMode.dark : ThemeMode.light;
  }

  // Toggle theme
  @override
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
  @override
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
  @override
  ThemeData get theme =>
      _themeMode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
}
