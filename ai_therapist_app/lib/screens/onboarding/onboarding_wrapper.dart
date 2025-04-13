import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../services/onboarding_service.dart';
import '../../services/auth_service.dart';
import 'welcome_screen.dart';
import 'profile_name_screen.dart';
import 'profile_reason_screen.dart';
import 'profile_goals_screen.dart';
import 'profile_experience_screen.dart';
import 'preferred_style_screen.dart';
import 'mood_setup_screen.dart';
import 'coping_strategies_screen.dart';
import 'cbt_intro_screen.dart';

class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({Key? key}) : super(key: key);

  @override
  State<OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<OnboardingWrapper> {
  final _onboardingService = GetIt.instance<OnboardingService>();
  final _authService = GetIt.instance<AuthService>();
  late ValueNotifier<OnboardingStep> _stepNotifier;
  
  @override
  void initState() {
    super.initState();
    _stepNotifier = _onboardingService.stepChanged;
    
    // Listen for step changes to detect completion
    _stepNotifier.addListener(_onStepChanged);
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
        context.go('/home');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OnboardingStep>(
      valueListenable: _onboardingService.stepChanged,
      builder: (context, step, child) {
        print('OnboardingWrapper: ValueListenableBuilder triggered with step: $step');
        
        return Scaffold(
          body: SafeArea(
            child: _getScreenForStep(step),
          ),
        );
      },
    );
  }
  
  Widget _getScreenForStep(OnboardingStep step) {
    print('OnboardingWrapper: Getting screen for step: $step');
    
    switch (step) {
      case OnboardingStep.welcome:
        print('OnboardingWrapper: Returning WelcomeScreen');
        return WelcomeScreen();
      case OnboardingStep.profileName:
        print('OnboardingWrapper: Returning ProfileNameScreen');
        return ProfileNameScreen();
      case OnboardingStep.profileReason:
        print('OnboardingWrapper: Returning ProfileReasonScreen');
        return ProfileReasonScreen();
      case OnboardingStep.profileGoals:
        print('OnboardingWrapper: Returning ProfileGoalsScreen');
        return ProfileGoalsScreen();
      case OnboardingStep.profileExperience:
        print('OnboardingWrapper: Returning ProfileExperienceScreen');
        return ProfileExperienceScreen();
      case OnboardingStep.preferredStyle:
        print('OnboardingWrapper: Returning PreferredStyleScreen');
        return PreferredStyleScreen();
      case OnboardingStep.moodSetup:
        // Skip the mood setup screen for now as it's not implemented
        print('OnboardingWrapper: Skipping MoodSetupScreen, going to CopingStrategiesScreen');
        _onboardingService.goToStep(OnboardingStep.copingStrategies);
        return Container(); // Temp placeholder while transitioning
      case OnboardingStep.copingStrategies:
        print('OnboardingWrapper: Returning CopingStrategiesScreen');
        return CopingStrategiesScreen();
      case OnboardingStep.cbtIntro:
        print('OnboardingWrapper: Returning CbtIntroScreen');
        return CbtIntroScreen();
      case OnboardingStep.complete:
        // This should navigate away, but have a fallback
        print('OnboardingWrapper: Detected complete step, navigating to home');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/home');
        });
        return Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
    }
  }
} 