import 'package:flutter/material.dart';

// App theme configuration
class AppTheme {
  // Primary colors - Twitter blue (used for navigation active items)
  static const Color primaryColor = Color(0xFF1DA1F2); // Twitter blue
  static const Color primaryLightColor =
      Color(0xFF60C4FF); // Lighter Twitter blue
  static const Color primaryDarkColor =
      Color(0xFF0C7BBF); // Darker Twitter blue

  // CalDiet colors
  static const Color caldietPrimaryColor = Colors.black;
  static const Color caldietAccentBlue = Color(0xFF4285F4);
  static const Color caldietBackgroundGray = Color(0xFFF8F8F8);
  static const Color caldietTextPrimary = Color(0xFF333333);
  static const Color caldietTextSecondary = Color(0xFF757575);

  // Button colors - brighter blue similar to Twitter blue in dark mode
  static const Color buttonColor = Color(0xFF38B6FF);
  static const Color buttonLightColor = Color(0xFF7DCFFF);
  static const Color buttonDarkColor = Color(0xFF1C92DB);

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

  // Dark mode colors
  static const Color darkBackgroundColor = Color(0xFF121212);
  static const Color darkCardColor = Color(0xFF1E1E1E);
  static const Color darkSurfaceColor = Color(0xFF1E1E1E);

  // Text colors
  static const Color textPrimaryColor = Color(0xFF525F7F);
  static const Color textSecondaryColor = Color(0xFF8898AA);
  static const Color textLightColor = Color(0xFFADB5BD);
  static const Color darkTextPrimaryColor = Color(0xFFEAEAEA);
  static const Color darkTextSecondaryColor = Color(0xFFBBBBBB);

  // Status colors
  static const Color successColor = Color(0xFF2DCE89);
  static const Color errorColor = Color(0xFFF5365C);
  static const Color warningColor = Color(0xFFFFB236);
  static const Color infoColor = Color(0xFF11CDEF);

  // Get the light theme data
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: caldietPrimaryColor,
        secondary: caldietAccentBlue,
        surface: Colors.white,
        background: caldietBackgroundGray,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: caldietTextPrimary,
        onBackground: caldietTextPrimary,
        onError: Colors.white,
      ),
      primaryColor: caldietPrimaryColor,
      scaffoldBackgroundColor: caldietBackgroundGray,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: caldietPrimaryColor,
        unselectedItemColor: caldietTextSecondary,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 1, // Lower elevation for cleaner look
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: caldietTextPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1, // Lower elevation for cleaner look
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)), // More rounded corners
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: caldietPrimaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 2,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: caldietAccentBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: caldietAccentBlue,
          side: BorderSide(color: caldietAccentBlue),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
          borderSide: const BorderSide(color: caldietAccentBlue, width: 2),
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
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        displayMedium:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        displaySmall:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        headlineLarge:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        headlineMedium:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        headlineSmall:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        titleLarge:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        titleMedium:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        titleSmall:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: caldietTextPrimary),
        bodyMedium: TextStyle(color: caldietTextPrimary),
        bodySmall: TextStyle(color: caldietTextSecondary),
        labelLarge:
            TextStyle(color: caldietTextPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: caldietTextPrimary),
        labelSmall: TextStyle(color: caldietTextSecondary),
      ),
      fontFamily: 'Poppins',
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEEEEEE), // Lighter divider for CalDiet style
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: caldietTextPrimary.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: caldietTextPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: caldietTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  // Get the dark theme data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: darkSurfaceColor,
        background: darkBackgroundColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimaryColor,
        onBackground: darkTextPrimaryColor,
        onError: Colors.white,
      ),
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackgroundColor,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: darkTextSecondaryColor,
        backgroundColor: darkCardColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCardColor,
        foregroundColor: darkTextPrimaryColor,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: darkCardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 2,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: buttonColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: buttonColor,
          side: BorderSide(color: buttonColor),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: textLightColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: textLightColor.withOpacity(0.3)),
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
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        displayMedium:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        displaySmall:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        headlineLarge:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        headlineMedium:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        headlineSmall:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        titleLarge:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        titleMedium:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        titleSmall:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: darkTextPrimaryColor),
        bodyMedium: TextStyle(color: darkTextPrimaryColor),
        bodySmall: TextStyle(color: darkTextSecondaryColor),
        labelLarge:
            TextStyle(color: darkTextPrimaryColor, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: darkTextPrimaryColor),
        labelSmall: TextStyle(color: darkTextSecondaryColor),
      ),
      fontFamily: 'Poppins',
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3A3A3A),
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkTextPrimaryColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: darkBackgroundColor),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCardColor,
        contentTextStyle: const TextStyle(color: darkTextPrimaryColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: darkCardColor,
        titleTextStyle: const TextStyle(
          color: darkTextPrimaryColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }
}
