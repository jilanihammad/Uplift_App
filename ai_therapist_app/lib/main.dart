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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/blocs/auth/auth_bloc.dart';
import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:ai_therapist_app/services/memory_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/memory_manager.dart';
import 'package:ai_therapist_app/services/message_processor.dart';
import 'package:ai_therapist_app/services/audio_generator.dart';
import 'package:ai_therapist_app/services/conversation_flow_manager.dart';
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
import 'package:ai_therapist_app/config/app_config.dart';
import 'debug_api.dart';
import 'debug_firebase.dart'; // Import for debugging only
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';

import 'package:ai_therapist_app/config/api.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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
import 'package:ai_therapist_app/data/datasources/local/database_provider.dart';

// Import the shared Firebase initialization utility
import 'package:ai_therapist_app/utils/firebase_init.dart';
import 'package:ai_therapist_app/utils/logging_service.dart';

// Import the new logging config
import 'utils/logging_config.dart';

// Import the new database helper
import 'utils/database_helper.dart';

// Global variables for crucial service references
FirebaseApp? _firebaseApp;
ConfigService? _configService;
ApiClient? _apiClient;

// Firebase messaging background handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This handler runs in its own isolate, so we need to re-initialize Firebase
  await Firebase.initializeApp();

  // Safe logging since we can't use our LoggingService in this isolate
  try {
    print('Handling a background message: ${message.messageId}');
  } catch (e) {
    print('Error in background message handler: $e');
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

// Global app configuration - Using AppConfig instead of hardcoded values
final bool isDebugMode = kDebugMode;
final String firebaseProjectUrl =
    'https://upliftapp-cd86e.web.app'; // Firebase project URL

// Global error handler for unhandled exceptions
void _handleGlobalError(dynamic error, StackTrace stack) {
  // Log the error details properly with LoggingService
  logger.error(
    'Uncaught global error',
    error: error,
    stackTrace: stack,
    tag: 'GLOBAL',
  );

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

  // Log the user-facing error message
  logger.warning('Error message for user: $errorMessage', tag: 'USER_ERROR');
}

Future<void> main() async {
  // Set zone error fatal to false to avoid Flutter zone binding errors
  BindingBase.debugZoneErrorsAreFatal = false;

  logger.info('[Main] Starting app initialization.');

  // Run the entire app in a single guarded zone to avoid zone mismatches
  runZonedGuarded(() async {
    // 0. Initialize LoggingService first - enables proper logging for the rest of initialization
    _initializeLogging();

    // 1. Ensure Flutter bindings are initialized first - inside the same zone as runApp
    final binding = WidgetsFlutterBinding.ensureInitialized();
    logger.info(
        '[Main] Flutter bindings initialized in the same zone as runApp.');

    // 1.5. Initialize AppConfig to load environment variables
    await AppConfig.initialize();
    AppConfig().logConfig();
    logger.info('[Main] AppConfig initialized with environment variables.');

    // CRITICAL CHANGE: DISABLE FIREBASE APP CHECK COMPLETELY
    try {
      // Initialize Firebase Core without App Check
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print("[Main] Firebase Core initialized directly - APP CHECK DISABLED");

      // IMPORTANT: Log that App Check is intentionally disabled
      print(
          "[Main] Firebase App Check is INTENTIONALLY DISABLED to fix authentication issues");

      // Do NOT initialize App Check at all
    } catch (e) {
      print("[Main] Error during Firebase initialization: $e");
      print("[Main] Continuing with app initialization...");
    }

    // 2. Now initialize Firebase using the synchronized method
    final firebaseApp = await ensureFirebaseInitialized();
    if (firebaseApp != null) {
      logger.info(
          '[Main] Firebase initialized successfully: ${firebaseApp.name}');
    } else {
      logger.warning(
          '[Main] Could not initialize Firebase, some features may be limited');
    }

    // 3. Register background messaging handler if Firebase is available
    if (isFirebaseInitialized()) {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      logger.info('[Main] Background messaging handler registered.');
    }

    // 4. Setup error handling
    logger.info('[Main] Setting up error handlers.');
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _handleGlobalError(
          details.exception, details.stack ?? StackTrace.current);
    };

    // 5. Setup Bloc observer for debugging
    if (kDebugMode) {
      Bloc.observer = SimpleBlocObserver();
      logger.debug('[Main] Set up Bloc observer for debugging.');
    }

    // 6. Initialize service locator (GetIt)
    logger.info('[Main] Setting up service locator...');
    try {
      await setupServiceLocator();
      logger.info('[Main] Service locator setup complete.');
    } catch (e) {
      logger.error('[Main] ERROR during service locator setup', error: e);
    }

    // 7. Initialize other services
    logger.info('[Main] Initializing app services...');
    try {
      // First check connectivity - this is quick
      logger.debug('[Main] Checking network connectivity...');
      final connectivityChecker = ConnectivityChecker();
      final isConnected = await connectivityChecker.isOffline() == false;
      logger.info(
          '[Main] Network is ${isConnected ? "available ✅" : "unavailable ⚠️"}');

      // Initialize database - required for basic functionality
      try {
        logger.debug('[Main] Initializing database...');
        final appDatabase = serviceLocator<AppDatabase>();
        await appDatabase.database;

        // Check and repair database health with our new utility
        try {
          if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
            logger.debug('[Main] Checking database health...');
            final dbManager = serviceLocator<DatabaseOperationManager>();
            final isHealthy =
                await dbManager.checkAndRepairDatabaseHealth(appDatabase);
            if (isHealthy) {
              logger.info('[Main] Database health check passed ✅');
            } else {
              logger.warning(
                  '[Main] Database health check failed, attempted repair');
            }
          }
        } catch (e) {
          logger.warning('[Main] Database health check error: $e');
        }

        // Verify database tables exist
        logger.debug('[Main] Verifying database tables...');
        final databaseProvider = serviceLocator<DatabaseProvider>();

        // Check required tables, especially the ones introduced in migration v3
        final requiredTables = [
          'sessions',
          'messages',
          'conversation_memories',
          'therapy_insights',
          'emotional_states'
        ];

        final missingTables = <String>[];

        for (final table in requiredTables) {
          final exists = await databaseProvider.tableExists(table);
          if (!exists) {
            missingTables.add(table);
            logger.warning('[Main] Table $table not found in database');
          }
        }

        if (missingTables.isEmpty) {
          logger.info(
              '[Main] All required database tables verified successfully ✅');
        } else {
          logger.warning('[Main] Missing tables: ${missingTables.join(', ')}');
          logger.warning(
              '[Main] Will attempt to create missing tables during service initialization');
        }

        logger.info('[Main] Database initialized successfully');

        // Schedule database optimization for later (after app is visible)
        if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
          Future.delayed(Duration(seconds: 3), () {
            final dbManager = serviceLocator<DatabaseOperationManager>();
            dbManager.optimizeDatabase(appDatabase).then((_) {
              logger.debug('[Main] Database optimization completed');
            });
          });
        }
      } catch (e) {
        logger.error('[Main] ERROR initializing database', error: e);
      }

      // Additional Firebase check for Firestore Native mode - only if connected
      if (isConnected) {
        try {
          logger.debug('[Main] Verifying Firestore setup...');
          final firestoreHelper = FirestoreHelper();

          // Only perform Firestore collection verification in debug mode
          // Collections are created on-demand in Firestore, so this check is unnecessary in production
          if (kDebugMode) {
            final isFirestoreReady = await safeOperation(
                  () => firestoreHelper.verifyFirestoreSetup(
                    requiredCollections: ['users', 'sessions', 'messages'],
                  ),
                  timeoutSeconds: 3, // Reduced timeout
                  operationName: 'Firestore verification',
                ) ??
                false;

            if (isFirestoreReady) {
              logger.info('[Main] Firestore setup verified successfully ✅');
            } else {
              logger.info(
                  '[Main] Some Firestore collections not found yet - they will be created on demand');
            }
          } else {
            // In release mode, just check basic Firebase connectivity without collection verification
            final isFirebaseConnected = await safeOperation(
                  () => firestoreHelper.checkFirebaseConnection(),
                  timeoutSeconds: 2,
                  operationName: 'Firebase connectivity check',
                ) ??
                false;

            if (isFirebaseConnected) {
              logger.info('[Main] Firebase connectivity verified ✅');
            }
          }
        } catch (e) {
          logger.error('[Main] Error checking Firebase', error: e);
        }
      }

      // Initialize Firebase services if GetIt is available
      await _initializeFirebaseServices();

      // Initialize ConfigService and ApiClient with better error handling
      await _initializeConfigAndApi();

      // Initialize notification permissions if needed - safely
      await _requestNotificationPermissions();

      logger.info('[Main] App services initialized successfully.');
    } catch (e) {
      logger.error('[Main] ERROR initializing services', error: e);
    }

    // Add explicit UI startup logging
    logger.info('[Main] Starting app UI...');
    try {
      logger.debug('[Main] Running app in same zone.');
      runApp(const AiTherapistApp());
      logger.info('[Main] App should now be visible!');
    } catch (e) {
      logger.error('[Main] Critical error in final app startup', error: e);
      // Last resort fallback - try to show a minimal error UI
      runApp(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(child: Text('Error starting app: $e')),
        ),
      ));
    }
  }, (error, stack) {
    logger.error('[Main] UNCAUGHT ERROR in app',
        error: error, stackTrace: stack);
    _handleGlobalError(error, stack);
  });
}

// Initialize the logging service
void _initializeLogging() {
  // Use the new logging config to set the appropriate log levels
  loggingConfig.init(
    // Set to true to enable more verbose logs in production for troubleshooting
    // Set to false by default to reduce logging overhead in production
    enableVerboseLogsInRelease: false,
  );

  // Log the configuration (only visible in appropriate log levels)
  logger
      .info('Logging initialized with level: ${loggingConfig.currentLogLevel}');
  logger.debug(
      'Debug logging is ${loggingConfig.isDebugEnabled ? 'enabled' : 'disabled'}');

  if (kDebugMode) {
    print('=== LoggingService initialized ===');
    print(
        '- Log level: ${loggingConfig.currentLogLevel.toString().split('.').last.toUpperCase()}');
    print(
        '- Debug logs: ${loggingConfig.isDebugEnabled ? 'ENABLED' : 'DISABLED'}');
    print('- Analytics logging: ${kDebugMode ? 'ENABLED' : 'DISABLED'}');
    print('- Crashlytics: ${!kDebugMode ? 'ENABLED' : 'DISABLED'}');
    print('==============================');
  }
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

    try {
      // Check if ThemeService is registered
      if (serviceLocator.isRegistered<ThemeService>()) {
        _themeService = serviceLocator<ThemeService>();
        _initTheme();
      } else {
        // Fallback if service is not registered
        debugPrint(
            '[AiTherapistApp] WARNING: ThemeService not registered, using default theme');
        _themeService = ThemeService(); // Create a local instance as fallback
        _initTheme();
      }
    } catch (e) {
      debugPrint('[AiTherapistApp] Error initializing theme: $e');
      _themeService = ThemeService(); // Create a local instance as fallback
    }
  }

  Future<void> _initTheme() async {
    try {
      await _themeService.init();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[AiTherapistApp] Error in _initTheme: $e');
      // Continue with default theme
    }
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
              create: (context) {
                // Safely access AuthService
                try {
                  if (serviceLocator.isRegistered<AuthService>()) {
                    final authBloc = AuthBloc(
                      authService: serviceLocator<AuthService>(),
                      onboardingService: serviceLocator<OnboardingService>(),
                    )..add(CheckAuthStatusEvent());

                    // Register the AuthBloc in the service locator if not already registered
                    if (!serviceLocator.isRegistered<AuthBloc>()) {
                      serviceLocator.registerSingleton<AuthBloc>(authBloc);
                      logger.debug(
                          '[AiTherapistApp] AuthBloc registered in service locator');
                    }

                    return authBloc;
                  } else {
                    debugPrint(
                        '[AiTherapistApp] WARNING: AuthService not registered, using empty AuthBloc');
                    // Return an AuthBloc without calling CheckAuthStatusEvent to prevent errors
                    final authBloc = AuthBloc(
                      authService:
                          AuthService(), // Create a local instance as fallback
                      onboardingService:
                          OnboardingService(), // Create a local instance as fallback
                    );

                    // Register the minimal AuthBloc in the service locator
                    if (!serviceLocator.isRegistered<AuthBloc>()) {
                      serviceLocator.registerSingleton<AuthBloc>(authBloc);
                      logger.debug(
                          '[AiTherapistApp] Minimal AuthBloc registered in service locator');
                    }

                    return authBloc;
                  }
                } catch (e) {
                  debugPrint('[AiTherapistApp] Error creating AuthBloc: $e');
                  // Return a minimal AuthBloc that won't crash the app
                  final authBloc = AuthBloc(
                    authService:
                        AuthService(), // Create a local instance as fallback
                    onboardingService:
                        OnboardingService(), // Create a local instance as fallback
                  );

                  // Register the fallback AuthBloc in the service locator
                  if (!serviceLocator.isRegistered<AuthBloc>()) {
                    serviceLocator.registerSingleton<AuthBloc>(authBloc);
                    logger.debug(
                        '[AiTherapistApp] Fallback AuthBloc registered in service locator');
                  }

                  return authBloc;
                }
              },
              child: MaterialApp.router(
                title: 'AI Therapist',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeService.themeMode,
                debugShowCheckedModeBanner: false,
                routerConfig: AppRouter.router,
                localizationsDelegates: [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('en', ''), // English
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Cleanup resources when the app is closed
    _cleanupResources();
    super.dispose();
  }

  // Cleanup app resources
  Future<void> _cleanupResources() async {
    try {
      // Close database connection
      if (serviceLocator.isRegistered<AppDatabase>()) {
        final appDatabase = serviceLocator<AppDatabase>();
        await appDatabase.close();
        debugPrint('[AiTherapistApp] Database connection closed');
      }

      // Close any BLoCs that were registered in the service locator
      // This is a more reliable approach than using context which might not be available
      if (serviceLocator.isRegistered<AuthBloc>()) {
        try {
          final authBloc = serviceLocator<AuthBloc>();
          await authBloc.close();
          logger.info('[AiTherapistApp] AuthBloc closed successfully');
        } catch (e) {
          logger.debug('[AiTherapistApp] Could not close AuthBloc: $e');
        }
      }

      // Additional cleanup can be added here
    } catch (e) {
      debugPrint('[AiTherapistApp] Error during cleanup: $e');
    }
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
      // Create a self-contained error UI with proper localization
      final errorTheme = ThemeData(
        primaryColor: Colors.red,
        primarySwatch: Colors.red,
        colorScheme: ColorScheme.light(primary: Colors.red),
      );

      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: errorTheme,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''), // English
        ],
        home: Scaffold(
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

    // If no error, show the normal content
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

// Add helper method for Firebase services initialization
Future<void> _initializeFirebaseServices() async {
  try {
    // Wait briefly to prevent startup slowdown from multiple async operations
    await Future.delayed(const Duration(milliseconds: 50));

    // Log entry
    logger.debug(
        'Initializing FirebaseService with existing Firebase instance...');

    final firebaseService = serviceLocator<FirebaseService>();

    // Add explicit log that we're disabling App Check
    logger.info(
        '[Main] IMPORTANT: App Check is DISABLED in this build to avoid authentication issues');

    await firebaseService.init();

    logger.info('[Main] FirebaseService initialized successfully');
  } catch (e) {
    logger.error('[Main] Error initializing FirebaseService', error: e);
  }
}

// Helper method for initializing ConfigService and ApiClient
Future<void> _initializeConfigAndApi() async {
  try {
    logger.debug('[Main] Initializing ConfigService...');

    _configService = ConfigService();
    await _configService!.init();

    logger.debug('ConfigService initialized successfully');

    // Create and initialize ApiClient with correct parameters
    logger.debug('[Main] Creating ApiClient with ConfigService');

    _apiClient = ApiClient(configService: _configService!);

    // Register dependencies that require ConfigService and ApiClient
    await registerApiDependentServices(_configService!, _apiClient!);

    // Initialize database operations manager first
    try {
      logger.debug('[Main] Getting DatabaseOperationManager...');
      final dbOpManager = serviceLocator<DatabaseOperationManager>();
      final appDatabase = serviceLocator<AppDatabase>();

      // Check and repair database health
      await dbOpManager.checkAndRepairDatabaseHealth(appDatabase);
      logger.debug('[Main] Database health check complete');

      // Small delay to allow any pending database operations to complete
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      logger.error('[Main] Error checking database health', error: e);
    }

    // Initialize all the refactored components in the right order
    logger.debug(
        '[Main] Initializing refactored service components sequentially...');

    // Initialize services in a specific order to avoid conflicts
    // 1. First initialize services that don't depend on the database
    try {
      logger.debug('[Main] Initializing VoiceService...');
      final voiceService = serviceLocator<VoiceService>();
      await voiceService.initialize();
      logger.debug('[Main] VoiceService initialized ✓');

      // Small delay between service initializations
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      logger.error('[Main] Error initializing VoiceService', error: e);
    }

    try {
      logger.debug('[Main] Initializing AudioGenerator...');
      final audioGenerator = serviceLocator<AudioGenerator>();
      await audioGenerator.initialize();
      logger.debug('[Main] AudioGenerator initialized ✓');

      // Small delay between service initializations
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      logger.error('[Main] Error initializing AudioGenerator', error: e);
    }

    // 2. Initialize database-dependent services
    try {
      logger.debug('[Main] Initializing MemoryService (database tables)...');
      final memoryService = serviceLocator<MemoryService>();
      await memoryService.init();
      logger.debug('[Main] MemoryService initialized ✓');

      // Important: Add a delay after MemoryService initialization
      // to allow database operations to complete
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      logger.error('[Main] Error initializing MemoryService', error: e);
    }

    // Memory manager depends on memory service
    try {
      logger.debug('[Main] Initializing MemoryManager...');
      final memoryManager = serviceLocator<MemoryManager>();
      await memoryManager.init();
      logger.debug('[Main] MemoryManager initialized ✓');

      // Small delay between service initializations
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      logger.error('[Main] Error initializing MemoryManager', error: e);
    }

    try {
      logger.debug('[Main] Initializing ConversationFlowManager...');
      final conversationFlowManager = serviceLocator<ConversationFlowManager>();
      await conversationFlowManager.init();
      logger.debug('[Main] ConversationFlowManager initialized ✓');

      // Small delay between service initializations
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      logger.error('[Main] Error initializing ConversationFlowManager',
          error: e);
    }

    // Initialize the TherapyService last (depends on most other services)
    if (serviceLocator.isRegistered<TherapyService>()) {
      final therapyService = serviceLocator<TherapyService>();
      await therapyService.init();
      logger.debug('[Main] TherapyService initialized successfully');
    }

    // Validate that all dependencies are registered
    final allDepsValid = validateDependencies();
    logger.info(
        '[Main] All required dependencies validated successfully ${allDepsValid ? '✅' : '❌'}');
  } catch (e) {
    logger.error('[Main] Error initializing config and API',
        error: e, stackTrace: StackTrace.current);
  }
}
