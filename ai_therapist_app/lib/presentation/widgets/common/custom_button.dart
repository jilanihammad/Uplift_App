import 'package:flutter/material.dart';

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
    Key? key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.textStyle,
    this.borderRadius = 12.0,
    this.padding,
    this.width,
    this.height = 48.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: padding ?? const EdgeInsets.symmetric(vertical: 12.0),
          disabledBackgroundColor: color?.withOpacity(0.7) ?? Theme.of(context).primaryColor.withOpacity(0.7),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24.0,
                height: 24.0,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              )
            : Text(
                label,
                style: textStyle ?? const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
} 