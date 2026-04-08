// lib/di/events/auth_events.dart
abstract class AuthEvent {
  final DateTime timestamp;
  AuthEvent() : timestamp = DateTime.now();
}
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
class UserLoggedOutEvent extends AuthEvent {
  final String userId;
  UserLoggedOutEvent({required this.userId});
}
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
class UserSignupCompletedEvent extends AuthEvent {
  final String userId;
  UserSignupCompletedEvent({required this.userId});
}
class AuthenticationFailedEvent extends AuthEvent {
  final String reason;
  final AuthMethod authMethod;
  AuthenticationFailedEvent({
    required this.reason,
    required this.authMethod,
  });
}
class SessionVerificationRequestedEvent extends AuthEvent {
  final String userId;
  SessionVerificationRequestedEvent({required this.userId});
}
enum AuthMethod {
  email,
  phone,
  google,
}
