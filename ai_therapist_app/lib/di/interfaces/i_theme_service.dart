// lib/di/interfaces/i_theme_service.dart
import 'package:flutter/material.dart';
abstract class IThemeService extends ChangeNotifier {
  ThemeMode get themeMode;
  bool get isDarkMode;
  ThemeData get theme;
  Future<void> init();
  Future<void> toggleTheme();
  Future<void> setTheme(ThemeMode mode);
}
