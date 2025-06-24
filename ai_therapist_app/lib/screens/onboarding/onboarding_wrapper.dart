import 'package:flutter/material.dart';
import '../../di/dependency_container.dart';
import 'package:go_router/go_router.dart';
import '../../services/onboarding_service.dart';
import '../../services/auth_service.dart';
import '../../config/routes.dart';
import 'welcome_screen.dart';
import 'profile_name_screen.dart';
import 'profile_goals_screen.dart';
import 'profile_experience_screen.dart';
import 'preferred_style_screen.dart';
import 'mood_setup_screen.dart';
import 'coping_strategies_screen.dart';
import 'cbt_intro_screen.dart';
import '../../services/memory_manager.dart';
import '../../services/audio_generator.dart';

class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({Key? key}) : super(key: key);

  @override
  State<OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<OnboardingWrapper> {
  final _onboardingService = DependencyContainer().get<OnboardingService>();
  final _authService = DependencyContainer().get<AuthService>();
  late ValueNotifier<OnboardingStep> _stepNotifier;

  @override
  void initState() {
    super.initState();
    _stepNotifier = _onboardingService.stepChanged;

    // Listen for step changes to detect completion
    _stepNotifier.addListener(_onStepChanged);

    // Defer heavy initializations to after navigation
    Future.microtask(() async {
      if (DependencyContainer().isRegistered<MemoryManager>()) {
        final memoryManager = DependencyContainer().get<MemoryManager>();
        await memoryManager.initializeOnlyIfNeeded();
      }
      if (DependencyContainer().isRegistered<AudioGenerator>()) {
        final audioGenerator = DependencyContainer().get<AudioGenerator>();
        await audioGenerator.initializeOnlyIfNeeded();
      }
      // Add any other heavy service initializations here
    });
  }

  @override
  void dispose() {
    _stepNotifier.removeListener(_onStepChanged);
    super.dispose();
  }

  void _onStepChanged() {
    if (_stepNotifier.value == OnboardingStep.complete) {
      // Mark the user as having completed signup when onboarding is done
      print('OnboardingWrapper: Marking user as having completed signup');
      _authService.completeSignup();

      // Navigate to home screen
      if (mounted) {
        print('OnboardingWrapper: Detected complete step, navigating to home');
        context.go(AppRouter.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OnboardingStep>(
      valueListenable: _onboardingService.stepChanged,
      builder: (context, step, child) {
        print(
            'OnboardingWrapper: ValueListenableBuilder triggered with step: $step');

        return Scaffold(
          body: SafeArea(
            child: _getScreen(),
          ),
        );
      },
    );
  }

  void _goToNextStep() {
    _onboardingService.goToNextStep();
  }

  void _goToPreviousStep() {
    // Implement previous step navigation
    final currentIndex = _onboardingService.currentStep.index;
    if (currentIndex > 0) {
      final previousStep = OnboardingStep.values[currentIndex - 1];
      _onboardingService.goToStep(previousStep);
    }
  }

  Widget _getScreen() {
    switch (_onboardingService.currentStep) {
      case OnboardingStep.welcome:
        return const WelcomeScreen();
      case OnboardingStep.profileName:
        return const ProfileNameScreen();
      case OnboardingStep.profileGoals:
        return const ProfileGoalsScreen();
      case OnboardingStep.profileExperience:
        return const ProfileExperienceScreen();
      case OnboardingStep.moodSetup:
        print('Skipping mood setup for now...');
        _onboardingService.goToNextStep();
        return Container(); // This screen is effectively skipped
      case OnboardingStep.complete:
        return Container(); // This should not be visible
      default:
        return Container(); // Fallback
    }
  }
}
