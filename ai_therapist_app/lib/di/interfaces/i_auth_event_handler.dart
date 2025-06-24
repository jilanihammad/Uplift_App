// lib/di/interfaces/i_auth_event_handler.dart

import '../events/auth_events.dart';

/// Interface for handling authentication events
abstract class IAuthEventHandler {
  /// Handle when a user logs in
  Future<void> handleUserLoggedIn(UserLoggedInEvent event);
  
  /// Handle when a user logs out
  Future<void> handleUserLoggedOut(UserLoggedOutEvent event);
  
  /// Handle when a user completes registration
  Future<void> handleUserRegistrationCompleted(UserRegistrationCompletedEvent event);
  
  /// Handle when a user completes the signup process
  Future<void> handleUserSignupCompleted(UserSignupCompletedEvent event);
  
  /// Handle when authentication fails
  Future<void> handleAuthenticationFailed(AuthenticationFailedEvent event);
  
  /// Handle when session verification is requested
  Future<void> handleSessionVerificationRequested(SessionVerificationRequestedEvent event);
}