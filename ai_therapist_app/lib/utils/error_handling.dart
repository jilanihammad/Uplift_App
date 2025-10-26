import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Safely executes an operation with timeout protection
Future<T?> safeOperation<T>(
  Future<T> Function() operation, {
  int timeoutSeconds = 5,
  String operationName = 'Unknown',
}) async {
  try {
    return await operation().timeout(
      Duration(seconds: timeoutSeconds),
      onTimeout: () {
        debugPrint('$operationName timed out after $timeoutSeconds seconds');
        throw TimeoutException(
            'Operation timed out', Duration(seconds: timeoutSeconds));
      },
    );
  } catch (e, stack) {
    debugPrint('Error in $operationName: $e');
    if (kDebugMode) {
      debugPrint('Stack trace: $stack');
    }
    return null;
  }
}

/// A widget that catches errors in its child widget tree
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, dynamic error)? errorBuilder;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  ErrorBoundaryState createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  bool hasError = false;
  dynamic errorDetails;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, errorDetails);
      }

      // Default error widget
      return Material(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  kDebugMode
                      ? errorDetails?.toString() ?? 'Unknown error'
                      : 'Please try again',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  child: const Text('Retry'),
                  onPressed: () {
                    setState(() => hasError = false);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _ErrorInterceptor(
      child: widget.child,
      onError: (error) {
        setState(() {
          hasError = true;
          errorDetails = error;
        });
      },
    );
  }
}

/// Internal widget that intercepts errors
class _ErrorInterceptor extends StatefulWidget {
  final Widget child;
  final Function(dynamic) onError;

  const _ErrorInterceptor({
    required this.child,
    required this.onError,
  });

  @override
  _ErrorInterceptorState createState() => _ErrorInterceptorState();
}

class _ErrorInterceptorState extends State<_ErrorInterceptor> {
  late final FlutterExceptionHandler? _originalOnError;

  @override
  void initState() {
    super.initState();
    _originalOnError = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
  }

  @override
  void dispose() {
    FlutterError.onError = _originalOnError;
    super.dispose();
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    widget.onError(details.exception);
    if (_originalOnError != null) {
      _originalOnError!(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return widget.child;
    } catch (e, stack) {
      debugPrint('Error caught in _ErrorInterceptor: $e');
      debugPrint('Stack trace: $stack');
      widget.onError(e);
      return const SizedBox();
    }
  }
}

/// A widget that safely builds UI components
class SafeBuilder extends StatelessWidget {
  final Widget Function(BuildContext) builder;
  final Widget? fallback;
  final Function(dynamic error)? onError;

  const SafeBuilder({
    super.key,
    required this.builder,
    this.fallback,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return builder(context);
    } catch (e, stack) {
      debugPrint('Error building widget: $e');
      debugPrint('Stack trace: $stack');
      if (onError != null) {
        onError!(e);
      }
      return fallback ?? const SizedBox();
    }
  }
}
