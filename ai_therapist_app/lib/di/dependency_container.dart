// lib/di/dependency_container.dart

import 'package:get_it/get_it.dart';
import 'interfaces/interfaces.dart';
import 'modules/core_module.dart';
import 'modules/services_module.dart';
import '../data/datasources/remote/api_client.dart';

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
      // The DependencyContainer now acts as a wrapper around the existing
      // service locator registrations. We don't need to re-register services
      // that are already registered in setupServiceLocator.
      
      // Just mark as initialized since services are already registered
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
  ApiClient get apiClientConcrete => get<ApiClient>(); // Concrete implementation for backward compatibility
  IDatabase get database => get<IDatabase>();
  IThemeService get theme => get<IThemeService>();
  IPreferencesService get preferences => get<IPreferencesService>();
  INavigationService get navigation => get<INavigationService>();
  IProgressService get progress => get<IProgressService>();
  IUserProfileService get userProfile => get<IUserProfileService>();
  IGroqService get groq => get<IGroqService>();
  ISessionRepository get sessionRepository => get<ISessionRepository>();
  IAuthService get authService => get<IAuthService>();
  IAuthEventHandler get authEventHandler => get<IAuthEventHandler>();
  IOnboardingService get onboarding => get<IOnboardingService>();
  ITherapyService get therapy => get<ITherapyService>();
  
  // Legacy compatibility - gradually remove these
  bool get hasLegacyServices => _isInitialized;
}

/// Extension to provide easy access to dependency container
extension DependencyContainerExtension on Object {
  DependencyContainer get dependencies => DependencyContainer();
}