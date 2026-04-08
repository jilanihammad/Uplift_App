// lib/services/auth_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/di/interfaces/i_auth_event_handler.dart';
import 'package:ai_therapist_app/di/interfaces/i_onboarding_service.dart';
import 'package:ai_therapist_app/di/events/auth_events.dart';
class AuthCoordinator implements IAuthEventHandler {
  final IOnboardingService _onboardingService;
  bool _initialized = false;
  AuthCoordinator({required IOnboardingService onboardingService})
      : _onboardingService = onboardingService;
  final _eventController = StreamController<AuthEvent>.broadcast();
  Stream<AuthEvent> get authEvents => _eventController.stream;
  Future<void> init() async {
    if (_initialized) return;
    try {
      await _onboardingService.init();
      _initialized = true;
    } catch (e) {
      rethrow;
    }
  }
  void emitEvent(AuthEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
      _handleEvent(event);
    }
  }
  Future<void> _handleEvent(AuthEvent event) async {
    if (!_initialized) {
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
    } catch (e) {}
  }
  @override
  Future<void> handleUserLoggedIn(UserLoggedInEvent event) async {
    if (event.isNewUser) {
      await _onboardingService.resetOnboarding();
    } else {
      await _onboardingService.completeOnboarding();
    }
  }
  @override
  Future<void> handleUserLoggedOut(UserLoggedOutEvent event) async {
  }
  @override
  Future<void> handleUserRegistrationCompleted(
      UserRegistrationCompletedEvent event) async {
    await _onboardingService.resetOnboarding();
  }
  @override
  Future<void> handleUserSignupCompleted(UserSignupCompletedEvent event) async {
    await _onboardingService.completeOnboarding();
  }
  @override
  Future<void> handleAuthenticationFailed(
      AuthenticationFailedEvent event) async {
  }
  @override
  Future<void> handleSessionVerificationRequested(
      SessionVerificationRequestedEvent event) async {
  }
  void dispose() {
    _eventController.close();
  }
}
