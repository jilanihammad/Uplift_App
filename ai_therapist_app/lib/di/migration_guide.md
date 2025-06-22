# Service Locator to Dependency Injection Migration Guide

## Overview
This guide explains how to gradually migrate from the service locator anti-pattern to proper dependency injection in the AI Therapist app.

## Migration Strategy

### Phase 1: Foundation Setup ✅
- [x] Create dependency injection interfaces
- [x] Create dependency modules with adapters
- [x] Set up new dependency container

### Phase 2: Simple Services (Week 1)
Target services with minimal dependencies:

#### 2.1 ThemeService
**Current Issue:**
```dart
final PreferencesService _preferencesService = serviceLocator<PreferencesService>();
```

**Solution:**
```dart
// Constructor injection
ThemeServiceDI({required PreferencesService preferencesService})

// Registration in module
locator.registerLazySingleton<ThemeServiceDI>(
  () => ThemeServiceDI(preferencesService: locator<PreferencesService>()),
);
```

#### 2.2 PreferencesService
**Migration:** Direct replacement since it has no dependencies on other services.

### Phase 3: Medium Complexity Services (Week 2-3)
Target services with 2-3 dependencies:

#### 3.1 ProgressService
**Current Dependencies:**
- NotificationService

#### 3.2 UserProfileService  
**Current Dependencies:**
- Minimal external dependencies

### Phase 4: Complex Services (Week 4-5)
Target services with circular dependencies:

#### 4.1 AuthService ↔ OnboardingService
**Current Problem:**
- AuthService needs OnboardingService
- OnboardingService needs AuthService
- Both use serviceLocator to break circular dependency

**Solution Pattern:**
```dart
// Use event-driven communication
class AuthService {
  final AuthEventBus _eventBus;
  AuthService({required AuthEventBus eventBus}) : _eventBus = eventBus;
  
  void signOut() {
    // ... auth logic
    _eventBus.emit(UserSignedOutEvent());
  }
}

class OnboardingService {
  final AuthEventBus _eventBus;
  OnboardingService({required AuthEventBus eventBus}) : _eventBus = eventBus {
    _eventBus.on<UserSignedOutEvent>(_handleSignOut);
  }
}
```

#### 4.2 VoiceService
**Current Issues:**
- 1,419 lines - needs to be split first
- Multiple responsibilities
- Complex initialization

**Solution:**
1. First refactor into smaller services (as per refactor.md)
2. Then apply dependency injection

### Phase 5: UI Components (Week 6)
Replace service locator usage in widgets:

#### Current Pattern:
```dart
class SomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authService = serviceLocator<AuthService>();
    // ...
  }
}
```

#### Target Pattern:
```dart
class SomeWidget extends StatelessWidget {
  final AuthService authService;
  
  const SomeWidget({required this.authService});
  
  // Or use Provider/BLoC for dependency injection
}
```

## Implementation Guidelines

### 1. Breaking Circular Dependencies

#### Option A: Event-Driven Architecture
```dart
// Create event bus for loose coupling
class ServiceEventBus {
  final StreamController<ServiceEvent> _controller = StreamController.broadcast();
  
  void emit(ServiceEvent event) => _controller.add(event);
  Stream<T> on<T extends ServiceEvent>() => _controller.stream.where((e) => e is T).cast<T>();
}
```

#### Option B: Interface Segregation
```dart
// Split interfaces to break dependencies
abstract class IUserAuthenticator {
  Future<User?> signIn(String email, String password);
}

abstract class IOnboardingStateManager {
  Future<void> completeOnboarding(String userId);
}

// AuthService implements IUserAuthenticator
// OnboardingService implements IOnboardingStateManager
```

#### Option C: Dependency Inversion
```dart
// Higher-level service orchestrates lower-level services
class UserSessionManager {
  final IUserAuthenticator _auth;
  final IOnboardingStateManager _onboarding;
  
  UserSessionManager({
    required IUserAuthenticator auth,
    required IOnboardingStateManager onboarding,
  }) : _auth = auth, _onboarding = onboarding;
}
```

### 2. Service Registration Patterns

#### Singleton Services
```dart
// For stateful services that should have one instance
locator.registerLazySingleton<ConfigService>(() => ConfigService());
```

#### Factory Services
```dart
// For stateless services or services that need fresh instances
locator.registerFactory<ApiClient>(() => ApiClient(config: locator<ConfigService>()));
```

#### Instance Registration
```dart
// For pre-initialized instances
final config = await ConfigService.initialize();
locator.registerSingleton<ConfigService>(config);
```

### 3. Testing Support

#### Mock Registration
```dart
// In test setup
void setUpMocks() {
  GetIt.instance.reset();
  GetIt.instance.registerSingleton<IAuthService>(MockAuthService());
  GetIt.instance.registerSingleton<IApiClient>(MockApiClient());
}
```

#### Dependency Override
```dart
// For specific test scenarios
class TestDependencyContainer extends DependencyContainer {
  void overrideForTest<T extends Object>(T instance) {
    _locator.unregister<T>();
    _locator.registerSingleton<T>(instance);
  }
}
```

## Migration Checklist

### For Each Service:
- [ ] Identify all dependencies (serviceLocator<T> usage)
- [ ] Create constructor that accepts dependencies
- [ ] Update service registration in appropriate module
- [ ] Create interface if the service is used by others
- [ ] Update tests to use dependency injection
- [ ] Update calling code to use new pattern

### For UI Components:
- [ ] Identify serviceLocator usage in widgets
- [ ] Choose injection method (Constructor, Provider, BLoC)
- [ ] Update widget tree to provide dependencies
- [ ] Update tests to mock dependencies

## Performance Considerations

### Memory Impact
- Dependency injection can reduce memory usage by avoiding global singletons
- Proper lifecycle management prevents memory leaks
- Factory registration allows garbage collection of unused instances

### Startup Performance
- Lazy registration delays service creation until needed
- Avoid heavy initialization in constructors
- Use async initialization methods for I/O operations

### Runtime Performance
- Dependency resolution is typically faster than service locator
- Compile-time dependency validation catches errors early
- Better tree-shaking in release builds

## Validation

### After Each Phase:
1. **Functionality Test:** All features work as before
2. **Performance Test:** No degradation in app startup or runtime
3. **Memory Test:** No increase in memory usage
4. **Test Coverage:** All tests pass with new dependency structure

### Final Validation:
1. **Remove service_locator.dart:** Ensure no imports remain
2. **Build Test:** App builds successfully
3. **Integration Test:** All user flows work correctly
4. **Code Review:** Clean separation of concerns achieved

## Rollback Plan

If issues arise during migration:

1. **Immediate Rollback:** Keep old service locator code commented out
2. **Partial Rollback:** Revert specific services while keeping others migrated
3. **Full Rollback:** Restore service locator pattern if critical issues found

## Benefits After Migration

### Code Quality
- Clear dependency declarations
- Better testability
- Reduced coupling
- Easier to understand code flow

### Development Experience
- Compile-time dependency validation
- Better IDE support
- Easier refactoring
- Clearer service boundaries

### Maintenance
- Easier to add new features
- Simplified testing
- Better error handling
- Improved debugging experience