import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color surfaceLow;
  final Color surface;
  final Color surfaceHigh;
  final Color accentPrimary;
  final Color accentSecondary;

  const AppPalette({
    required this.surfaceLow,
    required this.surface,
    required this.surfaceHigh,
    required this.accentPrimary,
    required this.accentSecondary,
  });

  @override
  AppPalette copyWith({
    Color? surfaceLow,
    Color? surface,
    Color? surfaceHigh,
    Color? accentPrimary,
    Color? accentSecondary,
  }) {
    return AppPalette(
      surfaceLow: surfaceLow ?? this.surfaceLow,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
    );
  }

  @override
  AppPalette lerp(
    covariant ThemeExtension<AppPalette>? other,
    double t,
  ) {
    if (other is! AppPalette) {
      return this;
    }

    return AppPalette(
      surfaceLow: Color.lerp(surfaceLow, other.surfaceLow, t) ?? surfaceLow,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceHigh:
          Color.lerp(surfaceHigh, other.surfaceHigh, t) ?? surfaceHigh,
      accentPrimary:
          Color.lerp(accentPrimary, other.accentPrimary, t) ?? accentPrimary,
      accentSecondary:
          Color.lerp(accentSecondary, other.accentSecondary, t) ??
              accentSecondary,
    );
  }
}

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

  static const AppPalette lightPalette = AppPalette(
    surfaceLow: Color(0xFFF3F5F8),
    surface: Color(0xFFFAFBFD),
    surfaceHigh: Colors.white,
    accentPrimary: Color(0xFF4B6CB7),
    accentSecondary: Color(0xFF86A6FF),
  );

  static const AppPalette darkPalette = AppPalette(
    surfaceLow: Color(0xFF1A1C1E),
    surface: darkSurfaceColor,
    surfaceHigh: Color(0xFF26282B),
    accentPrimary: buttonColor,
    accentSecondary: Color(0xFF70C8FF),
  );

  // Status colors
  static const Color successColor = Color(0xFF2DCE89);
  static const Color errorColor = Color(0xFFF5365C);
  static const Color warningColor = Color(0xFFFFB236);
  static const Color infoColor = Color(0xFF11CDEF);

  // Get the light theme data
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme();
    final appliedTextTheme = baseTextTheme.apply(
      bodyColor: caldietTextPrimary,
      displayColor: caldietTextPrimary,
    );
    final enrichedTextTheme = appliedTextTheme.copyWith(
      displayLarge:
          appliedTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.w600),
      displayMedium:
          appliedTextTheme.displayMedium?.copyWith(fontWeight: FontWeight.w600),
      displaySmall:
          appliedTextTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge:
          appliedTextTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium:
          appliedTextTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall:
          appliedTextTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge:
          appliedTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium:
          appliedTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall:
          appliedTextTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge:
          appliedTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodySmall:
          appliedTextTheme.bodySmall?.copyWith(color: caldietTextSecondary),
      labelSmall:
          appliedTextTheme.labelSmall?.copyWith(color: caldietTextSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light().copyWith(
        primary: caldietPrimaryColor,
        secondary: lightPalette.accentPrimary,
        surface: lightPalette.surface,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: caldietTextPrimary,
        onError: Colors.white,
      ),
      primaryColor: caldietPrimaryColor,
      scaffoldBackgroundColor: lightPalette.surfaceLow,
      extensions: const <ThemeExtension<dynamic>>[
        lightPalette,
      ],
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: caldietPrimaryColor,
        unselectedItemColor: caldietTextSecondary,
        backgroundColor: lightPalette.surfaceHigh,
        type: BottomNavigationBarType.fixed,
        elevation: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: caldietTextPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightPalette.surfaceHigh,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPalette.accentPrimary,
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
          foregroundColor: lightPalette.accentPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightPalette.accentPrimary,
          side: BorderSide(color: lightPalette.accentPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightPalette.surfaceHigh,
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
          borderSide:
              BorderSide(color: lightPalette.accentPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      textTheme: enrichedTextTheme,
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEEEEEE),
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: caldietTextPrimary.withValues(alpha: 0.9),
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
        backgroundColor: lightPalette.surfaceHigh,
        titleTextStyle: GoogleFonts.inter(
          color: caldietTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Get the dark theme data
  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    final appliedTextTheme = baseTextTheme.apply(
      bodyColor: darkTextPrimaryColor,
      displayColor: darkTextPrimaryColor,
    );
    final enrichedTextTheme = appliedTextTheme.copyWith(
      displayLarge:
          appliedTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.w600),
      displayMedium:
          appliedTextTheme.displayMedium?.copyWith(fontWeight: FontWeight.w600),
      displaySmall:
          appliedTextTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge:
          appliedTextTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium:
          appliedTextTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall:
          appliedTextTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge:
          appliedTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium:
          appliedTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall:
          appliedTextTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge:
          appliedTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodySmall:
          appliedTextTheme.bodySmall?.copyWith(color: darkTextSecondaryColor),
      labelSmall:
          appliedTextTheme.labelSmall?.copyWith(color: darkTextSecondaryColor),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark().copyWith(
        primary: primaryColor,
        secondary: darkPalette.accentPrimary,
        surface: darkPalette.surface,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimaryColor,
        onError: Colors.white,
      ),
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackgroundColor,
      extensions: const <ThemeExtension<dynamic>>[
        darkPalette,
      ],
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
        color: darkPalette.surfaceHigh,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPalette.accentPrimary,
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
          foregroundColor: darkPalette.accentPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPalette.accentPrimary,
          side: BorderSide(color: darkPalette.accentPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkPalette.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: textLightColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: textLightColor.withValues(alpha: 0.3)),
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
      textTheme: enrichedTextTheme,
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3A3A3A),
        space: 1,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkTextPrimaryColor.withValues(alpha: 0.9),
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
        backgroundColor: darkPalette.surfaceHigh,
        titleTextStyle: GoogleFonts.inter(
          color: darkTextPrimaryColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
