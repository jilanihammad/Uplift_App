import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  // Firebase instances - initialized lazily
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseStorage? _storage;
  FirebaseMessaging? _messaging;
  FirebaseAnalytics? _analytics;
  
  bool _initialized = false;

  // Getters with null safety
  FirebaseAuth? get auth => _auth;
  FirebaseFirestore? get firestore => _firestore;
  FirebaseStorage? get storage => _storage;
  FirebaseMessaging? get messaging => _messaging;
  FirebaseAnalytics? get analytics => _analytics;
  
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
        if (kDebugMode) print('FirebaseService: Auth initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Auth initialization failed: $e');
      }
      
      try {
        _firestore = FirebaseFirestore.instance;
        if (kDebugMode) print('FirebaseService: Firestore initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Firestore initialization failed: $e');
      }
      
      try {
        _storage = FirebaseStorage.instance;
        if (kDebugMode) print('FirebaseService: Storage initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Storage initialization failed: $e');
      }
      
      try {
        _messaging = FirebaseMessaging.instance;
        if (kDebugMode) print('FirebaseService: Messaging initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Messaging initialization failed: $e');
      }
      
      try {
        _analytics = FirebaseAnalytics.instance;
        if (kDebugMode) print('FirebaseService: Analytics initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Analytics initialization failed: $e');
      }
      
      _initialized = true;
      
      if (kDebugMode) {
        print('FirebaseService initialized successfully');
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
    if (!_initialized) {
      await init();
      if (!_initialized) return; // If initialization failed, don't proceed
    }
    
    try {
      // Request permission for notifications
      final settings = await _messaging?.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings?.authorizationStatus == AuthorizationStatus.authorized) {
        // Get FCM token
        String? token = await _messaging?.getToken();
        
        // Store the token in Firestore if the user is logged in
        User? currentUser = _auth?.currentUser;
        if (currentUser != null && token != null && _firestore != null) {
          try {
            await _firestore!
                .collection('users')
                .doc(currentUser.uid)
                .update({'fcmToken': token});
          } catch (e) {
            if (kDebugMode) {
              print('Error updating FCM token: $e');
            }
            // Token update failed, but we can continue
          }
        }

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          // Handle foreground message
          if (kDebugMode) {
            print('Got a message whilst in the foreground!');
            print('Message data: ${message.data}');

            if (message.notification != null) {
              print('Message also contained a notification: ${message.notification}');
            }
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in initMessaging: $e');
      }
      // Continue without messaging
    }
  }

  // Log events to Firebase Analytics
  Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _analytics?.logEvent(name: name, parameters: parameters);
    } catch (e) {
      if (kDebugMode) {
        print('Error logging event: $e');
      }
    }
  }

  // Get user document reference
  DocumentReference? getUserDocument(String userId) {
    try {
      return _firestore?.collection('users').doc(userId);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user document: $e');
      }
      return null;
    }
  }

  // Upload file to Firebase Storage
  Future<String?> uploadFile(String path, dynamic file) async {
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