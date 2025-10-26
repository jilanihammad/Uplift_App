import 'package:flutter/material.dart';

/// Custom icon provider for the Uplift therapy app
class UpliftIcons {
  /// Returns a therapy-themed icon widget for the app logo
  /// Size parameter controls the dimensions of the icon
  static Widget therapyLogo({double size = 120.0, Color? color}) {
    final primaryColor = color ?? const Color(0xFF5E72E4);
    const accentColor = Color(0xFFFB6340);
    const secondaryColor = Color(0xFF11CDEF);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primaryColor,
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Heart shape
            Icon(
              Icons.favorite,
              size: size * 0.6,
              color: accentColor,
            ),

            // Mindfulness symbol
            Positioned(
              top: size * 0.35,
              child: Icon(
                Icons.psychology,
                size: size * 0.3,
                color: secondaryColor,
              ),
            ),

            // Small decoration dots
            Positioned(
              top: size * 0.25,
              left: size * 0.32,
              child: Container(
                width: size * 0.05,
                height: size * 0.05,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),

            Positioned(
              top: size * 0.25,
              right: size * 0.32,
              child: Container(
                width: size * 0.05,
                height: size * 0.05,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns a widget that uses UpliftIcons if the image asset fails to load
  static Widget logoWithFallback({
    required String imagePath,
    double size = 120.0,
    Color? color,
  }) {
    return Image.asset(
      imagePath,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) {
        return therapyLogo(size: size, color: color);
      },
    );
  }
}
