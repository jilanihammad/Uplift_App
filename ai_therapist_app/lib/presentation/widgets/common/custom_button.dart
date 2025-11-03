import 'package:flutter/material.dart';

import 'package:ai_therapist_app/config/theme.dart';

/// A custom button widget that supports loading state
///
/// This button has consistent styling and can show a loading indicator
/// when the [isLoading] property is set to true.
class CustomButton extends StatelessWidget {
  /// The text to display on the button
  final String label;

  /// Callback that is called when the button is pressed
  final VoidCallback onPressed;

  /// If true, shows a loading indicator instead of the label
  final bool isLoading;

  /// Optional color for the button, defaults to the primary color of the theme
  final Color? color;

  /// Optional text style for the button label
  final TextStyle? textStyle;

  /// Optional border radius for the button
  final double borderRadius;

  /// Optional padding for the button
  final EdgeInsetsGeometry? padding;

  /// Optional width for the button, if null, the button will expand to fill available width
  final double? width;

  /// Optional height for the button
  final double height;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.textStyle,
    this.borderRadius = 12.0,
    this.padding,
    this.width,
    this.height = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final backgroundColor = color ??
        palette?.accentPrimary ?? theme.colorScheme.primary;
    final onColorBrightness =
        ThemeData.estimateBrightnessForColor(backgroundColor);
    final foregroundColor =
        onColorBrightness == Brightness.dark ? Colors.white : Colors.black;

    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: padding ?? const EdgeInsets.symmetric(vertical: 12.0),
          disabledBackgroundColor:
              backgroundColor.withValues(alpha: isLoading ? 0.6 : 0.7),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24.0,
                height: 24.0,
                child: _LoadingSpinner(),
              )
            : Text(
                label,
                style: textStyle ??
                    TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                    ),
              ),
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final buttonColor = palette?.accentPrimary ?? theme.colorScheme.primary;
    final brightness = ThemeData.estimateBrightnessForColor(buttonColor);
    final spinnerColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;

    return CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
      strokeWidth: 2.0,
    );
  }
}
