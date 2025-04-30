import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/firebase_options.dart';

// Completer to ensure Firebase initialization happens only once
final Completer<FirebaseApp?> _firebaseInitCompleter =
    Completer<FirebaseApp?>();

// Track Firebase initialization state
bool _firebaseInitialized = false;

// Global reference to FirebaseApp
FirebaseApp? _app;

/// The single source of truth for Firebase initialization across the app
///
/// This function ensures Firebase is initialized only once, even when called
/// from different isolates or contexts. It uses a Completer to synchronize
/// the initialization process and prevent race conditions.
Future<FirebaseApp?> ensureFirebaseInitialized() async {
  // Check if the initialization process has already started
  if (!_firebaseInitCompleter.isCompleted) {
    debugPrint('[Firebase] Starting Firebase initialization');
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
      _firebaseInitCompleter.complete(_app);
    } catch (e) {
      // Special handling for duplicate app error
      if (e.toString().contains('duplicate-app')) {
        debugPrint(
            '[Firebase] Caught duplicate app error, trying to get existing instance');
        try {
          _app = Firebase.app();
          _firebaseInitialized = true;
          _firebaseInitCompleter.complete(_app);
        } catch (innerError) {
          debugPrint(
              '[Firebase] Failed to get existing app after error: $innerError');
          _firebaseInitCompleter.completeError(innerError);
        }
      } else {
        debugPrint('[Firebase] Error during Firebase initialization: $e');
        _firebaseInitCompleter.completeError(e);
      }
    }
  } else {
    debugPrint('[Firebase] Waiting for existing Firebase initialization');
  }

  // Wait for initialization to complete and return the result
  try {
    return await _firebaseInitCompleter.future;
  } catch (e) {
    debugPrint('[Firebase] Error getting Firebase app from completer: $e');
    return null;
  }
}

/// Check if Firebase has been successfully initialized
bool isFirebaseInitialized() {
  return _firebaseInitialized;
}
