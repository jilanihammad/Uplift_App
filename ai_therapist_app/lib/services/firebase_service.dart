import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class FirebaseService {
  // Firebase instances - initialized lazily
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseStorage? _storage;
  FirebaseMessaging? _messaging;
  FirebaseAnalytics? _analytics;

  bool _initialized = false;
  bool _authAvailable = false;
  bool _firestoreAvailable = false;
  bool _storageAvailable = false;
  bool _messagingAvailable = false;
  bool _analyticsAvailable = false;

  // Getters with null safety
  FirebaseAuth? get auth => _authAvailable ? _auth : null;
  FirebaseFirestore? get firestore => _firestoreAvailable ? _firestore : null;
  FirebaseStorage? get storage => _storageAvailable ? _storage : null;
  FirebaseMessaging? get messaging => _messagingAvailable ? _messaging : null;
  FirebaseAnalytics? get analytics => _analyticsAvailable ? _analytics : null;

  // Check if Firebase is initialized
  bool get isInitialized => _initialized;

  // Initialize Firebase services safely
  Future<void> init() async {
    try {
      if (kDebugMode) {
        print('FirebaseService: Starting initialization');
      }

      // Try initializing each service separately with detailed logging
      try {
        _auth = FirebaseAuth.instance;
        // Test auth with a quick anonymous auth attempt
        try {
          await _auth?.signInAnonymously();
          _authAvailable = true;
          if (kDebugMode)
            print('FirebaseService: Auth initialized and working');
        } catch (authError) {
          if (kDebugMode)
            print(
                'FirebaseService: Auth available but operation restricted: $authError');
          _authAvailable = false;
        }
      } catch (e) {
        if (kDebugMode)
          print('FirebaseService: Auth initialization failed: $e');
        _authAvailable = false;
      }

      try {
        if (kDebugMode) {
          print('FirebaseService: Initializing Firestore');
        }

        // Initialize Firestore with custom database ID
        _firestore = FirebaseFirestore.instanceFor(
          app: FirebaseFirestore.instance.app,
          databaseId: 'upliftdb',
        );
        _firestoreAvailable = true;

        // Set longer timeouts for Firestore operations if needed
        _firestore?.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          sslEnabled: true,
        );

        if (kDebugMode)
          print(
              'FirebaseService: Firestore initialized with database: upliftdb');
      } catch (e) {
        if (kDebugMode)
          print('FirebaseService: Firestore initialization failed: $e');
        _firestoreAvailable = false;
      }

      try {
        _storage = FirebaseStorage.instance;
        try {
          // Just check if we can get a reference
          _storage?.ref().child('test');
          _storageAvailable = true;
          if (kDebugMode) print('FirebaseService: Storage initialized');
        } catch (storageError) {
          if (kDebugMode)
            print(
                'FirebaseService: Storage available but operation failed: $storageError');
          _storageAvailable = false;
        }
      } catch (e) {
        if (kDebugMode)
          print('FirebaseService: Storage initialization failed: $e');
        _storageAvailable = false;
      }

      try {
        _messaging = FirebaseMessaging.instance;
        try {
          String? token = await _messaging?.getToken();
          _messagingAvailable = token != null;
          if (kDebugMode)
            print('FirebaseService: Messaging initialized and token obtained');
        } catch (messagingError) {
          if (kDebugMode)
            print(
                'FirebaseService: Messaging available but operation failed: $messagingError');
          _messagingAvailable = false;
        }
      } catch (e) {
        if (kDebugMode)
          print('FirebaseService: Messaging initialization failed: $e');
        _messagingAvailable = false;
      }

      try {
        _analytics = FirebaseAnalytics.instance;
        _analyticsAvailable = true;
        if (kDebugMode) print('FirebaseService: Analytics initialized');
      } catch (e) {
        if (kDebugMode)
          print('FirebaseService: Analytics initialization failed: $e');
        _analyticsAvailable = false;
      }

      // Consider Firebase initialized if at least one service is working
      _initialized = _authAvailable ||
          _firestoreAvailable ||
          _storageAvailable ||
          _messagingAvailable ||
          _analyticsAvailable;

      if (kDebugMode) {
        print('FirebaseService initialized with status:');
        print('- Auth: ${_authAvailable ? 'Available' : 'Unavailable'}');
        print(
            '- Firestore: ${_firestoreAvailable ? 'Available' : 'Unavailable'}');
        print('- Storage: ${_storageAvailable ? 'Available' : 'Unavailable'}');
        print(
            '- Messaging: ${_messagingAvailable ? 'Available' : 'Unavailable'}');
        print(
            '- Analytics: ${_analyticsAvailable ? 'Available' : 'Unavailable'}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing FirebaseService: $e');
        print('Stack trace: ${StackTrace.current}');
      }
      _initialized = false;
    }
  }

  // Initialize Firebase messaging
  Future<void> initMessaging() async {
    debugPrint('FirebaseService: Entering initMessaging');

    // Skip entire process if any condition isn't met
    if (!_initialized || !_messagingAvailable || _messaging == null) {
      debugPrint(
          'FirebaseService: Skipping messaging initialization (not ready)');
      return;
    }

    try {
      debugPrint('FirebaseService: Requesting notification permissions');

      // Simple permission request - no fancy error handling to avoid type issues
      try {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        debugPrint(
            'FirebaseService: Permission status: ${settings.authorizationStatus}');

        // Only continue if authorized
        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          debugPrint('FirebaseService: Not authorized for notifications');
          return;
        }
      } catch (e) {
        debugPrint('FirebaseService: Error requesting permissions: $e');
        return;
      }

      // Token operations
      try {
        final token = await _messaging!.getToken();
        if (token != null) {
          debugPrint('FirebaseService: Got FCM token');
        } else {
          debugPrint('FirebaseService: Got null FCM token');
        }
      } catch (e) {
        debugPrint('FirebaseService: Error getting FCM token: $e');
      }

      // Setup listeners with minimal code
      try {
        FirebaseMessaging.onMessage.listen(
          (message) =>
              debugPrint('FirebaseService: Received foreground message'),
          onError: (e) =>
              debugPrint('FirebaseService: Message listener error: $e'),
        );
      } catch (e) {
        debugPrint('FirebaseService: Error setting up message listener: $e');
      }
    } catch (e) {
      debugPrint('FirebaseService: Error in initMessaging: $e');
    }

    debugPrint('FirebaseService: Completed initMessaging');
  }

  // Try to reconnect to Firebase services
  Future<void> tryReconnect() async {
    if (kDebugMode) {
      print('Attempting to reconnect to Firebase services...');
    }
    await init();
  }

  // Log events to Firebase Analytics
  Future<void> logEvent(String name, Map<String, dynamic> parameters) async {
    if (!_initialized || !_analyticsAvailable) {
      if (kDebugMode) {
        print(
            'Skipping analytics event logging: Firebase not ready or analytics unavailable.');
      }
      return;
    }

    try {
      // Filter out null values from parameters and cast to required type
      final Map<String, Object> nonNullParams = Map.fromEntries(parameters
          .entries
          .where((entry) => entry.value != null)
          .map((entry) => MapEntry(entry.key, entry.value as Object)));

      await _analytics?.logEvent(name: name, parameters: nonNullParams);
    } catch (e) {
      if (kDebugMode) {
        print('Error logging analytics event: $e');
      }
    }
  }

  // Get user document reference
  DocumentReference? getUserDocument(String userId) {
    if (!_firestoreAvailable) return null;

    try {
      return _firestore?.collection('users').doc(userId);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user document: $e');
      }
      return null;
    }
  }

  // Get storage reference
  Reference? getStorageRef() {
    if (!_storageAvailable) return null;

    try {
      return _storage?.ref();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting storage reference: $e');
      }
      return null;
    }
  }

  // Upload file to Firebase Storage
  Future<String?> uploadFile(String path, dynamic file) async {
    if (!_storageAvailable) return null;

    try {
      if (_storage == null) return null;

      final ref = _storage!.ref().child(path);
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading file: $e');
      }
      return null;
    }
  }
}
