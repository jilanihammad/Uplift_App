# Migration Guide: Converting debugPrint to LoggingService

This document provides a guide for migrating from direct use of `debugPrint()` to our new `LoggingService`.

## Key Benefits

1. **Consistent logging across the app**
2. **Debug-only logs don't leak into release builds**
3. **Structured logging with tags and error details**
4. **Integration with crash reporting platforms**
5. **Fine-grained control over log verbosity**

## Steps for Migration

### 1. Import the LoggingService

Add this import to your file:

```dart
import 'package:ai_therapist_app/utils/logging_service.dart';
```

### 2. Convert debugPrint() calls

| Instead of | Use |
|------------|-----|
| `debugPrint('Message')` | `logger.debug('Message')` |
| `if (kDebugMode) print('Info message')` | `logger.info('Info message')` |
| `print('Warning: $issue')` | `logger.warning('Warning: $issue')` |
| `print('Error: $e')` | `logger.error('Error occurred', error: e, stackTrace: StackTrace.current)` |

### 3. Add Tags for Better Categorization

```dart
// Old
debugPrint('[Main] Database initialized');

// New
logger.info('Database initialized', tag: 'Main');
```

### 4. Add Proper Error Handling

```dart
// Old
try {
  // Some operation
} catch (e) {
  debugPrint('Error: $e');
}

// New
try {
  // Some operation
} catch (e, stackTrace) {
  logger.error(
    'Operation failed', 
    error: e, 
    stackTrace: stackTrace,
    tag: 'YourServiceName'
  );
}
```

### 5. Use Analytics Logging

For user events and actions:

```dart
logger.analytics('button_clicked', parameters: {'screen': 'home', 'button': 'start_session'});
```

## Example Migration

### Before:

```dart
void initializeService() {
  debugPrint('Starting service initialization');
  
  try {
    // Service initialization
    debugPrint('Service initialized successfully');
  } catch (e) {
    if (kDebugMode) {
      print('Error initializing service: $e');
      print(StackTrace.current);
    }
  }
}
```

### After:

```dart
void initializeService() {
  logger.debug('Starting service initialization', tag: 'Service');
  
  try {
    // Service initialization
    logger.info('Service initialized successfully', tag: 'Service');
  } catch (e, stackTrace) {
    logger.error(
      'Error initializing service', 
      error: e,
      stackTrace: stackTrace,
      tag: 'Service'
    );
  }
}
```

## Log Level Guidelines

1. **debug** - Detailed information, typically of interest only when diagnosing problems
2. **info** - Confirmation that things are working as expected
3. **warning** - Indication that something unexpected happened, but the app can continue
4. **error** - Serious problem that prevented some function from working

Remember that in release builds, only warning and error logs are shown by default. 