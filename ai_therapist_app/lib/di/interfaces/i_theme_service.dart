// lib/di/interfaces/i_theme_service.dart

import 'package:flutter/material.dart';

/// Interface for theme service operations
/// Provides contract for theme management functionality
abstract class IThemeService extends ChangeNotifier {
  // Theme state
  ThemeMode get themeMode;
  bool get isDarkMode;
  ThemeData get theme;

  // Theme operations
  Future<void> init();
  Future<void> toggleTheme();
  Future<void> setTheme(ThemeMode mode);
}
