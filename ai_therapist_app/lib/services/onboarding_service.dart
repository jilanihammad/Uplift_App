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

  // Current step in memory
  OnboardingStep _currentStep = OnboardingStep.welcome;

  // Get current step
  @override
  OnboardingStep get currentStep => _currentStep;

  // Value notifier to track step changes
  final _stepChangedController =
      ValueNotifier<OnboardingStep>(OnboardingStep.welcome);

  // Observable step changes
  @override
  ValueNotifier<OnboardingStep> get stepChanged => _stepChangedController;

  // Has completed onboarding
  bool _hasCompleted = false;
  @override
  bool get hasCompleted => _hasCompleted;

  // This is the last step in the onboarding process before completion
  static const _lastImplementedStep = OnboardingStep.moodSetup;

  // Constructor
  OnboardingService();

  // Initialize the service
  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    print('Initializing OnboardingService...');

    // Get locally stored completion status
    _hasCompleted = prefs.getBool(_completedKey) ?? false;

    print('OnboardingService init - hasCompleted: $_hasCompleted');

    if (_hasCompleted) {
      print('Onboarding already completed, setting step to complete');
      _currentStep = OnboardingStep.complete;
    } else {
      // Load current step if not completed
      final stepIndex = prefs.getInt(_currentStepKey) ?? 0;
      print('Loaded step index from SharedPreferences: $stepIndex');

      _currentStep = OnboardingStep.values[stepIndex];
      print('Set current step to: ${_currentStep.toString()}');

      // If current step is beyond implemented screens, reset to last implemented step
      if (_currentStep.index > _lastImplementedStep.index &&
          _currentStep != OnboardingStep.complete) {
        print(
            'Current step beyond last implemented step, resetting to: ${_lastImplementedStep.toString()}');
        _currentStep = _lastImplementedStep;
        await _saveStep(_currentStep);
      }
    }

    _stepChangedController.value = _currentStep;
    print(
        'OnboardingService initialization complete, current step: ${_currentStep.toString()}');
  }

  // Move to next step
  @override
  Future<void> goToNextStep() async {
    if (_currentStep == OnboardingStep.complete) return;

    final nextStepIndex = _currentStep.index + 1;

    print(
        'Attempting to go from step: ${_currentStep.toString()} (index: ${_currentStep.index})');
    print('To next step with index: $nextStepIndex');

    if (nextStepIndex < OnboardingStep.values.length) {
      final nextStep = OnboardingStep.values[nextStepIndex];

      // Debug prints
      print(
          'Moving from step: ${_currentStep.toString()} (index: ${_currentStep.index})');
      print('To next step: ${nextStep.toString()} (index: ${nextStep.index})');

      // Simply save the next step, no need to skip any steps
      await _saveStep(nextStep);
    }
  }

  // Move to a specific step
  @override
  Future<void> goToStep(OnboardingStep step) async {
    print('Requested to go to step: ${step.toString()} (index: ${step.index})');

    // Prevent going to unimplemented steps
    if (step.index > _lastImplementedStep.index &&
        step != OnboardingStep.complete) {
      print(
          'Warning: Requested step beyond last implemented step. Requested: ${step.toString()}, Last implemented: ${_lastImplementedStep.toString()}');
      // If trying to go to an unimplemented step, go to the last implemented one
      await _saveStep(_lastImplementedStep);
      return;
    }

    await _saveStep(step);
  }

  // Save the current step
  Future<void> _saveStep(OnboardingStep step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentStepKey, step.index);

    print(
        'Saved step to SharedPreferences: ${step.toString()} (index: ${step.index})');

    _currentStep = step;
    _stepChangedController.value = _currentStep;

    // Debug print to verify the step was updated in memory
    print('Current step in memory updated to: ${_currentStep.toString()}');

    // If we reached complete, update completed status
    if (step == OnboardingStep.complete) {
      await completeOnboarding();
    }
  }

  // Mark onboarding as completed
  @override
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);

    _hasCompleted = true;
    _currentStep = OnboardingStep.complete;
    _stepChangedController.value = _currentStep;
  }

  // Reset onboarding (for testing)
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
