// lib/main.dart
// Trivial change to trigger linter
import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show WidgetsFlutterBinding, DartPluginRegistrant;
import 'package:flutter/foundation.dart' show BindingBase;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:provider/provider.dart';
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
// import 'package:firebase_app_check/firebase_app_check.dart'; // Keep this commented out as it may be causing issues
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/data/repositories/auth_repository.dart';
import 'package:ai_therapist_app/data/repositories/user_repository.dart';
import 'package:ai_therapist_app/data/repositories/session_repository.dart';
import 'package:ai_therapist_app/data/repositories/message_repository.dart';
import 'package:ai_therapist_app/utils/error_handling.dart';
import 'package:ai_therapist_app/utils/connectivity_checker.dart';
import 'package:ai_therapist_app/utils/firestore_helpers.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_therapist_app/services/theme_service.dart';

// Global variable to track Firebase initialization state
bool _firebaseInitialized = false;

// Background message handler (comment out body for now if causing issues)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only initialize Firebase if it hasn't been done yet
  if (!_firebaseInitialized) {
    // Ensure Flutter is initialized in the isolate
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Try to get existing Firebase app first
      try {
        _app = Firebase.app();
        debugPrint('[BackgroundHandler] Using existing Firebase app');
      } catch (e) {
        // Initialize Firebase if no existing app
        debugPrint(
            '[BackgroundHandler] No existing app, initializing Firebase');
        _app = await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('[BackgroundHandler] Firebase initialized successfully');
      }
      _firebaseInitialized = true;
    } catch (e) {
      debugPrint('[BackgroundHandler] Firebase init error: $e');
    }
  }

  debugPrint('Handling a background message: ${message.messageId}');
}

// Global reference to FirebaseApp
FirebaseApp? _app;

// Get the existing Firebase app or initialize it if it doesn't exist
Future<FirebaseApp?> _initializeFirebase() async {
  if (_app != null) {
    debugPrint('[Firebase] Returning cached Firebase app instance');
    return _app;
  }

  try {
    // First try to get existing app
    try {
      _app = Firebase.app();
      debugPrint('[Firebase] Got existing Firebase app: ${_app?.name}');
    } catch (e) {
      // If no existing app, initialize a new one
      debugPrint('[Firebase] No existing app found, initializing: $e');
      _app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('[Firebase] Firebase newly initialized: ${_app?.name}');
    }
    _firebaseInitialized = true;
    return _app;
  } catch (e) {
    // Special handling for duplicate app error
    if (e.toString().contains('duplicate-app')) {
      debugPrint(
          '[Firebase] Caught duplicate app error, trying to get existing instance');
      try {
        _app = Firebase.app();
        _firebaseInitialized = true;
        return _app;
      } catch (innerError) {
        debugPrint(
            '[Firebase] Failed to get existing app after error: $innerError');
      }
    }
    debugPrint('[Firebase] Error during Firebase initialization: $e');
    return null;
  }
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

Future<void> main() async {
  // Set zone error fatal to false to avoid Flutter zone binding errors
  BindingBase.debugZoneErrorsAreFatal = false;

  debugPrint('[Main] Starting app initialization.');

  // Run the entire app in a single guarded zone to avoid zone mismatches
  runZonedGuarded(() async {
    // 1. Ensure Flutter bindings are initialized first - inside the same zone as runApp
    final binding = WidgetsFlutterBinding.ensureInitialized();
    debugPrint(
        '[Main] Flutter bindings initialized in the same zone as runApp.');

    // 2. Access the existing Firebase app instance
    final firebaseApp = await _initializeFirebase();
    if (firebaseApp != null) {
      debugPrint('[Main] Found existing Firebase app: ${firebaseApp.name}');
      _firebaseInitialized = true;
    } else {
      debugPrint(
          '[Main] Could not get Firebase app instance, some features may be limited');
    }

    // 3. Only register background messaging handler if Firebase is available
    if (_firebaseInitialized) {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      debugPrint('[Main] Background messaging handler registered.');
    }

    // 4. Setup error handling
    debugPrint('[Main] Setting up error handlers.');
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _handleGlobalError(
          details.exception, details.stack ?? StackTrace.current);
    };

    // 5. Setup Bloc observer for debugging
    if (kDebugMode) {
      Bloc.observer = SimpleBlocObserver();
      debugPrint('[Main] Set up Bloc observer for debugging.');
    }

    // 6. Initialize service locator (GetIt)
    debugPrint('[Main] Setting up service locator...');
    try {
      await setupServiceLocator();
      debugPrint('[Main] Service locator setup complete.');
    } catch (e) {
      debugPrint('[Main] ERROR during service locator setup: $e');
    }

    // 7. Initialize other services
    debugPrint('[Main] Initializing app services...');
    try {
      // First check connectivity - this is quick
      debugPrint('[Main] Checking network connectivity...');
      final connectivityChecker = ConnectivityChecker();
      final isConnected = await connectivityChecker.isOffline() == false;
      debugPrint(
          '[Main] Network is ${isConnected ? "available ✅" : "unavailable ⚠️"}');

      // Initialize database - required for basic functionality
      try {
        debugPrint('[Main] Initializing database...');
        final appDatabase = AppDatabase();
        await appDatabase.database;
        debugPrint('[Main] Database initialized successfully');
      } catch (e) {
        debugPrint('[Main] ERROR initializing database: $e');
      }

      // Additional Firebase check for Firestore Native mode - only if connected
      if (isConnected) {
        try {
          debugPrint('[Main] Verifying Firestore setup...');
          final firestoreHelper = FirestoreHelper();
          final isFirestoreReady = await safeOperation(
                () => firestoreHelper.verifyFirestoreSetup(
                  requiredCollections: ['users', 'sessions', 'messages'],
                ),
                timeoutSeconds: 5,
                operationName: 'Firestore verification',
              ) ??
              false;

          if (isFirestoreReady) {
            debugPrint('[Main] Firestore setup verified successfully ✅');
          } else {
            debugPrint('[Main] Issues with Firestore setup !');
          }
        } catch (e) {
          debugPrint('[Main] Error checking Firestore: $e');
        }
      }

      // Initialize Firebase services if GetIt is available
      await _initializeFirebaseServices();

      // Initialize ConfigService and ApiClient with better error handling
      await _initializeConfigAndApi();

      // Initialize notification permissions if needed - safely
      await _requestNotificationPermissions();

      debugPrint('[Main] App services initialized successfully.');
    } catch (e) {
      debugPrint('[Main] ERROR initializing services: $e');
    }

    // Add explicit UI startup logging
    debugPrint('[Main] Starting app UI...');
    try {
      debugPrint('[Main] Running app in same zone.');
      runApp(const AiTherapistApp());
      debugPrint('[Main] App should now be visible!');
    } catch (e) {
      debugPrint('[Main] Critical error in final app startup: $e');
      // Last resort fallback - try to show a minimal error UI
      runApp(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(child: Text('Error starting app: $e')),
        ),
      ));
    }
  }, (error, stack) {
    debugPrint('[Main] UNCAUGHT ERROR in app: $error');
    debugPrint('[Main] Stack trace: $stack');
    _handleGlobalError(error, stack);
  });
}

// Initialize all other necessary services
Future<void> _initializeServices() async {
  // This method is no longer used - functionality moved to inline code in main()
  debugPrint('[Main] WARNING: Using deprecated _initializeServices method');

  // Database initialization handled directly in main() now

  // Firebase services initialization moved to _initializeFirebaseServices()

  // Initialize notification permissions if needed
  try {
    debugPrint(
        '[Main] Requesting notification permissions via deprecated method...');
    await _requestNotificationPermissions();
    debugPrint('[Main] Notification permissions setup complete');
  } catch (e) {
    debugPrint('[Main] ERROR setting up notification permissions: $e');
  }
}

// Request notification permissions
Future<void> _requestNotificationPermissions() async {
  // First check if we're running on a platform that supports notifications
  // This is not strictly necessary but helps avoid unnecessary API calls
  try {
    debugPrint('[Main] Starting notification permission request');

    // Skip if FirebaseService isn't registered
    if (!serviceLocator.isRegistered<FirebaseService>()) {
      debugPrint(
          '[Main] FirebaseService not registered, skipping notification permissions');
      return;
    }

    // Use safeOperation with increased timeout
    await safeOperation(
      () async {
        final firebaseService = serviceLocator<FirebaseService>();
        await firebaseService.initMessaging();
        debugPrint('[Main] Notification permissions setup complete');
      },
      timeoutSeconds: 12, // Increased from 8
      operationName: 'Notification permissions setup',
    );
  } catch (e) {
    // Just log and continue - notifications are not critical for app functionality
    debugPrint('[Main] Non-fatal error in notification setup: $e');
  }
}

// Main app widget
class AiTherapistApp extends StatefulWidget {
  const AiTherapistApp({Key? key}) : super(key: key);

  @override
  State<AiTherapistApp> createState() => _AiTherapistAppState();
}

class _AiTherapistAppState extends State<AiTherapistApp> {
  late ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = serviceLocator<ThemeService>();
    _initTheme();
  }

  Future<void> _initTheme() async {
    await _themeService.init();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with ErrorBoundary to catch errors in the widget tree
    return ErrorBoundary(
      child: ChangeNotifierProvider.value(
        value: _themeService,
        child: Consumer<ThemeService>(
          builder: (context, themeService, _) {
            return BlocProvider(
              create: (context) => AuthBloc(
                authService: serviceLocator<AuthService>(),
              )..add(CheckAuthStatusEvent()),
              child: MaterialApp.router(
                title: 'AI Therapist',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeService.themeMode,
                debugShowCheckedModeBanner: false,
                routerConfig: AppRouter.router,
              ),
            );
          },
        ),
      ),
    );
  }
}

// Error boundary widget to catch and display errors in the widget tree
class ErrorBoundary extends StatefulWidget {
  final Widget child;

  const ErrorBoundary({Key? key, required this.child}) : super(key: key);

  @override
  _ErrorBoundaryState createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  dynamic _error;
  StackTrace? _stackTrace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset error state on rebuild
    _hasError = false;
    _error = null;
    _stackTrace = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Error view
      return Material(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('App Error'),
            backgroundColor: Colors.red,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 60,
                ),
                const SizedBox(height: 16),
                const Text(
                  'An unexpected error occurred',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _error?.toString() ?? 'Unknown error',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _error = null;
                      _stackTrace = null;
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If no error, show the normal content - fixed to properly return a Widget
    // Set up the error handler first
    ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
      // Log the error
      if (kDebugMode) {
        print('Error caught by ErrorBoundary:');
        print(errorDetails.exception);
        print(errorDetails.stack);
      }

      // Update state to show error UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _hasError = true;
          _error = errorDetails.exception;
          _stackTrace = errorDetails.stack;
        });
      });

      // Return an empty container for the error widget
      return Container();
    };

    // Return the child widget
    return widget.child;
  }
}

// Add a helper method for Firebase services initialization
Future<void> _initializeFirebaseServices() async {
  if (!_firebaseInitialized) {
    debugPrint(
        '[Main] Skipping FirebaseService initialization as Firebase is not available');
    return;
  }

  try {
    debugPrint(
        '[Main] Initializing FirebaseService with existing Firebase instance...');
    if (serviceLocator.isRegistered<FirebaseService>()) {
      await safeOperation(
        () => serviceLocator<FirebaseService>().init(),
        timeoutSeconds: 10,
        operationName: 'Firebase services initialization',
      );
      debugPrint('[Main] FirebaseService initialized successfully');
    } else {
      debugPrint('[Main] FirebaseService not registered in serviceLocator');
    }
  } catch (e) {
    debugPrint('[Main] ERROR initializing FirebaseService: $e');
  }
}

// Helper method for initializing ConfigService and ApiClient
Future<void> _initializeConfigAndApi() async {
  try {
    debugPrint('[Main] Initializing ConfigService...');

    // Create and initialize ConfigService
    final configService = await safeOperation(
      () async {
        final service = ConfigService();
        await service.init();
        return service;
      },
      timeoutSeconds: 5,
      operationName: 'ConfigService initialization',
    );

    if (configService == null) {
      debugPrint('[Main] Failed to initialize ConfigService');
      return;
    }

    // Register in service locator
    serviceLocator.registerSingleton<ConfigService>(configService);

    // Log the baseUrl for diagnostic purposes
    final baseUrl = configService.llmApiEndpoint;
    debugPrint('[Main] API baseUrl: $baseUrl');

    if (baseUrl.isEmpty) {
      debugPrint(
          '[Main] WARNING: API baseUrl is empty! ApiClient may not work properly.');
    }

    // Create and register ApiClient
    debugPrint('[Main] Creating ApiClient with baseUrl: $baseUrl');
    final apiClient = ApiClient(configService: configService);
    serviceLocator.registerSingleton<ApiClient>(apiClient);

    // Register repositories that depend on ApiClient
    debugPrint('[Main] Registering repositories...');

    serviceLocator.registerLazySingleton<AuthRepository>(() => AuthRepository(
          apiClient: serviceLocator<ApiClient>(),
        ));

    serviceLocator.registerLazySingleton<UserRepository>(() => UserRepository(
          apiClient: serviceLocator<ApiClient>(),
        ));

    serviceLocator
        .registerLazySingleton<SessionRepository>(() => SessionRepository(
              apiClient: serviceLocator<ApiClient>(),
              appDatabase: serviceLocator<AppDatabase>(),
            ));

    serviceLocator
        .registerLazySingleton<MessageRepository>(() => MessageRepository(
              apiClient: serviceLocator<ApiClient>(),
              appDatabase: serviceLocator<AppDatabase>(),
            ));

    // Register TherapyService
    serviceLocator
        .registerLazySingleton<TherapyService>(() => TherapyService());

    // Register AuthService
    serviceLocator.registerLazySingleton<AuthService>(() => AuthService());

    debugPrint(
        '[Main] All repositories and services registered successfully ✅');
  } catch (e) {
    debugPrint('[Main] ERROR initializing ConfigService/ApiClient: $e');
  }
}
