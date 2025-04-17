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
          if (kDebugMode) print('FirebaseService: Auth initialized and working');
        } catch (authError) {
          if (kDebugMode) print('FirebaseService: Auth available but operation restricted: $authError');
          _authAvailable = false;
        }
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Auth initialization failed: $e');
        _authAvailable = false;
      }
      
      try {
        if (kDebugMode) {
          print('FirebaseService: Skipping Firestore initialization to avoid errors');
        }
        
        // Set Firestore as unavailable - don't even try to initialize it
        _firestoreAvailable = false;
        
        /*
        _firestore = FirebaseFirestore.instance;
        
        // Set longer timeouts for Firestore operations
        _firestore?.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          sslEnabled: true,
        );
        
        // Test Firestore with exponential backoff retry
        bool firestoreConnected = false;
        int retryCount = 0;
        const maxRetries = 3;
        
        while (!firestoreConnected && retryCount < maxRetries) {
          try {
            if (kDebugMode) print('FirebaseService: Firestore connection attempt ${retryCount + 1}');
            
            // First check if we're dealing with a Datastore Mode project
            try {
              final testRef = _firestore?.collection('_test');
              
              // Try to use a transaction which will fail quickly for Datastore Mode
              await _firestore?.runTransaction((transaction) async {
                // This will fail immediately with FAILED_PRECONDITION if Datastore Mode
                return null;
              }).timeout(Duration(seconds: 5 + (retryCount * 3)));
              
              // If we get here, it's not Datastore Mode
              firestoreConnected = true;
              _firestoreAvailable = true;
              if (kDebugMode) print('FirebaseService: Firestore initialized and working');
            } catch (e) {
              // Check if it's a Datastore Mode error
              final errorString = e.toString();
              if (errorString.contains('Datastore Mode') || 
                  errorString.contains('FAILED_PRECONDITION')) {
                if (kDebugMode) {
                  print('FirebaseService: Project is using Firestore in Datastore Mode.');
                  print('This app requires Firestore Native Mode. Please check Firebase Console settings.');
                }
                // Don't retry for Datastore Mode errors
                retryCount = maxRetries;
                _firestoreAvailable = false;
                break;
              } else {
                // Normal connection error, try again
                throw e;
              }
            }
          } catch (firestoreError) {
            retryCount++;
            if (kDebugMode) {
              print('FirebaseService: Firestore connection attempt ${retryCount} failed: $firestoreError');
            }
            
            if (retryCount < maxRetries) {
              // Exponential backoff
              final backoffDuration = Duration(milliseconds: 500 * (1 << retryCount));
              if (kDebugMode) print('FirebaseService: Retrying in ${backoffDuration.inMilliseconds}ms');
              await Future.delayed(backoffDuration);
            } else {
              if (kDebugMode) print('FirebaseService: All Firestore connection attempts failed');
              _firestoreAvailable = false;
            }
          }
        }
        */
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Firestore initialization failed: $e');
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
          if (kDebugMode) print('FirebaseService: Storage available but operation failed: $storageError');
          _storageAvailable = false;
        }
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Storage initialization failed: $e');
        _storageAvailable = false;
      }
      
      try {
        _messaging = FirebaseMessaging.instance;
        try {
          String? token = await _messaging?.getToken();
          _messagingAvailable = token != null;
          if (kDebugMode) print('FirebaseService: Messaging initialized and token obtained');
        } catch (messagingError) {
          if (kDebugMode) print('FirebaseService: Messaging available but operation failed: $messagingError');
          _messagingAvailable = false;
        }
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Messaging initialization failed: $e');
        _messagingAvailable = false;
      }
      
      try {
        _analytics = FirebaseAnalytics.instance;
        _analyticsAvailable = true;
        if (kDebugMode) print('FirebaseService: Analytics initialized');
      } catch (e) {
        if (kDebugMode) print('FirebaseService: Analytics initialization failed: $e');
        _analyticsAvailable = false;
      }
      
      // Consider Firebase initialized if at least one service is working
      _initialized = _authAvailable || _firestoreAvailable || _storageAvailable || _messagingAvailable || _analyticsAvailable;
      
      if (kDebugMode) {
        print('FirebaseService initialized with status:');
        print('- Auth: ${_authAvailable ? 'Available' : 'Unavailable'}');
        print('- Firestore: ${_firestoreAvailable ? 'Available' : 'Unavailable'}');
        print('- Storage: ${_storageAvailable ? 'Available' : 'Unavailable'}');
        print('- Messaging: ${_messagingAvailable ? 'Available' : 'Unavailable'}');
        print('- Analytics: ${_analyticsAvailable ? 'Available' : 'Unavailable'}');
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
    }
    
    // Skip if messaging is not available
    if (!_messagingAvailable) {
      if (kDebugMode) {
        print('Skipping messaging initialization as it is unavailable');
      }
      return;
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
        
        // Store the token in Firestore if the user is logged in and Firestore is available
        if (_firestoreAvailable && _authAvailable) {
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

  // Try to reconnect to Firebase services
  Future<void> tryReconnect() async {
    if (kDebugMode) {
      print('Attempting to reconnect to Firebase services...');
    }
    await init();
  }

  // Log events to Firebase Analytics
  Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
  }) async {
    if (!_analyticsAvailable) return;
    
    try {
      // Convert Map<String, dynamic>? to Map<String, Object>? by removing any null values
      final Map<String, Object>? nonNullParams = parameters?.map(
        (key, value) => MapEntry(key, value as Object)
      );
      
      await _analytics?.logEvent(name: name, parameters: nonNullParams);
    } catch (e) {
      if (kDebugMode) {
        print('Error logging event: $e');
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