// lib/main.dart
// Trivial change to trigger linter
import 'dart:async';
import 'dart:async' show unawaited;
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

// Import the new database health checker
import 'utils/database_health_checker.dart';

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
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) print('[Main] App initialization starting...');

  BindingBase.debugZoneErrorsAreFatal = false;
  logger.info('[Main] Starting app initialization.');

  runZonedGuarded(() async {
    debugPrint('[main.dart] Entered runZonedGuarded');

    // CRITICAL: Initialize only essential services first
    _initializeLogging();
    await AppConfig.initialize();
    AppConfig().logConfig();

<<<<<<< Updated upstream
    // CRITICAL CHANGE: DISABLE FIREBASE APP CHECK COMPLETELY
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint(
          "[main.dart] Firebase Core initialized directly - APP CHECK DISABLED");
      debugPrint(
          "[main.dart] Firebase App Check is INTENTIONALLY DISABLED to fix authentication issues");
    } catch (e) {
      debugPrint("[main.dart] Error during Firebase initialization: $e");
      debugPrint("[main.dart] Continuing with app initialization...");
    }

    // 2. Now initialize Firebase using the synchronized method
    final firebaseApp = await ensureFirebaseInitialized();
    if (firebaseApp != null) {
      debugPrint('[main.dart] Firebase initialized successfully');
      logger.info(
          '[Main] Firebase initialized successfully: ${firebaseApp.name}');
    } else {
      debugPrint('[main.dart] Could not initialize Firebase');
      logger.warning(
          '[Main] Could not initialize Firebase, some features may be limited');
    }

    // 3. Register background messaging handler if Firebase is available
    if (isFirebaseInitialized()) {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      debugPrint('[main.dart] Background messaging handler registered.');
      logger.info('[Main] Background messaging handler registered.');
    }

    // 4. Setup error handling
    debugPrint('[main.dart] Setting up error handlers.');
    logger.info('[Main] Setting up error handlers.');
=======
    final firebaseApp = await ensureFirebaseInitialized();

    // Setup error handling
>>>>>>> Stashed changes
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _handleGlobalError(
          details.exception, details.stack ?? StackTrace.current);
    };

    if (kDebugMode) {
      Bloc.observer = SimpleBlocObserver();
    }

    // Setup service locator
    await setupServiceLocator();

    // 🚨 CRITICAL CHANGE: Initialize audio services FIRST, before database
    debugPrint('[main.dart] Initializing CRITICAL audio services...');
    try {
      await _initializeCriticalAudioServices();
      debugPrint('[main.dart] ✅ Critical audio services ready');
    } catch (e) {
      debugPrint('[main.dart] 🚨 CRITICAL: Audio services failed: $e');
    }

    // Initialize basic database connection only (no heavy operations)
    try {
      final appDatabase = serviceLocator<AppDatabase>();
      await appDatabase.database;
      debugPrint('[main.dart] ✅ Database connection established.');
    } catch (e) {
      debugPrint('[main.dart] Database connection error: $e');
    }

    // START UI IMMEDIATELY
    debugPrint('[main.dart] Starting app UI...');
    runApp(const AiTherapistApp());
    debugPrint('[main.dart] ✅ App UI started');

    // 🚨 CRITICAL CHANGE: Single PostFrameCallback for all background work
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint(
          '[main.dart] PostFrameCallback: Starting background initialization...');
      await _initializeBackgroundServices();
    });
  }, (error, stack) {
    debugPrint('[main.dart] Uncaught error in runZonedGuarded: $error');
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
    debugPrint('=== LoggingService initialized ===');
    debugPrint(
        '- Log level: ${loggingConfig.currentLogLevel.toString().split('.').last.toUpperCase()}');
    debugPrint(
        '- Debug logs: ${loggingConfig.isDebugEnabled ? 'ENABLED' : 'DISABLED'}');
    debugPrint('- Analytics logging: ${kDebugMode ? 'ENABLED' : 'DISABLED'}');
    debugPrint('- Crashlytics: ${!kDebugMode ? 'ENABLED' : 'DISABLED'}');
    debugPrint('==============================');
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
    debugPrint('[main.dart] AiTherapistApp initState');
    try {
      if (serviceLocator.isRegistered<ThemeService>()) {
        _themeService = serviceLocator<ThemeService>();
        _initTheme();
      } else {
        debugPrint(
            '[main.dart] WARNING: ThemeService not registered, using default theme');
        _themeService = ThemeService();
        _initTheme();
      }
    } catch (e) {
      debugPrint('[main.dart] Error initializing theme: $e');
      _themeService = ThemeService();
    }
  }

  Future<void> _initTheme() async {
    try {
      await _themeService.init();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[main.dart] Error in _initTheme: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[main.dart] AiTherapistApp build');
    return ErrorBoundary(
      child: ChangeNotifierProvider.value(
        value: _themeService,
        child: Consumer<ThemeService>(
          builder: (context, themeService, _) {
            return MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>(
                  create: (context) {
                    debugPrint(
                        '[main.dart] Creating AuthBloc in MultiBlocProvider');
                    try {
                      if (serviceLocator.isRegistered<AuthService>()) {
                        final authBloc = AuthBloc(
                          authService: serviceLocator<AuthService>(),
                          onboardingService:
                              serviceLocator<OnboardingService>(),
                        )..add(CheckAuthStatusEvent());
                        debugPrint(
                            '[main.dart] AuthBloc registered in service locator');
                        return authBloc;
                      } else {
                        debugPrint(
                            '[main.dart] WARNING: AuthService not registered, using empty AuthBloc');
                        final authBloc = AuthBloc(
                          authService: AuthService(),
                          onboardingService: OnboardingService(),
                        );
                        if (!serviceLocator.isRegistered<AuthBloc>()) {
                          serviceLocator.registerSingleton<AuthBloc>(authBloc);
                          logger.debug(
                              '[AiTherapistApp] Minimal AuthBloc registered in service locator');
                        }
                        return authBloc;
                      }
                    } catch (e) {
                      debugPrint('[main.dart] Error creating AuthBloc: $e');
                      final authBloc = AuthBloc(
                        authService: AuthService(),
                        onboardingService: OnboardingService(),
                      );
                      if (!serviceLocator.isRegistered<AuthBloc>()) {
                        serviceLocator.registerSingleton<AuthBloc>(authBloc);
                        logger.debug(
                            '[AiTherapistApp] Fallback AuthBloc registered in service locator');
                      }
                      return authBloc;
                    }
                  },
                ),
              ],
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
    debugPrint('[main.dart] AiTherapistApp dispose');
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
        debugPrint('Error caught by ErrorBoundary:');
        debugPrint(errorDetails.exception.toString());
        debugPrint(errorDetails.stack?.toString());
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

// LEGACY: This method was replaced by the new priority-based initialization
// Keeping for reference but should not be called

// New: Heavy service initializations and notification permissions
Future<void> initializeHeavyServices() async {
  logger.info('[Main] Initializing heavy services in background...');
  try {
    // Table checks and health/repair
    try {
      final appDatabase = serviceLocator<AppDatabase>();
      if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
        logger.debug('[Main] Checking database health...');
        final dbManager = serviceLocator<DatabaseOperationManager>();
        final isHealthy =
            await dbManager.checkAndRepairDatabaseHealth(appDatabase);
        if (isHealthy) {
          logger.info('[Main] Database health check passed ✅');
        } else {
          logger
              .warning('[Main] Database health check failed, attempted repair');
        }
      }
      // Table existence checks
      logger.debug('[Main] Verifying database tables...');
      final databaseProvider = serviceLocator<DatabaseProvider>();
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
      logger.error('[Main] ERROR in deferred database checks', error: e);
    }

    // Initialize Firebase services only (ConfigService/ApiClient handled elsewhere now)
    try {
      await _initializeFirebaseServices();
    } catch (e) {
      logger.error('[Main] ERROR initializing Firebase services', error: e);
    }

    // Request notification permissions (deferred)
    try {
      await _requestNotificationPermissions();
    } catch (e) {
      logger.error('[Main] ERROR requesting notification permissions',
          error: e);
    }

    logger.info('[Main] Heavy services initialized in background.');
  } catch (e) {
    logger.error('[Main] ERROR in initializeHeavyServices', error: e);
  }
}

// 🔧 PATCH 2: Add this new method for critical audio services
Future<void> _initializeCriticalAudioServices() async {
  logger.info(
      '[Main] Initializing CRITICAL audio services (no database dependency)');

  try {
    // VoiceService first - completely independent
    if (serviceLocator.isRegistered<VoiceService>()) {
      final voiceService = serviceLocator<VoiceService>();
      await voiceService.initialize();
      logger.info('[Main] ✅ VoiceService initialized (CRITICAL)');
    }

    // AudioGenerator second - also independent
    if (serviceLocator.isRegistered<AudioGenerator>()) {
      final audioGenerator = serviceLocator<AudioGenerator>();
      await audioGenerator.initialize();
      logger.info('[Main] ✅ AudioGenerator initialized (CRITICAL)');
    }

    // Ensure API client is ready for immediate TTS requests
    if (serviceLocator.isRegistered<ApiClient>()) {
      // ApiClient should be ready from service locator setup
      logger.info('[Main] ✅ ApiClient ready for TTS requests (CRITICAL)');
    }

    logger.info(
        '[Main] 🎵 All critical audio services ready - TTS should work immediately');
  } catch (e) {
    logger.error('[Main] 🚨 CRITICAL: Audio service initialization failed',
        error: e);
    throw e; // Re-throw so we know audio won't work
  }
}

// 🔧 PATCH 3: Replace initializeHeavyServices with this
Future<void> _initializeBackgroundServices() async {
  logger.info('[Main] Starting background service initialization...');

  try {
    // Background database operations (don't block TTS)
    unawaited(_runDatabaseOperationsInBackground());

    // Initialize remaining services that aren't critical for TTS
    await _initializeNonCriticalServices();

    // Firebase services
    await _initializeFirebaseServices();

    // Notification permissions
    await _requestNotificationPermissions();

    logger.info('[Main] Background service initialization complete');
  } catch (e) {
    logger.error(
        '[Main] Background service initialization error (non-critical)',
        error: e);
  }
}

// 🔧 PATCH 4: Move heavy database work to true background
Future<void> _runDatabaseOperationsInBackground() async {
  try {
    logger.debug('[Main] Running database operations in background...');

    // Small delay to let app settle
    await Future.delayed(Duration(seconds: 2));

    if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
      final dbManager = serviceLocator<DatabaseOperationManager>();
      final appDatabase = serviceLocator<AppDatabase>();

      await dbManager.checkAndRepairDatabaseHealth(appDatabase);
      logger.debug('[Main] Background: Database health check complete');

      // Delay optimization even more to not interfere with user interaction
      await Future.delayed(Duration(seconds: 10));
      await dbManager.optimizeDatabase(appDatabase);
      logger.debug('[Main] Background: Database optimization complete');
    }
  } catch (e) {
    logger.error('[Main] Background database operations failed (non-critical)',
        error: e);
  }
}

// 🔧 PATCH 5: Initialize services that can wait
Future<void> _initializeNonCriticalServices() async {
  try {
    // These services can be initialized after TTS is working
    if (serviceLocator.isRegistered<MemoryService>()) {
      final memoryService = serviceLocator<MemoryService>();
      await memoryService.init();
      logger.debug('[Main] MemoryService initialized (background)');
    }

    if (serviceLocator.isRegistered<MemoryManager>()) {
      final memoryManager = serviceLocator<MemoryManager>();
      await memoryManager.init();
      logger.debug('[Main] MemoryManager initialized (background)');
    }

    if (serviceLocator.isRegistered<ConversationFlowManager>()) {
      final conversationFlowManager = serviceLocator<ConversationFlowManager>();
      await conversationFlowManager.init();
      logger.debug('[Main] ConversationFlowManager initialized (background)');
    }

    if (serviceLocator.isRegistered<TherapyService>()) {
      final therapyService = serviceLocator<TherapyService>();
      await therapyService.init();
      logger.debug('[Main] TherapyService initialized (background)');
    }
  } catch (e) {
    logger.warning('[Main] Some non-critical services failed to initialize',
        error: e);
  }
}

// 🔧 CRITICAL FIX: Priority-based service initialization with safety checks
Future<void> initializeCriticalAudioServices() async {
  logger.info('[Main] 🎵 Initializing CRITICAL audio services...');

  try {
    // Add a small delay to ensure UI is fully started
    await Future.delayed(Duration(milliseconds: 100));

    // 1. VoiceService FIRST - no database dependencies
    if (serviceLocator.isRegistered<VoiceService>()) {
      try {
        final voiceService = serviceLocator<VoiceService>();
        await voiceService.initialize().timeout(Duration(seconds: 10));
        logger.info('[Main] ✅ VoiceService initialized (CRITICAL)');
      } catch (e) {
        logger.error('[Main] ❌ VoiceService failed', error: e);
        // Continue with other services
      }
    } else {
      logger.warning('[Main] ⚠️ VoiceService not registered');
    }

    // 2. AudioGenerator SECOND - no database dependencies
    if (serviceLocator.isRegistered<AudioGenerator>()) {
      try {
        final audioGenerator = serviceLocator<AudioGenerator>();
        await audioGenerator.initialize().timeout(Duration(seconds: 10));
        logger.info('[Main] ✅ AudioGenerator initialized (CRITICAL)');
      } catch (e) {
        logger.error('[Main] ❌ AudioGenerator failed', error: e);
        // Continue with other services
      }
    } else {
      logger.warning('[Main] ⚠️ AudioGenerator not registered');
    }

    // 3. ApiClient for TTS - no database needed
    if (serviceLocator.isRegistered<ApiClient>()) {
      logger.info('[Main] ✅ ApiClient ready for TTS (CRITICAL)');
    } else {
      logger.warning('[Main] ⚠️ ApiClient not registered');
    }

    logger.info('[Main] 🎵 CRITICAL audio services initialization complete');
  } catch (e) {
    logger.error('[Main] 🚨 CRITICAL: Audio services failed', error: e);
    // Don't throw - let app continue
  }
}

// 🔧 CRITICAL FIX: Separate background initialization without delays
Future<void> initializeNonCriticalServicesInBackground() async {
  logger.info('[Main] Starting background initialization...');

  // Run database operations completely in background
  unawaited(_backgroundDatabaseOperations());

  // Initialize remaining services that TTS doesn't need
  try {
    await _initializeNonCriticalServices();
  } catch (e) {
    logger.error('[Main] Non-critical services failed (continuing)', error: e);
  }
}

Future<void> _backgroundDatabaseOperations() async {
  try {
    logger.debug('[Main] Running database operations in background...');

    // All heavy database operations - don't block TTS
    if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
      final dbManager = serviceLocator<DatabaseOperationManager>();
      final appDatabase = serviceLocator<AppDatabase>();

      await dbManager.checkAndRepairDatabaseHealth(appDatabase);
      logger.debug('[Main] Background: Database health check complete');

      // Wait before optimization to avoid competing with user actions
      await Future.delayed(Duration(seconds: 5));
      await dbManager.optimizeDatabase(appDatabase);
      logger.debug('[Main] Background: Database optimization complete');
    }
  } catch (e) {
    logger.error('[Main] Background database operations failed', error: e);
  }
}

// 🔧 CRITICAL FIX: TTS health check
Future<bool> checkTTSHealth() async {
  try {
    if (!serviceLocator.isRegistered<VoiceService>()) {
      logger.error('[TTS Health] VoiceService not registered');
      return false;
    }

    if (!serviceLocator.isRegistered<AudioGenerator>()) {
      logger.error('[TTS Health] AudioGenerator not registered');
      return false;
    }

    if (!serviceLocator.isRegistered<ApiClient>()) {
      logger.error('[TTS Health] ApiClient not registered');
      return false;
    }

    logger.info('[TTS Health] ✅ All TTS services registered and ready');
    return true;
  } catch (e) {
    logger.error('[TTS Health] Health check failed', error: e);
    return false;
  }
}
