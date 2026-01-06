import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/firebase_options.dart';

bool _firebaseInitialized = false;
FirebaseApp? _app;
Future<FirebaseApp?>? _initializationFuture;

Future<FirebaseApp?> ensureFirebaseInitialized() async {
  if (_firebaseInitialized && _app != null) {
    return _app;
  }

  _initializationFuture ??= _initializeFirebaseApp();
  final FirebaseApp? app = await _initializationFuture;
  if (app != null) {
    _firebaseInitialized = true;
    _app = app;
  }
  if (_firebaseInitialized) {
    _initializationFuture = null;
  }
  return app;
}

Future<FirebaseApp?> _initializeFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) {
    _firebaseInitialized = true;
    _app = Firebase.app();
    debugPrint('Firebase is already initialized: ${_app!.name}');
    return _app;
  }

  debugPrint('Firebase is not yet initialized, attempting to initialize...');

  try {
    // RACE CONDITION FIX: Check again right before init in case another path
    // initialized Firebase during the async gap (e.g., FlutterFire auto-init,
    // background message handler, or plugin initialization)
    if (Firebase.apps.isNotEmpty) {
      _app = Firebase.app();
      _firebaseInitialized = true;
      debugPrint('Firebase initialized by another path during async gap: ${_app!.name}');
      return _app;
    }

    _app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseInitialized = true;
    debugPrint('Firebase initialized successfully: ${_app!.name}');
    debugPrint(
        'Firebase App Check is INTENTIONALLY DISABLED to fix auth issues');
    return _app;
  } catch (e) {
    // Handle duplicate-app error gracefully - this can still happen in rare
    // race conditions where init completes between our check and the call
    if (e.toString().contains('duplicate-app')) {
      try {
        _app = Firebase.app();
        _firebaseInitialized = true;
        debugPrint('Firebase already initialized (caught duplicate-app): ${_app!.name}');
        return _app;
      } catch (innerError) {
        debugPrint('Error getting existing Firebase app: $innerError');
      }
    } else {
      debugPrint('Error initializing Firebase: $e');
    }
    _firebaseInitialized = false;
    _initializationFuture = null;
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
