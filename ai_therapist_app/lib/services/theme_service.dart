import 'package:flutter/material.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/di/service_locator.dart';

class ThemeService extends ChangeNotifier {
  final PreferencesService _preferencesService =
      serviceLocator<PreferencesService>();

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
