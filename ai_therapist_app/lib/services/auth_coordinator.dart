// lib/services/auth_coordinator.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/di/interfaces/i_auth_event_handler.dart';
import 'package:ai_therapist_app/di/interfaces/i_onboarding_service.dart';
import 'package:ai_therapist_app/di/events/auth_events.dart';

/// Coordinates authentication and onboarding flow using events
/// This service breaks the circular dependency between AuthService and OnboardingService
class AuthCoordinator implements IAuthEventHandler {
  final IOnboardingService _onboardingService;
  bool _initialized = false;

  /// Constructor with dependency injection
  AuthCoordinator({required IOnboardingService onboardingService})
      : _onboardingService = onboardingService;

  // Event stream controller for broadcasting auth events
  final _eventController = StreamController<AuthEvent>.broadcast();

  /// Stream of authentication events
  Stream<AuthEvent> get authEvents => _eventController.stream;

  /// Initialize the coordinator
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Initialize the onboarding service
      await _onboardingService.init();
      _initialized = true;

      if (kDebugMode) {
        debugPrint('AuthCoordinator: Initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AuthCoordinator: Error during initialization: $e');
      }
      rethrow;
    }
  }

  /// Emit an authentication event
  void emitEvent(AuthEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);

      if (kDebugMode) {
        debugPrint('AuthCoordinator: Emitted ${event.runtimeType} event');
      }

      // Handle the event internally
      _handleEvent(event);
    }
  }

  /// Internal event handler that routes events to appropriate handlers
  Future<void> _handleEvent(AuthEvent event) async {
    if (!_initialized) {
      if (kDebugMode) {
        debugPrint('AuthCoordinator: Not initialized, skipping event handling');
      }
      return;
    }

    try {
      if (event is UserLoggedInEvent) {
        await handleUserLoggedIn(event);
      } else if (event is UserLoggedOutEvent) {
        await handleUserLoggedOut(event);
      } else if (event is UserRegistrationCompletedEvent) {
        await handleUserRegistrationCompleted(event);
      } else if (event is UserSignupCompletedEvent) {
        await handleUserSignupCompleted(event);
      } else if (event is AuthenticationFailedEvent) {
        await handleAuthenticationFailed(event);
      } else if (event is SessionVerificationRequestedEvent) {
        await handleSessionVerificationRequested(event);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AuthCoordinator: Error handling event ${event.runtimeType}: $e');
      }
    }
  }

  @override
  Future<void> handleUserLoggedIn(UserLoggedInEvent event) async {
    if (kDebugMode) {
      debugPrint(
          'AuthCoordinator: Handling user login - isNewUser: ${event.isNewUser}, method: ${event.authMethod}');
    }

    if (event.isNewUser) {
      // New user needs onboarding
      await _onboardingService.resetOnboarding();
      if (kDebugMode) {
        debugPrint('AuthCoordinator: Reset onboarding for new user');
      }
    } else {
      // Returning user - mark onboarding as complete
      await _onboardingService.completeOnboarding();
      if (kDebugMode) {
        debugPrint(
            'AuthCoordinator: Marked onboarding as complete for returning user');
      }
    }
  }

  @override
  Future<void> handleUserLoggedOut(UserLoggedOutEvent event) async {
    if (kDebugMode) {
      debugPrint('AuthCoordinator: Handling user logout');
    }
    // No specific onboarding action needed for logout
  }

  @override
  Future<void> handleUserRegistrationCompleted(
      UserRegistrationCompletedEvent event) async {
    if (kDebugMode) {
      debugPrint('AuthCoordinator: Handling user registration completed');
    }

    // New registration always needs onboarding
    await _onboardingService.resetOnboarding();
  }

  @override
  Future<void> handleUserSignupCompleted(UserSignupCompletedEvent event) async {
    if (kDebugMode) {
      debugPrint('AuthCoordinator: Handling user signup completed');
    }

    // When signup is completed, mark onboarding as complete
    await _onboardingService.completeOnboarding();
  }

  @override
  Future<void> handleAuthenticationFailed(
      AuthenticationFailedEvent event) async {
    if (kDebugMode) {
      debugPrint(
          'AuthCoordinator: Handling authentication failed - method: ${event.authMethod}, reason: ${event.reason}');
    }
    // No specific onboarding action needed for failed auth
  }

  @override
  Future<void> handleSessionVerificationRequested(
      SessionVerificationRequestedEvent event) async {
    if (kDebugMode) {
      debugPrint('AuthCoordinator: Handling session verification requested');
    }
    // No specific onboarding action needed for session verification
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
}
