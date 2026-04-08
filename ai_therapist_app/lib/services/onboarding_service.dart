import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/interfaces/i_onboarding_service.dart';
enum OnboardingStep {
  welcome,
  profileName,
  profileGoals,
  profileExperience,
  moodSetup,
  complete
}
class OnboardingService implements IOnboardingService {
  static const String _currentStepKey = 'onboarding_step';
  static const String _completedKey = 'onboarding_completed';
  OnboardingStep _currentStep = OnboardingStep.welcome;
  @override
  OnboardingStep get currentStep => _currentStep;
  final _stepChangedController =
      ValueNotifier<OnboardingStep>(OnboardingStep.welcome);
  @override
  ValueNotifier<OnboardingStep> get stepChanged => _stepChangedController;
  bool _hasCompleted = false;
  @override
  bool get hasCompleted => _hasCompleted;
  static const _lastImplementedStep = OnboardingStep.moodSetup;
  OnboardingService();
  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _hasCompleted = prefs.getBool(_completedKey) ?? false;
    if (_hasCompleted) {
      _currentStep = OnboardingStep.complete;
    } else {
      final stepIndex = prefs.getInt(_currentStepKey) ?? 0;
      _currentStep = OnboardingStep.values[stepIndex];
      if (_currentStep.index > _lastImplementedStep.index &&
          _currentStep != OnboardingStep.complete) {
        _currentStep = _lastImplementedStep;
        await _saveStep(_currentStep);
      }
    }
    _stepChangedController.value = _currentStep;
  }
  @override
  Future<void> goToNextStep() async {
    if (_currentStep == OnboardingStep.complete) return;
    final nextStepIndex = _currentStep.index + 1;
    if (nextStepIndex < OnboardingStep.values.length) {
      final nextStep = OnboardingStep.values[nextStepIndex];
      await _saveStep(nextStep);
    }
  }
  @override
  Future<void> goToStep(OnboardingStep step) async {
    if (step.index > _lastImplementedStep.index &&
        step != OnboardingStep.complete) {
      await _saveStep(_lastImplementedStep);
      return;
    }
    await _saveStep(step);
  }
  Future<void> _saveStep(OnboardingStep step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentStepKey, step.index);
    _currentStep = step;
    _stepChangedController.value = _currentStep;
    if (step == OnboardingStep.complete) {
      await completeOnboarding();
    }
  }
  @override
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    _hasCompleted = true;
    _currentStep = OnboardingStep.complete;
    _stepChangedController.value = _currentStep;
  }
  @override
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentStepKey);
    await prefs.remove(_completedKey);
    _hasCompleted = false;
    _currentStep = OnboardingStep.welcome;
    _stepChangedController.value = _currentStep;
  }
}
