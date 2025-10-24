// lib/di/events/auth_events.dart

/// Base class for all authentication-related events
abstract class AuthEvent {
  final DateTime timestamp;

  AuthEvent() : timestamp = DateTime.now();
}

/// Event emitted when a user successfully logs in
class UserLoggedInEvent extends AuthEvent {
  final String userId;
  final String? email;
  final String? phoneNumber;
  final bool isNewUser;
  final AuthMethod authMethod;

  UserLoggedInEvent({
    required this.userId,
    this.email,
    this.phoneNumber,
    required this.isNewUser,
    required this.authMethod,
  });
}

/// Event emitted when a user logs out
class UserLoggedOutEvent extends AuthEvent {
  final String userId;

  UserLoggedOutEvent({required this.userId});
}

/// Event emitted when a user completes registration
class UserRegistrationCompletedEvent extends AuthEvent {
  final String userId;
  final String? email;
  final String? name;

  UserRegistrationCompletedEvent({
    required this.userId,
    this.email,
    this.name,
  });
}

/// Event emitted when a user completes the signup process
class UserSignupCompletedEvent extends AuthEvent {
  final String userId;

  UserSignupCompletedEvent({required this.userId});
}

/// Event emitted when authentication fails
class AuthenticationFailedEvent extends AuthEvent {
  final String reason;
  final AuthMethod authMethod;

  AuthenticationFailedEvent({
    required this.reason,
    required this.authMethod,
  });
}

/// Event emitted when a session needs verification
class SessionVerificationRequestedEvent extends AuthEvent {
  final String userId;

  SessionVerificationRequestedEvent({required this.userId});
}

/// Enum representing different authentication methods
enum AuthMethod {
  email,
  phone,
  google,
}
