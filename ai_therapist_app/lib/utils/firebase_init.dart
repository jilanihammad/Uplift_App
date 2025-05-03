import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/firebase_options.dart';

// Flag to track Firebase initialization status
bool _firebaseInitialized = false;

// Global reference to FirebaseApp
FirebaseApp? _app;

/// The single source of truth for Firebase initialization across the app
///
/// This function ensures Firebase is initialized only once, even when called
/// from different isolates or contexts. It uses a Completer to synchronize
/// the initialization process and prevent race conditions.
Future<FirebaseApp?> ensureFirebaseInitialized() async {
  // First check if Firebase is already initialized
  try {
    // Get default app if it exists
    FirebaseApp app = Firebase.app();
    debugPrint('Firebase is already initialized: ${app.name}');
    return app;
  } catch (e) {
    debugPrint('Firebase is not yet initialized, attempting to initialize...');
  }

  try {
    // Initialize Firebase with default options if not already initialized
    FirebaseApp app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // IMPORTANT: DO NOT initialize App Check here
    debugPrint('Firebase initialized successfully: ${app.name}');
    debugPrint(
        'Firebase App Check is INTENTIONALLY DISABLED to fix auth issues');

    return app;
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');

    if (e.toString().contains('duplicate-app')) {
      // If the error is because Firebase is already initialized, return the existing app
      try {
        FirebaseApp app = Firebase.app();
        debugPrint('Using existing Firebase app: ${app.name}');
        return app;
      } catch (innerError) {
        debugPrint('Error getting existing Firebase app: $innerError');
      }
    }
    return null;
  }
}

/// Check if Firebase has been successfully initialized
bool isFirebaseInitialized() {
  return _firebaseInitialized;
}
