import 'dart:async';
import '../utils/logging_service.dart';

/// A singleton class that tracks the initialization status of all services
/// and provides error handling and retry logic for service initialization.
class InitializationTracker {
  // Singleton instance
  static final InitializationTracker _instance =
      InitializationTracker._internal();

  factory InitializationTracker() => _instance;

  InitializationTracker._internal();

  // Map to track initialization status of services
  final Map<String, bool> _initStatus = {};

  // Map to track initialization errors
  final Map<String, String> _initErrors = {};

  // Map to track retry counts
  final Map<String, int> _retryCount = {};

  // Map to track ongoing initialization futures to prevent concurrent attempts
  final Map<String, Completer<bool>> _initializationCompleters = {};

  // Maximum retries allowed
  final int maxRetries = 3;

  // Register a service initialization
  void markInitialized(String serviceName) {
    _initStatus[serviceName] = true;
    logger.debug('Service initialized: $serviceName');
  }

  // Record a service initialization failure
  void markInitializationFailed(String serviceName, Object error) {
    _initStatus[serviceName] = false;
    _initErrors[serviceName] = error.toString();
    logger.error('Service initialization failed: $serviceName - $error');
  }

  // Check if a service is initialized
  bool isInitialized(String serviceName) {
    return _initStatus[serviceName] ?? false;
  }

  // Get initialization error for a service
  String? getInitializationError(String serviceName) {
    return _initErrors[serviceName];
  }

  // Execute an initialization function with retry logic
  Future<bool> initializeWithRetry(
      String serviceName, Future<void> Function() initFunction) async {
    if (isInitialized(serviceName)) {
      logger.debug('$serviceName already initialized');
      return true;
    }

    // Check if initialization is already in progress
    if (_initializationCompleters.containsKey(serviceName)) {
      logger.debug('$serviceName initialization already in progress, waiting...');
      return await _initializationCompleters[serviceName]!.future;
    }

    // Start new initialization
    final completer = Completer<bool>();
    _initializationCompleters[serviceName] = completer;

    try {
      _retryCount[serviceName] = _retryCount[serviceName] ?? 0;

      if (_retryCount[serviceName]! >= maxRetries) {
        logger.error('Max retries reached for $serviceName initialization');
        completer.complete(false);
        return false;
      }

      logger.debug(
          'Initializing service: $serviceName (attempt: ${_retryCount[serviceName]! + 1})');
      
      await initFunction();
      markInitialized(serviceName);
      completer.complete(true);
      return true;
    } catch (e) {
      _retryCount[serviceName] = (_retryCount[serviceName] ?? 0) + 1;
      markInitializationFailed(serviceName, e);

      if (_retryCount[serviceName]! < maxRetries) {
        // Remove completer before retry
        _initializationCompleters.remove(serviceName);
        
        // Exponential backoff for retries
        final backoffMs = 500 * (1 << _retryCount[serviceName]!);
        logger.debug('Retrying $serviceName initialization in ${backoffMs}ms');
        await Future.delayed(Duration(milliseconds: backoffMs));
        return initializeWithRetry(serviceName, initFunction);
      }

      completer.complete(false);
      return false;
    } finally {
      _initializationCompleters.remove(serviceName);
    }
  }

  // Check if all critical services are initialized
  bool areAllCriticalServicesInitialized(List<String> criticalServices) {
    return criticalServices.every(isInitialized);
  }

  // Get a formatted report of initialization status
  String getInitializationReport() {
    final buffer = StringBuffer();
    buffer.writeln('===== Service Initialization Report =====');

    _initStatus.forEach((service, initialized) {
      final status = initialized ? 'INITIALIZED' : 'FAILED';
      final error = _initErrors[service] ?? '';
      buffer.writeln('$service: $status ${error.isNotEmpty ? '- $error' : ''}');
    });

    return buffer.toString();
  }
}

// Global instance for easy access
final initTracker = InitializationTracker();
