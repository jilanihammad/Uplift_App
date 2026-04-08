import 'package:flutter/material.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/i_theme_service.dart';
class ThemeService extends ChangeNotifier implements IThemeService {
  final PreferencesService _preferencesService;
  ThemeService({
    PreferencesService? preferencesService,
  }) : _preferencesService = preferencesService ??
            DependencyContainer().get<PreferencesService>();
  ThemeMode _themeMode = ThemeMode.light;
  @override
  ThemeMode get themeMode => _themeMode;
  @override
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  @override
  Future<void> init() async {
    await _preferencesService.init();
    final darkModeEnabled =
        _preferencesService.preferences?.darkModeEnabled ?? true;
    _themeMode = darkModeEnabled ? ThemeMode.dark : ThemeMode.light;
  }
  @override
  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await _preferencesService.updateSinglePreference(
      darkModeEnabled: _themeMode == ThemeMode.dark,
    );
    notifyListeners();
  }
  @override
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _preferencesService.updateSinglePreference(
      darkModeEnabled: _themeMode == ThemeMode.dark,
    );
    notifyListeners();
  }
  @override
  ThemeData get theme =>
      _themeMode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
}
