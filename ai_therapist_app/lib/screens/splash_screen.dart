// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get_it/get_it.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../services/backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import 'custom_icons.dart'; // Import the custom icons
import 'package:go_router/go_router.dart'; // Import GoRouter
import '../config/routes.dart'; // Import route constants
import '../services/config_service.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/memory_manager.dart';
import '../services/audio_generator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  final bool skipFirebaseCheck;

  const SplashScreen({Key? key, this.skipFirebaseCheck = false})
      : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Don't directly access services during State creation
  late AuthService _authService;
  late OnboardingService _onboardingService;
  late BackendService _backendService;
  bool _serviceInitialized = false;
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

    // Initialize app properly
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
      // First initialize the service locator if not already done
      setState(() {
        _statusMessage = "Setting up services...";
        _loadingProgress = 0.1;
      });

      // Ensure service locator is initialized
      if (!serviceLocator.isRegistered<AuthService>()) {
        await setupServiceLocator();
      }

      // Ensure ConfigService is initialized before using BackendService
      if (serviceLocator.isRegistered<ConfigService>()) {
        final configService = serviceLocator<ConfigService>();
        await configService.init();
        if (kDebugMode) {
          print("SplashScreen: ConfigService initialized successfully");
        }
      } else {
        if (kDebugMode) {
          print("SplashScreen: Warning - ConfigService not registered");
        }
      }

      // Ensure ApiClient is ready
      if (serviceLocator.isRegistered<ApiClient>()) {
        if (kDebugMode) {
          print("SplashScreen: ApiClient is registered");
        }
      } else {
        if (kDebugMode) {
          print("SplashScreen: Warning - ApiClient not registered");
        }
      }

      // Now safely get services from the locator
      _authService = serviceLocator<AuthService>();

      if (serviceLocator.isRegistered<OnboardingService>()) {
        _onboardingService = serviceLocator<OnboardingService>();
        await _onboardingService.init();
      }

      // Add a check for first app launch to force fresh login experience
      final prefs = await SharedPreferences.getInstance();
      final bool isFirstLaunch =
          !(prefs.getBool('app_launched_before') ?? false);

      if (isFirstLaunch) {
        print(
            "SplashScreen: First app launch detected, clearing any cached auth sessions");

        // Clear any potentially cached Firebase auth session
        try {
          // Sign out from Firebase Auth
          await FirebaseAuth.instance.signOut();

          // Clear any stored auth tokens in local storage
          await _authService.logout();

          // Record that app has been launched
          await prefs.setBool('app_launched_before', true);

          print(
              "SplashScreen: Successfully cleared auth state for first launch");

          // After a short delay to show splash screen, navigate to login
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            context.go(AppRouter.login);
          }
          return; // Exit early to avoid further processing
        } catch (e) {
          print("SplashScreen: Error clearing auth state: $e");
          // Continue processing
        }
      }

      // Verify Firebase auth is working properly
      setState(() {
        _statusMessage = "Checking authentication...";
        _loadingProgress = 0.2;
      });

      // Check Firebase user status
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = firebaseUser != null;

      // Backend check with timeout
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
        print("SplashScreen: Backend check failed or timed out: $e");
        backendAvailable = false;
      }
      _backendAvailable = backendAvailable;

      // Continue with auth checks and navigation
      final authData = await compute(_getAuthData, _authService);
      final bool hasCompletedSignup = authData['hasCompletedSignup'] as bool;

      setState(() {
        _isAnimating = false;
        _loadingProgress = 1.0;
      });

      if (kDebugMode) {
        print(
            "SplashScreen: User isLoggedIn=$isLoggedIn, hasCompletedSignup=$hasCompletedSignup, backendAvailable=$_backendAvailable");
      }

      // Ensure minimum showing time for splash screen (shorter duration)
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // Navigate to appropriate screen - if backend is unavailable but user is logged in, still go to home
      _navigateBasedOnAuth(isLoggedIn, hasCompletedSignup);
    } catch (e, stack) {
      print("SplashScreen: Initialization error: $e\n$stack");
      if (mounted) {
        context.go(AppRouter.login); // Fallback to login
      }
    }
  }

  // Helper method to navigate based on auth status
  void _navigateBasedOnAuth(bool isLoggedIn, bool hasCompletedSignup) {
    bool canProceedToHome = isLoggedIn && hasCompletedSignup;
    bool needsOnboarding = isLoggedIn && !hasCompletedSignup;

    // Check backend connection and determine if we need a recovery path
    bool forceLoginFlow = false;
    if (!_backendAvailable && isLoggedIn) {
      // If backend is unavailable but we have a valid Firebase user,
      // we can still proceed without backend (in offline mode)
      if (kDebugMode) {
        print(
            "SplashScreen: Backend unavailable but Firebase user valid, proceeding to appropriate screen");
      }
    }

    // Log the navigation decision making for debugging
    if (kDebugMode) {
      print(
          "SplashScreen: Navigation decision - canProceedToHome=$canProceedToHome, needsOnboarding=$needsOnboarding");
      print(
          "SplashScreen: Auth state details - isLoggedIn=$isLoggedIn, hasCompletedSignup=$hasCompletedSignup, backendAvailable=$_backendAvailable");
    }

    // Final navigation decision
    if (!canProceedToHome && !needsOnboarding || forceLoginFlow) {
      if (kDebugMode) {
        print(
            "SplashScreen: Navigating to login screen (isLoggedIn=$isLoggedIn)");
      }
      if (mounted) {
        context.go(AppRouter.login);
      }
    } else if (needsOnboarding) {
      if (kDebugMode) {
        print("SplashScreen: Navigating to onboarding");
      }
      if (mounted) {
        context.go(AppRouter.onboarding);
      }
    } else {
      if (kDebugMode) {
        print("SplashScreen: Navigating to home screen");
      }
      if (mounted) {
        context.go(AppRouter.home);
      }
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
    });

    // Skip backend check if requested
    if (widget.skipFirebaseCheck) {
      if (kDebugMode) {
        print("SplashScreen: Skipping backend check as requested");
      }

      setState(() {
        _backendAvailable = false;
        _statusMessage = "Offline mode activated";
        _loadingProgress = 0.6;
      });
      return;
    }

    // Defensive check for required services before attempting backend check
    if (!serviceLocator.isRegistered<ConfigService>() ||
        !serviceLocator.isRegistered<ApiClient>()) {
      if (kDebugMode) {
        print(
            "SplashScreen: Cannot check backend - required services not registered");
      }

      setState(() {
        _backendAvailable = false;
        _statusMessage = "Configuration incomplete. Using offline mode.";
        _loadingProgress = 0.6;
      });
      return;
    }

    // Initialize BackendService explicitly before checking availability
    try {
      await _backendService.init();
      if (kDebugMode) {
        print("SplashScreen: BackendService initialized successfully");
      }
    } catch (e) {
      if (kDebugMode) {
        print("SplashScreen: Error initializing BackendService: $e");
      }

      setState(() {
        _backendAvailable = false;
        _statusMessage =
            "Backend service initialization failed. Using offline mode.";
        _loadingProgress = 0.6;
      });
      return;
    }

    // Max number of retries
    int maxRetries = 2;
    int retryCount = 0;
    bool connectionSuccess = false;

    while (retryCount < maxRetries && !connectionSuccess) {
      try {
        // More verbose logging for connection attempt
        if (kDebugMode) {
          print(
              "SplashScreen: Checking backend connection via BackendService... (Attempt ${retryCount + 1})");
        }

        connectionSuccess = await compute(_checkBackend, _backendService);

        if (!mounted) return;

        if (connectionSuccess) {
          setState(() {
            _backendAvailable = true;
            _statusMessage = "Connected to backend!";
            _loadingProgress = 0.6;
          });
          if (kDebugMode) {
            print("SplashScreen: Backend connection successful");
          }
          break; // Exit the retry loop on success
        } else {
          retryCount++;
          if (retryCount < maxRetries) {
            if (kDebugMode) {
              print("SplashScreen: Backend connection failed, retrying...");
            }
            // Wait briefly before retrying
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      } catch (e) {
        retryCount++;
        if (kDebugMode) {
          print("SplashScreen: Backend connection error: $e");
          if (retryCount < maxRetries) {
            print("SplashScreen: Retrying connection...");
          }
        }

        // Wait briefly before retrying
        if (retryCount < maxRetries) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    // If all retries failed, proceed with offline mode
    if (!connectionSuccess && mounted) {
      setState(() {
        _backendAvailable = false;
        _statusMessage = "Cannot connect to backend. Using offline mode.";
        _loadingProgress = 0.6;
      });

      if (kDebugMode) {
        print(
            "SplashScreen: Backend connection failed after $retryCount attempts");
        print("SplashScreen: Will proceed with app flow in offline mode");
      }

      // Show alert dialog but allow user to continue without waiting for response
      if (mounted) {
        Future.delayed(Duration.zero, () {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => AlertDialog(
              title: const Text('Backend Connection Issue'),
              content: const Text(
                'Could not connect to the therapy backend server. '
                'This may cause limited functionality.\n\n'
                'Please check your internet connection and try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue Anyway'),
                ),
              ],
            ),
          ).then((_) {
            // Dialog was dismissed or button pressed
            if (kDebugMode) {
              print("SplashScreen: User acknowledged backend issue dialog");
            }
          });
        });
      }
    }
  }

  // Isolate function to check backend
  static Future<bool> _checkBackend(BackendService service) async {
    try {
      return await service.isBackendAvailable();
    } catch (e) {
      // More specific error handling
      if (e.toString().contains('NotInitializedError')) {
        print(
            "SplashScreen: Backend check failed due to NotInitializedError - a required service dependency was not ready");
      } else {
        print("SplashScreen: Backend check failed with error: $e");
      }
      return false;
    }
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
        const SnackBar(
            content: Text(
                'Auth state reset - logged out and will show onboarding next login')),
      );

      // Refresh the screen by navigating back to splash
      if (mounted) {
        context.go(AppRouter.splash);
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
        const SnackBar(
            content: Text('Signup marked as complete - will skip onboarding')),
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

  // Multiple timeouts for each stage
  void _startSplashTimeout() {
    // FIRST TIMEOUT: Extremely short timeout to avoid black screen
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        print("SplashScreen: Quick sanity check at 1s, continuing startup");
        _loadingProgress = 0.2;
      }
    });

    // SECOND TIMEOUT: Force navigation after 3 seconds if still on "Checking connection"
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted &&
          (_statusMessage.contains("Checking connection") ||
              _statusMessage.contains("connection..."))) {
        print(
            "SplashScreen: Connectivity check timeout reached (3s), forcing navigation");
        // Force backend to be considered unavailable to prevent waiting for it
        _backendAvailable = false;
        _loadingProgress = 0.8;

        // Only check Firebase Auth status, not backend connectivity
        _forceNavigateBasedOnFirebaseUser();
      }
    });

    // THIRD TIMEOUT: For any other initialization issues
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _statusMessage != "Done") {
        print("SplashScreen: General timeout reached (5s), forcing navigation");
        _loadingProgress = 0.9;
        _forceNavigateBasedOnFirebaseUser();
      }
    });

    // FINAL TIMEOUT: Maximum failsafe - no matter what
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        print(
            "SplashScreen: Maximum time reached (8s), forcing navigation to login screen");
        _isAnimating = false;
        _loadingProgress = 1.0;

        // Just go to login screen, most reliable option
        if (mounted) {
          print("SplashScreen: EMERGENCY navigation to login screen");
          context.go(AppRouter.login);
        }
      }
    });
  }

  // Helper method to force navigation based on current Firebase user state
  void _forceNavigateBasedOnFirebaseUser() {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = firebaseUser != null;
      print("SplashScreen: Force navigation with isLoggedIn=$isLoggedIn");
      if (!isLoggedIn) {
        if (mounted) context.go(AppRouter.login);
      } else {
        if (mounted) context.go(AppRouter.home);
      }
    } catch (e) {
      print("SplashScreen: Error during force navigation: $e");
      // If all else fails, go to login
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
              // Logo with animated rotation for engagement
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
                kDebugMode ? _statusMessage : "Preparing your experience...",
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
            ],
          ),
        ),
      ),
    );
  }

  // Build logo widget with fallback
  Widget _buildLogoWidget() {
    try {
      // Try to load the image asset with our custom fallback
      return UpliftIcons.logoWithFallback(
        imagePath: 'assets/images/uplift_logo.png',
        size: 200,
        color: Theme.of(context).primaryColor,
      );
    } catch (e) {
      // Additional fallback in case of exception
      return UpliftIcons.therapyLogo(
        size: 200,
        color: Theme.of(context).primaryColor,
      );
    }
  }
}
