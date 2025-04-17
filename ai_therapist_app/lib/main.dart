// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show WidgetsFlutterBinding, DartPluginRegistrant;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/blocs/auth/auth_bloc.dart';
import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/firebase_options.dart';
import 'package:ai_therapist_app/services/firebase_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ai_therapist_app/screens/splash_screen.dart';
import 'package:ai_therapist_app/screens/login_screen.dart';
import 'package:ai_therapist_app/screens/register_screen.dart';
import 'package:ai_therapist_app/screens/home_screen.dart';
import 'package:ai_therapist_app/screens/chat_screen.dart';
import 'package:ai_therapist_app/screens/profile_screen.dart';
import 'package:ai_therapist_app/screens/onboarding/onboarding_wrapper.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'debug_api.dart';
import 'debug_firebase.dart'; // Import for debugging only
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';

import 'package:ai_therapist_app/config/api.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// Background message handler for Firebase Cloud Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for the background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Ensure the binary messenger is initialized for the background isolate
  await FirebaseMessaging.instance.setAutoInitEnabled(true);

  print("Handling a background message: ${message.messageId}");
}

// Error handling bloc observer for logging
class SimpleBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      print('Bloc error: $error');
      print('Stack trace: $stackTrace');
    }
    super.onError(bloc, error, stackTrace);
  }
}

// Global app configuration
final bool isDebugMode = kDebugMode;
final String apiBaseUrl =
    'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app'; // Cloud backend URL
final String firebaseProjectUrl =
    'https://upliftapp-cd86e.web.app'; // Firebase project URL

// Global error handler for unhandled exceptions
void _handleGlobalError(Object error, StackTrace stack) {
  if (kDebugMode) {
    print('Unhandled error: $error');
    print(stack);
  }

  String errorMessage = 'An unexpected error occurred';

  // Provide more specific error messages for common errors
  if (error is SocketException) {
    errorMessage =
        'Network connection error. Please check your internet connection and try again.';
  } else if (error is TimeoutException) {
    errorMessage = 'Connection timed out. Please try again later.';
  } else if (error is ApiException) {
    errorMessage = error.message;
  } else if (error.toString().contains('semaphore timeout')) {
    errorMessage = 'Server connection timed out. Please try again later.';
  }

  // Show a toast or notification here if possible
  // Since we can't use BuildContext here, we'll just log it
  if (kDebugMode) {
    print('Error message for user: $errorMessage');
  }
}

// Helper class for compute method parameters
class ServiceInitParams {
  final String serviceType;

  ServiceInitParams(this.serviceType);
}

// Initialize a service in an isolate
Future<bool> _initializeServiceIsolate(ServiceInitParams params) async {
  try {
    switch (params.serviceType) {
      case 'userProfile':
        if (serviceLocator.isRegistered<UserProfileService>()) {
          await serviceLocator<UserProfileService>().init();
        }
        break;
      case 'onboarding':
        if (serviceLocator.isRegistered<OnboardingService>()) {
          await serviceLocator<OnboardingService>().init();
        }
        break;
      case 'therapy':
        if (serviceLocator.isRegistered<TherapyService>()) {
          await serviceLocator<TherapyService>().init();
        }
        break;
      case 'firebase':
        if (serviceLocator.isRegistered<FirebaseService>()) {
          await serviceLocator<FirebaseService>().init();
          await serviceLocator<FirebaseService>().initMessaging();
        }
        break;
    }
    return true;
  } catch (e) {
    if (kDebugMode) {
      print('Failed to initialize ${params.serviceType} service: $e');
    }
    return false;
  }
}

// Initialize the database in background
Future<void> _initializeDatabase() async {
  try {
    final appDatabase = AppDatabase();
    await appDatabase.database;
    if (kDebugMode) {
      print('Database initialized successfully');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Database initialization failed: $e');
    }
  }
}

Future<void> main() async {
  // Set up error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
    _handleGlobalError(details.exception, details.stack ?? StackTrace.current);
  };

  // This ensures Flutter is initialized in the same zone as runApp
  WidgetsFlutterBinding.ensureInitialized();

  // Register background message handler before anything else
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Set up custom bloc observer for better error handling
  Bloc.observer = SimpleBlocObserver();

  try {
    // Start the app immediately with a loading indicator
    // This allows the UI to be responsive while services initialize
    runApp(const LoadingApp());

    // Initialize essential services first
    await _initializeEssentialServices();

    // Then initialize remaining services in the background
    _initializeRemainingServices();

    // Run the main app after essential services are ready
    runApp(const MyApp());
  } catch (e) {
    if (kDebugMode) {
      print('Error during app initialization: $e');
    }
    // Fallback to a simple app if initialization fails
    runApp(const FallbackApp());
  }
}

// Initialize essential services
Future<void> _initializeEssentialServices() async {
  try {
    // Initialize Firebase Core first - this is required
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure FirebaseAppCheck for better security
    await FirebaseAppCheck.instance.activate(
      // Use debug provider for dev/test
      webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      String? token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        print('FCM Token: $token');
        print('Firebase initialized successfully on Android');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error initializing Firebase: $e');
    }
    // Continue even if Firebase init fails
  }

  // Initialize dependencies for service locator
  await setupServiceLocator();

  // Initialize essential services synchronously
  try {
    if (serviceLocator.isRegistered<OnboardingService>()) {
      await serviceLocator<OnboardingService>().init();
      if (kDebugMode) {
        print("OnboardingService initialized synchronously");
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print("Error initializing OnboardingService synchronously: $e");
    }
  }
}

// Initialize remaining services in the background
void _initializeRemainingServices() {
  // Use a microtask to ensure UI is responsive first
  Future.microtask(() async {
    try {
      final List<Future<void>> initTasks = [];

      // Request permissions only after UI is shown
      if (defaultTargetPlatform == TargetPlatform.android) {
        initTasks.add(_requestNotificationPermissions());
      }

      // Initialize Firebase service
      initTasks.add(
          compute(_initializeServiceIsolate, ServiceInitParams('firebase')));

      // Initialize database asynchronously
      initTasks.add(_initializeDatabase());

      // Initialize other services in parallel
      initTasks.add(
          compute(_initializeServiceIsolate, ServiceInitParams('userProfile')));
      initTasks.add(
          compute(_initializeServiceIsolate, ServiceInitParams('therapy')));

      // Wait for all initialization tasks to complete
      await Future.wait(initTasks);

      if (kDebugMode) {
        print('All services initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during background service initialization: $e');
      }
    }
  });
}

// Request notification permissions separately to avoid blocking the UI
Future<void> _requestNotificationPermissions() async {
  try {
    // Request permission for notifications
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (kDebugMode) {
      print('Notification permissions requested');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting notification permissions: $e');
    }
  }
}

// Simple loading app to show while services initialize
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uplift',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/uplift_logo.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                'Loading...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Fallback app widget if initialization fails
class FallbackApp extends StatelessWidget {
  const FallbackApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    try {
      // Get AuthService from service locator
      final authService = serviceLocator<AuthService>();

      return MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(authService: authService),
          ),
        ],
        child: MaterialApp.router(
          title: 'Uplift',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: AppRouter.router,
        ),
      );
    } catch (e) {
      // If service locator initialization failed, provide a basic fallback
      return MaterialApp(
        title: 'Uplift - Error Mode',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('Service Error')),
          body: Center(
            child: Text('Service initialization error: $e'),
          ),
        ),
      );
    }
  }
}

class _FallbackScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Connection Status'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off,
                size: 64,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              const Text(
                'Some Firebase services are unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This may be due to network issues or Firebase project configuration. The app will still function with limited cloud connectivity.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () {
                  // Try to reinitialize Firebase and restart the app
                  runApp(const LoadingApp());

                  // Use a microtask to allow the LoadingApp to render first
                  Future.microtask(() async {
                    try {
                      // Re-initialize essential services with modified Firestore settings
                      await Firebase.initializeApp(
                        options: DefaultFirebaseOptions.currentPlatform,
                      );

                      // Explicitly configure Firestore with longer timeouts
                      FirebaseFirestore.instance.settings = const Settings(
                        persistenceEnabled: true,
                        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
                        sslEnabled: true,
                      );

                      // Continue with service initialization
                      await setupServiceLocator();
                      _initializeRemainingServices();

                      // Run the main app
                      runApp(const MyApp());
                    } catch (e) {
                      // If initialization fails again, go back to FallbackApp
                      if (kDebugMode) {
                        print('Error during retry initialization: $e');
                      }
                      runApp(const FallbackApp());
                    }
                  });
                },
                child: const Text('Retry Connection',
                    style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // Continue to the main app anyway with normal mode
                  runApp(const MyApp());
                },
                child: const Text('Continue Anyway',
                    style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // Skip Firebase initialization and continue with offline functionality
                  try {
                    final authService = serviceLocator<AuthService>();

                    runApp(MultiBlocProvider(
                      providers: [
                        BlocProvider<AuthBloc>(
                          create: (context) =>
                              AuthBloc(authService: authService),
                        ),
                      ],
                      child: MaterialApp.router(
                        title: 'Uplift Therapist',
                        theme: AppTheme.lightTheme,
                        debugShowCheckedModeBanner: false,
                        routerConfig: AppRouter.router,
                      ),
                    ));
                  } catch (e) {
                    if (kDebugMode) {
                      print('Error in offline mode: $e');
                    }
                    runApp(const FallbackApp());
                  }
                },
                child: const Text('Continue with Offline Mode',
                    style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const FirebaseDebugScreen(),
                    ),
                  );
                },
                child: const Text('View Detailed Status',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print(
        'MyApp build method called - Initializing MaterialApp with SplashScreen');
    try {
      // Get AuthService from service locator
      final authService = serviceLocator<AuthService>();

      // Wrap GoRouter with BlocProvider for AuthBloc
      return MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(authService: authService),
          ),
        ],
        child: MaterialApp.router(
          title: 'Uplift Therapist',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: AppRouter.router,
        ),
      );
    } catch (e) {
      print('ERROR in MyApp build: $e');
      // Fallback to simple MaterialApp on error
      return MaterialApp(
        title: 'Uplift Therapist - Error Mode',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(
            child: Text('Application initialization error: $e'),
          ),
        ),
      );
    }
  }
}
