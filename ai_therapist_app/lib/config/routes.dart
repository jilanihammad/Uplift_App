// lib/config/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

// Import screen files with the correct paths
import 'package:ai_therapist_app/screens/splash_screen.dart';
import 'package:ai_therapist_app/screens/login_screen.dart';
import 'package:ai_therapist_app/screens/register_screen.dart';
import 'package:ai_therapist_app/screens/phone_login_screen.dart';
import 'package:ai_therapist_app/screens/home_screen.dart';
import 'package:ai_therapist_app/screens/chat_screen.dart';
import 'package:ai_therapist_app/screens/profile_screen.dart';
import 'package:ai_therapist_app/screens/history_screen.dart';
import 'package:ai_therapist_app/screens/resources_screen.dart';
import 'package:ai_therapist_app/screens/settings_screen.dart';
import 'package:ai_therapist_app/screens/session_summary_screen.dart';
import 'package:ai_therapist_app/screens/therapist_style_screen.dart';
import 'package:ai_therapist_app/screens/progress_screen.dart';
import 'package:ai_therapist_app/screens/onboarding/onboarding_wrapper.dart';
import 'package:ai_therapist_app/screens/session_details_screen.dart';
import 'package:ai_therapist_app/screens/diagnostic_screen.dart';

// Services for navigation guards
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/navigation_service.dart';

/// The router configuration for the app
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  // Route names as constants for easy reference
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String phoneLogin = '/phone_login';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String profile = '/profile';
  static const String history = '/history';
  static const String resources = '/resources';
  static const String settings = '/settings';
  static const String sessionSummary = '/session_summary';
  static const String therapistStyle = '/therapist_style';
  static const String progress = '/progress';
  static const String onboarding = '/onboarding';
  static const String diagnostic = '/diagnostic';

  // Create and configure the router
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: home,
    debugLogDiagnostics: true,
    redirect: (BuildContext context, GoRouterState state) async {
      print(
          "ROUTER DEBUG: Redirect called with location: ${state.matchedLocation}");

      // Access services needed for routing decisions
      try {
        final authService = serviceLocator<AuthService>();

        // Check for anonymous Firebase auth
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final isAnonymous = firebaseUser?.isAnonymous ?? false;

        // Check if user is logged in and onboarding status - note async/await
        final bool isLoggedIn = await authService.isLoggedIn;
        final bool hasCompletedSignup = await authService.hasCompletedSignup;

        print(
            "ROUTER DEBUG: Redirect check - isLoggedIn: $isLoggedIn, hasCompletedSignup: $hasCompletedSignup, isAnonymous: $isAnonymous, path: ${state.matchedLocation}");

        final bool isGoingToAuth = state.matchedLocation == login ||
            state.matchedLocation == register ||
            state.matchedLocation == phoneLogin;
        final bool isGoingToOnboarding = state.matchedLocation == onboarding;
        final bool isGoingToSplash = state.matchedLocation == splash;

        // If at splash, always redirect to home (unless onboarding/auth needed)
        if (isGoingToSplash) {
          if (!isLoggedIn) return login;
          if (isLoggedIn && !hasCompletedSignup) return onboarding;
          return home;
        }

        // Handle anonymous auth - treat as not logged in
        if (isAnonymous && !isGoingToAuth) {
          print(
              "ROUTER DEBUG: User is using anonymous auth, redirecting to login");
          return login;
        }

        // If not logged in and not going to auth screens, redirect to login
        if (!isLoggedIn && !isGoingToAuth && !isGoingToOnboarding) {
          print("ROUTER DEBUG: User not logged in, redirecting to login");
          return login;
        }

        // If logged in but hasn't completed signup process, redirect to onboarding
        // ONLY if not already going to onboarding
        if (isLoggedIn && !hasCompletedSignup && !isGoingToOnboarding) {
          print(
              "ROUTER DEBUG: User is logged in but hasn't completed signup, redirecting to onboarding");
          return onboarding;
        }

        // If logged in and has completed signup but trying to go to onboarding, redirect to home
        if (isLoggedIn && hasCompletedSignup && isGoingToOnboarding) {
          print(
              "ROUTER DEBUG: User already completed signup, redirecting from onboarding to home");
          return home;
        }

        // If logged in and going to auth screens, redirect to home or onboarding
        if (isLoggedIn && isGoingToAuth) {
          final redirectTo = hasCompletedSignup ? home : onboarding;
          print(
              "ROUTER DEBUG: User is logged in and going to auth screen, redirecting to $redirectTo");
          return redirectTo;
        }

        // Log the final routing decision
        print(
            "ROUTER DEBUG: No redirection needed for path: ${state.matchedLocation}");
      } catch (e) {
        print("ROUTER DEBUG ERROR: Exception during redirection: $e");
        // On error, allow navigation to continue without redirection
      }

      // No redirection needed
      return null;
    },
    routes: [
      // Splash screen route
      GoRoute(
        path: splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Onboarding route
      GoRoute(
        path: onboarding,
        builder: (context, state) => const OnboardingWrapper(),
      ),

      // Authentication routes
      GoRoute(
        path: login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: phoneLogin,
        builder: (context, state) => const PhoneLoginScreen(),
      ),

      // Session summary route
      GoRoute(
        path: sessionSummary,
        builder: (context, state) {
          // For safety, use type check and provide defaults
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SessionSummaryScreen(
            sessionId: extra['sessionId'] as String? ?? 'unknown',
            summary: extra['summary'] as String? ?? '',
            actionItems: extra['actionItems'] as List<String>? ?? [],
            messages: extra['messages'],
            initialMood: extra['initialMood'],
          );
        },
      ),

      // Session details route (from history)
      GoRoute(
        path: '/sessions/:sessionId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId'] ?? '';
          return SessionDetailsScreen(sessionId: sessionId);
        },
      ),

      // Diagnostic screen route
      GoRoute(
        path: diagnostic,
        builder: (context, state) => const DiagnosticScreen(),
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ScaffoldWithNavBar(child: child);
        },
        routes: [
          // Home/Dashboard route
          GoRoute(
            path: home,
            builder: (context, state) => const HomeScreen(),
          ),

          // Chat/Therapy session route
          GoRoute(
            path: chat,
            builder: (context, state) => const ChatScreen(),
            routes: [
              // Dynamic chat session route with ID parameter
              GoRoute(
                path: ':sessionId',
                builder: (context, state) {
                  final sessionId = state.pathParameters['sessionId']!;
                  return ChatScreen(sessionId: sessionId);
                },
              ),
            ],
          ),

          // User profile route
          GoRoute(
            path: profile,
            builder: (context, state) => const ProfileScreen(),
          ),

          // History/Past sessions route
          GoRoute(
            path: history,
            builder: (context, state) => const HistoryScreen(),
          ),

          // Resources/Help route
          GoRoute(
            path: resources,
            builder: (context, state) => const ResourcesScreen(),
          ),

          // Settings route
          GoRoute(
            path: settings,
            builder: (context, state) => const SettingsScreen(),
            routes: [
              // Therapist style selection sub-route
              GoRoute(
                path: 'therapist_style',
                builder: (context, state) => const TherapistStyleScreen(),
              ),
            ],
          ),

          // Progress tracking route
          GoRoute(
            path: progress,
            builder: (context, state) => const ProgressScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
  );
}

// Bottom navigation scaffold
class ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;

  const ScaffoldWithNavBar({Key? key, required this.child}) : super(key: key);

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  late final NavigationService _navigationService;
  bool _isBottomNavVisible = true;
  StreamSubscription? _navBarVisibilitySubscription;

  @override
  void initState() {
    super.initState();
    _navigationService = serviceLocator<NavigationService>();
    _isBottomNavVisible = _navigationService.isBottomNavVisible;

    // Listen for changes to bottom nav visibility
    _navBarVisibilitySubscription =
        _navigationService.bottomNavVisibilityStream.listen((isVisible) {
      if (mounted) {
        setState(() {
          _isBottomNavVisible = isVisible;
        });
      }
    });
  }

  @override
  void dispose() {
    _navBarVisibilitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: _isBottomNavVisible
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _calculateSelectedIndex(context),
              onTap: (index) => _onItemTapped(index, context),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.history), label: 'History'),
              ],
            )
          : null,
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRouter.home)) return 0;
    if (location.startsWith(AppRouter.chat)) return 1;
    if (location.startsWith(AppRouter.history)) return 2;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        GoRouter.of(context).go(AppRouter.home);
        break;
      case 1:
        GoRouter.of(context).go(AppRouter.chat);
        break;
      case 2:
        GoRouter.of(context).go(AppRouter.history);
        break;
    }
  }
}

// Error screen for handling navigation errors
class ErrorScreen extends StatelessWidget {
  final Exception? error;

  const ErrorScreen({Key? key, this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation Error'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Oops! Something went wrong.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => GoRouter.of(context).go(AppRouter.home),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
