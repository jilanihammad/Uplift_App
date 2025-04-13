// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
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
  
  // Initialize Firebase only for Android
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (kDebugMode) {
        print('Firebase initialized successfully on Android');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize Firebase: $e');
        print('Stack trace: ${StackTrace.current}');
      }
      // Continue without Firebase functionality
    }
  } else {
    if (kDebugMode) {
      print('Skipping Firebase initialization for non-Android platform');
    }
  }
  
  // Set up custom bloc observer for better error handling
  Bloc.observer = SimpleBlocObserver();
  
  try {
    // Initialize dependencies
    await setupServiceLocator();
    
    // Initialize Firebase service only for Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (serviceLocator.isRegistered<FirebaseService>()) {
          await serviceLocator<FirebaseService>().init();
          await serviceLocator<FirebaseService>().initMessaging();
        } else {
          if (kDebugMode) {
            print('FirebaseService is not registered');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Failed to initialize Firebase messaging: $e');
          print('Stack trace: ${StackTrace.current}');
        }
        // Continue without Firebase messaging
      }
    }
    
    // Initialize services that require async initialization
    try {
      if (serviceLocator.isRegistered<UserProfileService>()) {
        await serviceLocator<UserProfileService>().init();
      }
      
      if (serviceLocator.isRegistered<OnboardingService>()) {
        await serviceLocator<OnboardingService>().init();
      }
      
      if (serviceLocator.isRegistered<TherapyService>()) {
        await serviceLocator<TherapyService>().init();
      }
      
      // Initialize database
      final appDatabase = AppDatabase();
      await appDatabase.database;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize a service: $e');
      }
    }
    
    runApp(const MyApp());
  } catch (e) {
    if (kDebugMode) {
      print('Error during app initialization: $e');
    }
    // Fallback to a simple app if initialization fails
    runApp(const FallbackApp());
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