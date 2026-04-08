// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/i_auth_service.dart';
import '../di/interfaces/i_onboarding_service.dart';
import 'custom_icons.dart'; // Import the custom icons
import 'package:go_router/go_router.dart'; // Import GoRouter
import '../config/routes.dart'; // Import route constants
import '../services/config_service.dart';
import '../data/datasources/remote/api_client.dart';
import '../utils/feature_flags.dart';
import 'package:firebase_auth/firebase_auth.dart';
class SplashScreen extends StatefulWidget {
  final bool skipFirebaseCheck;
  final IAuthService? authService;
  final IOnboardingService? onboardingService;
  final ApiClient? apiClient;
  const SplashScreen({
    super.key,
    this.skipFirebaseCheck = false,
    this.authService,
    this.onboardingService,
    this.apiClient,
  });
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late IAuthService _authService;
  late IOnboardingService _onboardingService;
  late BackendService _backendService;
  final bool _serviceInitialized = false;
  bool _backendAvailable = false;
  String _statusMessage = "Initializing...";
  double _loadingProgress = 0.0;
  bool _isAnimating = true;
  late AnimationController _animController;
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _initializeAndNavigate();
  }
  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }
  Future<void> _initializeAndNavigate() async {
    _startSplashTimeout(); // Ensure timeouts always run
    try {
      setState(() {
        _statusMessage = "Setting up services...";
        _loadingProgress = 0.1;
      });
      try {
        await setupServiceLocator(
          useRefactoredVoicePipeline: FeatureFlags.useNewVoicePipeline,
        );
      } catch (e) {}
      if (DependencyContainer().isRegistered<ConfigService>()) {
        final configService = DependencyContainer().configService;
        await configService.init();
      } else {
      }
      if (DependencyContainer().isRegistered<ApiClient>()) {
      } else {
      }
      _authService = widget.authService ?? DependencyContainer().authService;
      _onboardingService =
          widget.onboardingService ?? DependencyContainer().onboarding;
      await _onboardingService.init();
      final prefs = await SharedPreferences.getInstance();
      final bool isFirstLaunch =
          !(prefs.getBool('app_launched_before') ?? false);
      if (isFirstLaunch) {
        try {
          await FirebaseAuth.instance.signOut();
          await _authService.logout();
          await prefs.setBool('app_launched_before', true);
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            context.go(AppRouter.login);
          }
          return; // Exit early to avoid further processing
        } catch (e) {}
      }
      setState(() {
        _statusMessage = "Checking authentication...";
        _loadingProgress = 0.2;
      });
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = firebaseUser != null;
      setState(() {
        _statusMessage = "Checking backend connection...";
        _loadingProgress = 0.3;
      });
      bool backendAvailable = false;
      try {
        backendAvailable = await _backendService
            .isBackendAvailable()
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        backendAvailable = false;
      }
      _backendAvailable = backendAvailable;
      final authData = await compute(_getAuthData, _authService);
      final bool hasCompletedSignup = authData['hasCompletedSignup'] as bool;
      setState(() {
        _isAnimating = false;
        _loadingProgress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      _navigateBasedOnAuth(isLoggedIn, hasCompletedSignup);
    } catch (e, stack) {
      if (mounted) {
        context.go(AppRouter.login); // Fallback to login
      }
    }
  }
  void _navigateBasedOnAuth(bool isLoggedIn, bool hasCompletedSignup) {
    bool canProceedToHome = isLoggedIn && hasCompletedSignup;
    bool needsOnboarding = isLoggedIn && !hasCompletedSignup;
    bool forceLoginFlow = false;
    if (!_backendAvailable && isLoggedIn) {
    }
    if (!canProceedToHome && !needsOnboarding || forceLoginFlow) {
      if (mounted) {
        context.go(AppRouter.login);
      }
    } else if (needsOnboarding) {
      if (mounted) {
        context.go(AppRouter.onboarding);
      }
    } else {
      if (mounted) {
        context.go(AppRouter.home);
      }
    }
  }
  static Future<Map<String, bool>> _getAuthData(IAuthService service) async {
    final isLoggedIn = await service.isLoggedIn;
    final hasCompletedSignup = await service.hasCompletedSignup;
    return {
      'isLoggedIn': isLoggedIn,
      'hasCompletedSignup': hasCompletedSignup,
    };
  }
  static Future<bool> _checkBackend(BackendService service) async {
    try {
      return await service.isBackendAvailable();
    } catch (e) {
      if (e.toString().contains('NotInitializedError')) {
      } else {
      }
      return false;
    }
  }
  static Future<void> _syncServices(IAuthService service) async {
    await service.syncWithOnboardingService();
  }
  void _startSplashTimeout() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _loadingProgress = 0.2;
      }
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted &&
          (_statusMessage.contains("Checking connection") ||
              _statusMessage.contains("connection..."))) {
        _backendAvailable = false;
        _loadingProgress = 0.8;
        _forceNavigateBasedOnFirebaseUser();
      }
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _statusMessage != "Done") {
        _loadingProgress = 0.9;
        _forceNavigateBasedOnFirebaseUser();
      }
    });
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        _isAnimating = false;
        _loadingProgress = 1.0;
        if (mounted) {
          context.go(AppRouter.login);
        }
      }
    });
  }
  void _forceNavigateBasedOnFirebaseUser() {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = firebaseUser != null;
      if (!isLoggedIn) {
        if (mounted) context.go(AppRouter.login);
      } else {
        if (mounted) context.go(AppRouter.home);
      }
    } catch (e) {
      if (mounted) {
        context.go(AppRouter.login);
      }
    }
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
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + 0.05 * _animController.value.abs(),
                    child: _buildLogoWidget(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Uplift',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Personal Therapy Companion',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                kDebugMode ? _statusMessage : "Preparing your experience...",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Theme.of(context).colorScheme.onPrimary.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildLogoWidget() {
    try {
      return UpliftIcons.logoWithFallback(
        imagePath: 'assets/images/uplift_logo.png',
        size: 200,
        color: Theme.of(context).primaryColor,
      );
    } catch (e) {
      return UpliftIcons.therapyLogo(
        size: 200,
        color: Theme.of(context).primaryColor,
      );
    }
  }
}
