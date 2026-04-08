import 'dart:async';
import '../utils/logging_service.dart';
class InitializationTracker {
  static final InitializationTracker _instance =
      InitializationTracker._internal();
  factory InitializationTracker() => _instance;
  InitializationTracker._internal();
  final Map<String, bool> _initStatus = {};
  final Map<String, String> _initErrors = {};
  final Map<String, int> _retryCount = {};
  final Map<String, Completer<bool>> _initializationCompleters = {};
  final int maxRetries = 3;
  void markInitialized(String serviceName) {
    _initStatus[serviceName] = true;
    logger.debug('Service initialized: $serviceName');
  }
  void markInitializationFailed(String serviceName, Object error) {
    _initStatus[serviceName] = false;
    _initErrors[serviceName] = error.toString();
    logger.error('Service initialization failed: $serviceName - $error');
  }
  bool isInitialized(String serviceName) {
    return _initStatus[serviceName] ?? false;
  }
  String? getInitializationError(String serviceName) {
    return _initErrors[serviceName];
  }
  Future<bool> initializeWithRetry(
      String serviceName, Future<void> Function() initFunction) async {
    if (isInitialized(serviceName)) {
      logger.debug('$serviceName already initialized');
      return true;
    }
    if (_initializationCompleters.containsKey(serviceName)) {
      logger
          .debug('$serviceName initialization already in progress, waiting...');
      return await _initializationCompleters[serviceName]!.future;
    }
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
        _initializationCompleters.remove(serviceName);
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
  bool areAllCriticalServicesInitialized(List<String> criticalServices) {
    return criticalServices.every(isInitialized);
  }
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
final initTracker = InitializationTracker();
