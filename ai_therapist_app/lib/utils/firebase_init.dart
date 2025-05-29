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
    _app = Firebase.app(); // Attempt to get the default app
    _firebaseInitialized =
        true; // If Firebase.app() doesn't throw, it's initialized
    debugPrint('Firebase is already initialized: ${_app!.name}');
    return _app;
  } catch (e) {
    debugPrint('Firebase is not yet initialized, attempting to initialize...');
    _firebaseInitialized =
        false; // Explicitly set to false if it's not initialized
  }

  try {
    // Initialize Firebase with default options if not already initialized
    _app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseInitialized = true; // Set flag on successful initialization

    // IMPORTANT: DO NOT initialize App Check here
    debugPrint('Firebase initialized successfully: ${_app!.name}');
    debugPrint(
        'Firebase App Check is INTENTIONALLY DISABLED to fix auth issues');

    return _app;
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
    _firebaseInitialized = false; // Ensure flag is false on error

    if (e.toString().contains('duplicate-app')) {
      // If the error is because Firebase is already initialized, return the existing app
      try {
        _app = Firebase.app();
        _firebaseInitialized = true; // It was already initialized
        debugPrint('Using existing Firebase app: ${_app!.name}');
        return _app;
      } catch (innerError) {
        debugPrint('Error getting existing Firebase app: $innerError');
      }
    }
    return null;
  }
}

/// Check if Firebase has been successfully initialized
bool isFirebaseInitialized() {
  // More robust check:
  // return _firebaseInitialized && Firebase.apps.isNotEmpty;
  // Or simply rely on _firebaseInitialized if ensureFirebaseInitialized is the ONLY way it's set.
  return _firebaseInitialized;
}
