// lib/di/interfaces/i_auth_event_handler.dart
import '../events/auth_events.dart';
abstract class IAuthEventHandler {
  Future<void> handleUserLoggedIn(UserLoggedInEvent event);
  Future<void> handleUserLoggedOut(UserLoggedOutEvent event);
  Future<void> handleUserRegistrationCompleted(
      UserRegistrationCompletedEvent event);
  Future<void> handleUserSignupCompleted(UserSignupCompletedEvent event);
  Future<void> handleAuthenticationFailed(AuthenticationFailedEvent event);
  Future<void> handleSessionVerificationRequested(
      SessionVerificationRequestedEvent event);
}
