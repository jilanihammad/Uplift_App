# Event-Driven Architecture for Authentication

This directory contains the event-driven pattern implementation that breaks the circular dependency between `AuthService` and `OnboardingService`.

## Overview

Instead of `AuthService` directly calling `OnboardingService` methods (and vice versa), we use an event-driven pattern where:

1. **AuthService** emits authentication events
2. **AuthCoordinator** listens to these events and coordinates the appropriate actions
3. **OnboardingService** is updated based on the events without direct coupling

## Architecture

```
AuthService -> emits events -> AuthCoordinator -> updates -> OnboardingService
```

## Key Components

### 1. Auth Events (`auth_events.dart`)

Defines all authentication-related events:
- `UserLoggedInEvent` - When a user successfully logs in
- `UserLoggedOutEvent` - When a user logs out
- `UserRegistrationCompletedEvent` - When a new user completes registration
- `UserSignupCompletedEvent` - When a user completes the signup process
- `AuthenticationFailedEvent` - When authentication fails
- `SessionVerificationRequestedEvent` - When session verification is needed

### 2. Auth Event Handler Interface (`i_auth_event_handler.dart`)

Defines the contract for handling authentication events. This interface ensures consistent event handling across the application.

### 3. Auth Coordinator (`auth_coordinator.dart`)

The central coordinator that:
- Implements `IAuthEventHandler`
- Listens to events from `AuthService`
- Updates `OnboardingService` based on authentication state
- Manages the flow between authentication and onboarding

## Usage Example

```dart
// In AuthService - emit an event when user logs in
if (_authCoordinator != null) {
  _authCoordinator!.emitEvent(UserLoggedInEvent(
    userId: user.uid,
    email: user.email,
    isNewUser: !hasCompletedSignup,
    authMethod: AuthMethod.email,
  ));
}

// AuthCoordinator handles the event
@override
Future<void> handleUserLoggedIn(UserLoggedInEvent event) async {
  if (event.isNewUser) {
    // New user needs onboarding
    await _onboardingService.resetOnboarding();
  } else {
    // Returning user - mark onboarding as complete
    await _onboardingService.completeOnboarding();
  }
}
```

## Benefits

1. **No Circular Dependencies**: Services don't directly reference each other
2. **Loose Coupling**: Changes to one service don't require changes to the other
3. **Extensibility**: Easy to add new events and handlers
4. **Testability**: Each component can be tested in isolation
5. **Clear Flow**: Authentication flow is explicit and traceable

## Adding New Events

To add a new authentication event:

1. Define the event class in `auth_events.dart`:
```dart
class NewAuthEvent extends AuthEvent {
  final String someData;
  NewAuthEvent({required this.someData});
}
```

2. Add the handler method to `IAuthEventHandler`:
```dart
Future<void> handleNewAuthEvent(NewAuthEvent event);
```

3. Implement the handler in `AuthCoordinator`:
```dart
@override
Future<void> handleNewAuthEvent(NewAuthEvent event) async {
  // Handle the event
}
```

4. Emit the event from the appropriate service:
```dart
_authCoordinator?.emitEvent(NewAuthEvent(someData: 'value'));
```

## Testing

The event-driven pattern makes testing easier:

```dart
// Test AuthService in isolation
test('login emits correct event', () async {
  final mockCoordinator = MockAuthCoordinator();
  authService.setAuthCoordinator(mockCoordinator);
  
  await authService.login('user@example.com', 'password');
  
  verify(mockCoordinator.emitEvent(any)).called(1);
});

// Test AuthCoordinator logic
test('new user triggers onboarding reset', () async {
  final mockOnboarding = MockOnboardingService();
  final coordinator = AuthCoordinator();
  
  await coordinator.handleUserLoggedIn(UserLoggedInEvent(
    userId: '123',
    isNewUser: true,
    authMethod: AuthMethod.email,
  ));
  
  verify(mockOnboarding.resetOnboarding()).called(1);
});
```

## Migration Notes

When migrating from the old circular dependency pattern:

1. Remove direct references between AuthService and OnboardingService
2. Register AuthCoordinator in the dependency container
3. Connect AuthCoordinator to AuthService after initialization
4. Update any direct method calls to emit events instead

## Future Enhancements

- Add event persistence for offline scenarios
- Implement event replay for debugging
- Add event metrics and monitoring
- Support for event filtering and prioritization