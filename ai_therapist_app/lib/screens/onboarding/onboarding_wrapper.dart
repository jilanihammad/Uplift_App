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
import '../../services/memory_manager.dart';
import '../../services/audio_generator.dart';
class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({super.key});
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
    _stepNotifier.addListener(_onStepChanged);
    Future.microtask(() async {
      if (DependencyContainer().isRegistered<MemoryManager>()) {
        final memoryManager = DependencyContainer().get<MemoryManager>();
        await memoryManager.initializeOnlyIfNeeded();
      }
      if (DependencyContainer().isRegistered<AudioGenerator>()) {
        final audioGenerator = DependencyContainer().get<AudioGenerator>();
        await audioGenerator.initializeOnlyIfNeeded();
      }
    });
  }
  @override
  void dispose() {
    _stepNotifier.removeListener(_onStepChanged);
    super.dispose();
  }
  void _onStepChanged() {
    if (_stepNotifier.value == OnboardingStep.complete) {
      _authService.completeSignup();
      if (mounted) {
        context.go(AppRouter.home);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OnboardingStep>(
      valueListenable: _onboardingService.stepChanged,
      builder: (context, step, child) {
        return Scaffold(
          body: SafeArea(
            child: _getScreen(),
          ),
        );
      },
    );
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
        _onboardingService.goToNextStep();
        return Container(); // This screen is effectively skipped
      case OnboardingStep.complete:
        return Container(); // This should not be visible
      default:
        return Container(); // Fallback
    }
  }
}
