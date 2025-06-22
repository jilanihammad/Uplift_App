// lib/di/dependency_container.dart

import 'package:get_it/get_it.dart';
import 'interfaces/interfaces.dart';
import 'modules/core_module.dart';
import 'modules/services_module.dart';

/// New dependency injection container to replace service locator pattern
/// This provides a clean interface for dependency injection with proper lifecycle management
class DependencyContainer {
  static final DependencyContainer _instance = DependencyContainer._internal();
  factory DependencyContainer() => _instance;
  DependencyContainer._internal();

  final GetIt _locator = GetIt.instance;
  bool _isInitialized = false;

  /// Initialize the dependency container with all required modules
  Future<void> initialize({bool testing = false}) async {
    if (_isInitialized) {
      return;
    }

    try {
      if (testing) {
        // Register mock implementations for testing
        CoreModule.registerMocks(_locator);
        ServicesModule.registerMocks(_locator);
      } else {
        // Register production implementations
        await CoreModule.register(_locator);
        await ServicesModule.register(_locator);
      }

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  /// Get a dependency by type
  T get<T extends Object>() {
    if (!_isInitialized) {
      throw StateError('DependencyContainer not initialized. Call initialize() first.');
    }
    return _locator.get<T>();
  }

  /// Check if a dependency is registered
  bool isRegistered<T extends Object>() {
    return _locator.isRegistered<T>();
  }

  /// Reset the container (useful for testing)
  Future<void> reset() async {
    await _locator.reset();
    _isInitialized = false;
  }

  /// Dispose resources
  void dispose() {
    // Future implementation for proper resource cleanup
  }

  // Convenience getters for commonly used services
  IConfigService get config => get<IConfigService>();
  IApiClient get apiClient => get<IApiClient>();
  IDatabase get database => get<IDatabase>();
  IThemeService get theme => get<IThemeService>();
  IPreferencesService get preferences => get<IPreferencesService>();
  INavigationService get navigation => get<INavigationService>();
  
  // Legacy compatibility - gradually remove these
  bool get hasLegacyServices => _isInitialized;
}

/// Extension to provide easy access to dependency container
extension DependencyContainerExtension on Object {
  DependencyContainer get dependencies => DependencyContainer();
}