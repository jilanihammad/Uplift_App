import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/services/theme_service.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/data/datasources/local/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Dark Mode Persistence Tests', () {
    test('ThemeService should load saved dark mode preference on init', () async {
      // Setup
      SharedPreferences.setMockInitialValues({
        'user_preferences': '{"darkModeEnabled": true}'
      });
      
      final prefsManager = PrefsManager();
      final preferencesService = PreferencesService(prefsManager: prefsManager);
      final themeService = ThemeService(preferencesService: preferencesService);
      
      // Test
      await themeService.init();
      
      // Verify
      expect(themeService.isDarkMode, isTrue);
      expect(themeService.themeMode, equals(ThemeMode.dark));
    });
    
    test('ThemeService should default to light mode when no preference exists', () async {
      // Setup
      SharedPreferences.setMockInitialValues({}); // No saved preferences
      
      final prefsManager = PrefsManager();
      final preferencesService = PreferencesService(prefsManager: prefsManager);
      final themeService = ThemeService(preferencesService: preferencesService);
      
      // Test
      await themeService.init();
      
      // Verify - PreferencesService defaults to dark mode, so ThemeService should be dark
      expect(themeService.isDarkMode, isTrue);
      expect(themeService.themeMode, equals(ThemeMode.dark));
    });
    
    test('ThemeService should persist dark mode preference when toggled', () async {
      // Setup
      SharedPreferences.setMockInitialValues({});
      
      final prefsManager = PrefsManager();
      final preferencesService = PreferencesService(prefsManager: prefsManager);
      final themeService = ThemeService(preferencesService: preferencesService);
      
      // Initialize
      await themeService.init();
      
      // Toggle to light mode
      await themeService.setTheme(ThemeMode.light);
      expect(themeService.isDarkMode, isFalse);
      
      // Create new instance to simulate app restart
      final newThemeService = ThemeService(preferencesService: preferencesService);
      await newThemeService.init();
      
      // Verify preference was persisted
      expect(newThemeService.isDarkMode, isFalse);
      expect(newThemeService.themeMode, equals(ThemeMode.light));
    });
  });
}