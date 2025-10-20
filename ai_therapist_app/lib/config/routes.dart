// lib/config/routes.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:flutter/services.dart';

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
import 'package:ai_therapist_app/screens/progress_screen.dart';
import 'package:ai_therapist_app/screens/onboarding/onboarding_wrapper.dart';
import 'package:ai_therapist_app/screens/session_details_screen.dart';
import 'package:ai_therapist_app/screens/diagnostic_screen.dart';

// Services for navigation guards
import 'package:ai_therapist_app/di/dependency_container.dart';
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
  static const String progress = '/progress';
  static const String onboarding = '/onboarding';
  static const String diagnostic = '/diagnostic';
  static const String tasks = '/tasks'; // Added tasks route

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
        final authService = DependencyContainer().authService;

        // Check if user is logged in and onboarding status - note async/await
        final bool isLoggedIn = await authService.isLoggedIn;
        final bool hasCompletedSignup = await authService.hasCompletedSignup;

        print(
            "ROUTER DEBUG: Redirect check - isLoggedIn: $isLoggedIn, hasCompletedSignup: $hasCompletedSignup, path: ${state.matchedLocation}");

        final bool isGoingToAuth = state.matchedLocation == login ||
            state.matchedLocation == register ||
            state.matchedLocation == phoneLogin;
        final bool isGoingToOnboarding = state.matchedLocation == onboarding;
        final bool isGoingToSplash = state.matchedLocation == splash;

        // If at splash, always redirect to home (unless onboarding/auth needed)
        if (isGoingToSplash) {
          if (!isLoggedIn) {
            if (state.matchedLocation == login) return null;
            return login;
          }
          if (isLoggedIn && !hasCompletedSignup) {
            if (state.matchedLocation == onboarding) return null;
            return onboarding;
          }
          if (state.matchedLocation == home) return null;
          return home;
        }

        // If not logged in and not going to auth screens, redirect to login
        if (!isLoggedIn && !isGoingToAuth && !isGoingToOnboarding) {
          print("ROUTER DEBUG: User not logged in, redirecting to login");
          if (state.matchedLocation == login) return null;
          return login;
        }

        // If logged in but hasn't completed signup process, redirect to onboarding
        // ONLY if not already going to onboarding
        if (isLoggedIn && !hasCompletedSignup && !isGoingToOnboarding) {
          print(
              "ROUTER DEBUG: User is logged in but hasn't completed signup, redirecting to onboarding");
          if (state.matchedLocation == onboarding) return null;
          return onboarding;
        }

        // If logged in and has completed signup but trying to go to onboarding, redirect to home
        if (isLoggedIn && hasCompletedSignup && isGoingToOnboarding) {
          print(
              "ROUTER DEBUG: User already completed signup, redirecting from onboarding to home");
          if (state.matchedLocation == home) return null;
          return home;
        }

        // If logged in and going to auth screens, redirect to home or onboarding
        if (isLoggedIn && isGoingToAuth) {
          final redirectTo = hasCompletedSignup ? home : onboarding;
          print(
              "ROUTER DEBUG: User is logged in and going to auth screen, redirecting to $redirectTo");
          if (state.matchedLocation == redirectTo) return null;
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

          // Safely cast actionItems from List<dynamic> to List<String>
          final actionItemsDynamic =
              extra['actionItems'] as List<dynamic>? ?? [];
          final actionItems =
              actionItemsDynamic.map((item) => item.toString()).toList();

          return SessionSummaryScreen(
            sessionId: extra['sessionId'] as String? ?? 'unknown',
            summary: extra['summary'] as String? ?? '',
            actionItems: actionItems,
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
            ],
          ),

          // Progress tracking route
          GoRoute(
            path: progress,
            builder: (context, state) => const ProgressScreen(),
          ),

          // New Tasks route (aliased to progress)
          GoRoute(
            path: tasks,
            builder: (context, state) => const ProgressScreen(initialTabIndex: 2), // Pass index 2 for Tasks tab
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
    _navigationService = DependencyContainer().navigation as NavigationService;
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
    return WillPopScope(
      onWillPop: () async {
        final int currentIndex = _calculateSelectedIndex(context);
        if (currentIndex == 0) {
          // On Home tab, show exit dialog
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Exit App'),
              content: const Text('Are you sure you want to exit the app?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Exit'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          );
          if (shouldExit == true) {
            SystemNavigator.pop();
            return true;
          }
          return false;
        } else {
          // Not on Home tab, switch to Home
          _onItemTapped(0, context);
          return false;
        }
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: _isBottomNavVisible
            ? BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _calculateSelectedIndex(context),
                onTap: (index) => _onItemTapped(index, context),
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.home), label: 'Home'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.task), label: 'Tasks'), // New Tasks button
                  BottomNavigationBarItem(
                      icon: Icon(Icons.history), label: 'History'),
                ],
              )
            : null,
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRouter.home)) return 0;
    if (location.startsWith(AppRouter.tasks)) return 1; // Handle Tasks route
    if (location.startsWith(AppRouter.history)) return 2;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        GoRouter.of(context).go(AppRouter.home);
        break;
      case 1:
        GoRouter.of(context).go(AppRouter.tasks); // Navigate to Tasks
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
