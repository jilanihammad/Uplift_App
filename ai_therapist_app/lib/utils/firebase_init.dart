import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
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
    return _app;
  }
  try {
    if (Firebase.apps.isNotEmpty) {
      _app = Firebase.app();
      _firebaseInitialized = true;
      return _app;
    }
    _app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseInitialized = true;
    return _app;
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      try {
        _app = Firebase.app();
        _firebaseInitialized = true;
        return _app;
      } catch (innerError) {}
    } else {
    }
    _firebaseInitialized = false;
    _initializationFuture = null;
    return null;
  }
}
bool isFirebaseInitialized() {
  return _firebaseInitialized;
}
