// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:get_it/get_it.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = GetIt.instance<AuthService>();
  // Don't initialize OnboardingService here, as it might not be registered yet
  late OnboardingService _onboardingService;
  late final BackendService _backendService;
  bool _backendAvailable = false;
  String _statusMessage = "Initializing...";
  double _loadingProgress = 0.0;
  bool _isAnimating = true;
  
  // Animation controller for smoother loading experience
  late AnimationController _animController;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize the animation controller
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    // Initialize the backend service from service locator
    _backendService = serviceLocator<BackendService>();
    
    // Initialize services and navigate to the appropriate screen
    _initializeAndNavigate();
  }
  
  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeAndNavigate() async {
    // Start all tasks without immediately awaiting them
    final backendCheckFuture = _checkBackendAvailability();
    final authStatusFuture = _checkAuthStatus();
    
    // Schedule UI updates less frequently to reduce frame drops
    _updateLoadingProgressLess();
    
    // Perform backend check and auth status check in parallel using compute
    await Future.wait([backendCheckFuture, authStatusFuture]);
    
    // Check results and navigate using compute to avoid blocking main thread
    final authData = await compute(_getAuthData, _authService);
    final bool isLoggedIn = authData['isLoggedIn'] as bool;
    final bool hasCompletedSignup = authData['hasCompletedSignup'] as bool;
    
    setState(() {
      _isAnimating = false;
      _loadingProgress = 1.0;
    });
    
    if (kDebugMode) {
      print("SplashScreen: User isLoggedIn=$isLoggedIn, hasCompletedSignup=$hasCompletedSignup, backendAvailable=$_backendAvailable");
    }
    
    // Ensure minimum showing time for splash screen (shorter duration)
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (!mounted) return;
    
    // Navigate to appropriate screen
    _navigateBasedOnAuth(isLoggedIn, hasCompletedSignup);
  }
  
  // Helper method to navigate based on auth status
  void _navigateBasedOnAuth(bool isLoggedIn, bool hasCompletedSignup) {
    if (!isLoggedIn) {
      if (kDebugMode) {
        print("SplashScreen: Navigating to login screen");
      }
      context.go('/login');
    } else if (!hasCompletedSignup) {
      if (kDebugMode) {
        print("SplashScreen: Navigating to onboarding");
      }
      context.go('/onboarding');
    } else {
      if (kDebugMode) {
        print("SplashScreen: Navigating to home screen");
      }
      context.go('/home');
    }
  }
  
  // Get auth data in an isolate to avoid blocking main thread
  static Future<Map<String, bool>> _getAuthData(AuthService service) async {
    final isLoggedIn = await service.isLoggedIn;
    final hasCompletedSignup = await service.hasCompletedSignup;
    return {
      'isLoggedIn': isLoggedIn,
      'hasCompletedSignup': hasCompletedSignup,
    };
  }
  
  // Separate function to check backend availability
  Future<void> _checkBackendAvailability() async {
    setState(() {
      _statusMessage = "Checking connection...";
      _loadingProgress = 0.3;
    });
    
    try {
      _backendAvailable = await compute(_checkBackend, _backendService);
      
      if (!mounted) return;
      
      setState(() {
        _statusMessage = _backendAvailable 
          ? "Connected to backend!" 
          : "Cannot connect to backend. Using offline mode.";
        _loadingProgress = 0.6;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _backendAvailable = false;
        _statusMessage = "Connection error. Using offline mode.";
        _loadingProgress = 0.6;
      });
    }
  }
  
  // Isolate function to check backend
  static Future<bool> _checkBackend(BackendService service) async {
    return await service.isBackendAvailable();
  }
  
  // Separate function to check auth status
  Future<void> _checkAuthStatus() async {
    try {
      // Ensure services are in sync
      await compute(_syncServices, _authService);
      setState(() {
        _loadingProgress = 0.8;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error checking auth status: $e");
      }
    }
  }
  
  // Isolate function to sync services
  static Future<void> _syncServices(AuthService service) async {
    await service.syncWithOnboardingService();
  }
  
  // Create a less intensive loading animation that updates the UI less frequently
  void _updateLoadingProgressLess() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isAnimating || !mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        // Increment in larger steps to reduce UI updates
        if (_loadingProgress < 0.9) {
          _loadingProgress += 0.1;
        }
      });
      
      // Run for shorter time
      if (_loadingProgress >= 0.9 || timer.tick > 8) {
        timer.cancel();
      }
    });
  }

  // Reset user signup status for testing
  Future<void> _resetSignupStatus() async {
    try {
      // Safely get the OnboardingService when needed
      _onboardingService = serviceLocator<OnboardingService>();
      
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
    } catch (e) {
      if (kDebugMode) {
        print('Error resetting signup status: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting signup status: $e')),
      );
    }
  }
  
  // Mark signup as complete for testing
  Future<void> _completeSignup() async {
    try {
      // Safely get the OnboardingService when needed
      _onboardingService = serviceLocator<OnboardingService>();
      
      await _authService.completeSignup();
      await _onboardingService.completeOnboarding();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signup marked as complete - will skip onboarding')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error completing signup: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error completing signup: $e')),
      );
    }
  }

  // Check backend connectivity
  Future<void> _checkBackendConnectivity() async {
    setState(() {
      _statusMessage = "Checking connection...";
    });
    
    final isAvailable = await _backendService.isBackendAvailable();
    setState(() {
      _backendAvailable = isAvailable;
      _statusMessage = isAvailable 
          ? "Backend connection successful" 
          : "Cannot connect to backend";
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_statusMessage),
        backgroundColor: _backendAvailable ? Colors.green : Colors.red,
      ),
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
              // Logo with animated rotation for engagement
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + 0.05 * _animController.value.abs(),
                    child: Image.asset(
                      'assets/images/uplift_logo.png',
                      height: 200,
                      width: 200,
                    ),
                  );
                },
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
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              // Linear progress indicator for better visual feedback
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
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
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _checkBackendConnectivity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                  ),
                  child: const Text('Check Backend'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}