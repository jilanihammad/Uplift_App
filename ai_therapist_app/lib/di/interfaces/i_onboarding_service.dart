// lib/di/interfaces/i_onboarding_service.dart

import 'package:flutter/material.dart';
import '../../services/onboarding_service.dart';

/// Interface for onboarding service operations
/// Provides contract for user onboarding flow management
abstract class IOnboardingService {
  // Current step properties
  OnboardingStep get currentStep;
  bool get hasCompleted;
  ValueNotifier<OnboardingStep> get stepChanged;

  // Initialization
  Future<void> init();

  // Step navigation
  Future<void> goToNextStep();
  Future<void> goToStep(OnboardingStep step);

  // Onboarding completion
  Future<void> completeOnboarding();

  // Reset functionality (for testing)
  Future<void> resetOnboarding();
}
