// lib/di/interfaces/i_onboarding_service.dart
import 'package:flutter/material.dart';
import '../../services/onboarding_service.dart';
abstract class IOnboardingService {
  OnboardingStep get currentStep;
  bool get hasCompleted;
  ValueNotifier<OnboardingStep> get stepChanged;
  Future<void> init();
  Future<void> goToNextStep();
  Future<void> goToStep(OnboardingStep step);
  Future<void> completeOnboarding();
  Future<void> resetOnboarding();
}
