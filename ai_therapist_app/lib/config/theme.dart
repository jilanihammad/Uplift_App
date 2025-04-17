import 'package:flutter/material.dart';

// App theme configuration
class AppTheme {
  // Primary colors
  static const Color primaryColor = Color(0xFF5E72E4); // Indigo blue
  static const Color primaryLightColor = Color(0xFF7B8FF7);
  static const Color primaryDarkColor = Color(0xFF324AB2);

  // Secondary colors
  static const Color secondaryColor = Color(0xFF11CDEF); // Cyan
  static const Color secondaryLightColor = Color(0xFF4FE3FF);
  static const Color secondaryDarkColor = Color(0xFF0097BD);

  // Accent colors
  static const Color accentColor = Color(0xFFFB6340); // Orange
  static const Color accentLightColor = Color(0xFFFF8F73);
  static const Color accentDarkColor = Color(0xFFC33A1B);

  // Background colors
  static const Color backgroundColor = Color(0xFFF8F9FE);
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Colors.white;

  // Text colors
  static const Color textPrimaryColor = Color(0xFF525F7F);
  static const Color textSecondaryColor = Color(0xFF8898AA);
  static const Color textLightColor = Color(0xFFADB5BD);

  // Status colors
  static const Color successColor = Color(0xFF2DCE89);
  static const Color errorColor = Color(0xFFF5365C);
  static const Color warningColor = Color(0xFFFFB236);
  static const Color infoColor = Color(0xFF11CDEF);

  // Get the theme data
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        background: backgroundColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimaryColor,
        onBackground: textPrimaryColor,
        onError: Colors.white,
      ),
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primaryColor,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: textLightColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: textLightColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      textTheme: const TextTheme(
        displayLarge:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        displayMedium:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        displaySmall:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        headlineLarge:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        headlineMedium:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        headlineSmall:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        titleLarge:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        titleMedium:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        titleSmall:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimaryColor),
        bodyMedium: TextStyle(color: textPrimaryColor),
        bodySmall: TextStyle(color: textSecondaryColor),
        labelLarge:
            TextStyle(color: textPrimaryColor, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textPrimaryColor),
        labelSmall: TextStyle(color: textSecondaryColor),
      ),
      fontFamily: 'Poppins',
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE9ECEF),
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: textPrimaryColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimaryColor,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: textPrimaryColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }
}
