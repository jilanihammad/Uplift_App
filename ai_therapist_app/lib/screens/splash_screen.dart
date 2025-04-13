// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:get_it/get_it.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = GetIt.instance<AuthService>();
  final OnboardingService _onboardingService = GetIt.instance<OnboardingService>();
  
  @override
  void initState() {
    super.initState();
    // Initialize services and navigate to the appropriate screen
    _initializeAndNavigate();
  }
  
  Future<void> _initializeAndNavigate() async {
    // Wait for a minimum time to show the splash screen
    await Future.delayed(const Duration(seconds: 2));
    
    // Ensure services are in sync
    await _authService.syncWithOnboardingService();
    
    // Check if user is logged in
    final bool isLoggedIn = await _authService.isLoggedIn;
    final bool hasCompletedSignup = await _authService.hasCompletedSignup;
    
    print("SplashScreen: User isLoggedIn=$isLoggedIn, hasCompletedSignup=$hasCompletedSignup");
    
    if (!mounted) return;
    
    if (!isLoggedIn) {
      // Navigate to login if not logged in
      print("SplashScreen: Navigating to login screen");
      context.go('/login');
    } else {
      // Check if signup is completed
      if (hasCompletedSignup) {
        // Navigate to home if signup is completed
        print("SplashScreen: Navigating to home screen");
        context.go('/home');
      } else {
        // Navigate to onboarding if signup is not completed
        print("SplashScreen: Navigating to onboarding");
        context.go('/onboarding');
      }
    }
  }

  // Reset user signup status for testing
  Future<void> _resetSignupStatus() async {
    // Logout first to ensure we're starting from a clean state
    await _authService.logout();
    
    // Clean up all auth-related preferences
    await SharedPreferences.getInstance().then((prefs) {
      prefs.remove(AuthService.HAS_COMPLETED_SIGNUP_KEY);
      prefs.remove(AuthService.AUTH_TOKEN_KEY);
      prefs.remove(AuthService.EMAIL_KEY);
      prefs.remove(AuthService.PHONE_KEY);
    });
    
    // Reset onboarding step
    await _onboardingService.resetOnboarding();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Auth state reset - logged out and will show onboarding next login')),
    );
    
    // Refresh the screen by navigating back to splash
    if (mounted) {
      context.go('/');
    }
  }
  
  // Mark signup as complete for testing
  Future<void> _completeSignup() async {
    await _authService.completeSignup();
    await _onboardingService.completeOnboarding();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signup marked as complete - will skip onboarding')),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo 
              Image.asset(
                'assets/images/uplift_logo.png',
                height: 200,
                width: 200,
              ),
              const SizedBox(height: 24),
              const Text(
                'Uplift',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your Personal Therapy Companion',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              
              // Debug buttons - only shown in debug mode
              if (kDebugMode) ...[
                const SizedBox(height: 40),
                const Text(
                  'Debug Options',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _resetSignupStatus,
                      child: const Text('Reset Signup'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _completeSignup,
                      child: const Text('Complete Signup'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}