// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding, DartPluginRegistrant;
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'package:firebase_core/firebase_core.dart';
import 'package:ai_therapist_app/firebase_options.dart';
import 'package:ai_therapist_app/services/firebase_service.dart';

// This needs to be outside of any class and marked with this annotation
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you need to use other Firebase services in the background, such as Firestore,
  // make sure Firebase is initialized here if it wasn't already
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  if (kDebugMode) {
    print('Handling a background message: ${message.messageId}');
    print('Background message data: ${message.data}');
    if (message.notification != null) {
      print('Background message notification: ${message.notification!.title}');
    }
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
final String apiBaseUrl = isDebugMode 
    ? 'http://10.0.2.2:8000'    // Android emulator localhost 
    : 'https://upliftapp-cd86e.web.app'; // Updated production URL

// Global error handler for unhandled exceptions
void _handleGlobalError(Object error, StackTrace stack) {
  if (kDebugMode) {
    print('Unhandled error: $error');
    print(stack);
  }
  
  String errorMessage = 'An unexpected error occurred';
  
  // Provide more specific error messages for common errors
  if (error is SocketException) {
    errorMessage = 'Network connection error. Please check your internet connection and try again.';
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

// Initialize Firebase in the main thread, not in an isolate
Future<bool> _initializeFirebase() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Initialize Firebase Core first
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      // Request permission for notifications if needed
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      // Get token for this device
      String? token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        print('FCM Token: $token');
      }
      
      return true;
    }
    return false;
  } catch (e) {
    if (kDebugMode) {
      print('Failed to initialize Firebase: $e');
    }
    return false;
  }
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

// Initialize only the most critical services needed for app startup
Future<void> _initializeEssentialServices() async {
  // Initialize Firebase Core first - this is required
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
    
  if (defaultTargetPlatform == TargetPlatform.android) {
    // Get token for this device - defer permission requests until later
    String? token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) {
      print('FCM Token: $token');
      print('Firebase initialized successfully on Android');
    }
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
      initTasks.add(compute(_initializeServiceIsolate, ServiceInitParams('firebase')));
      
      // Initialize database asynchronously
      initTasks.add(_initializeDatabase());
      
      // Initialize other services in parallel
      initTasks.add(compute(_initializeServiceIsolate, ServiceInitParams('userProfile')));
      initTasks.add(compute(_initializeServiceIsolate, ServiceInitParams('therapy')));
      
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
                'assets/images/app_logo.png',
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
  const FallbackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uplift - Fallback Mode',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Uplift - Fallback Mode'),
          backgroundColor: Colors.blue.shade100,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                'App Initialization Failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'The app could not initialize properly. This may be due to missing dependencies or configuration issues.',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  main(); // Try to restart the app
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => AuthBloc(
            authService: serviceLocator<AuthService>(),
          )..add(CheckAuthStatusEvent()),
        ),
        // Add other Bloc providers here
      ],
      child: MaterialApp.router(
        title: 'Uplift',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        routerConfig: AppRouter.router,
      ),
    );
  }
}