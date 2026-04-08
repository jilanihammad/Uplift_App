import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:async';
import 'package:ai_therapist_app/utils/firebase_init.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/utils/logging_service.dart';
class FirebaseService {
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
  late final ConfigService _configService;
  FirebaseAuth? get auth => _authAvailable ? _auth : null;
  FirebaseFirestore? get firestore => _firestoreAvailable ? _firestore : null;
  FirebaseStorage? get storage => _storageAvailable ? _storage : null;
  FirebaseMessaging? get messaging => _messagingAvailable ? _messaging : null;
  FirebaseAnalytics? get analytics => _analyticsAvailable ? _analytics : null;
  bool get isInitialized => _initialized;
  FirebaseService() {
    try {
      _configService = DependencyContainer().configService;
    } catch (e) {
      logger.warning(
        'ConfigService not available, using defaults',
        tag: 'Firebase',
      );
    }
  }
  Future<void> init() async {
    try {
      logger.info('Starting initialization', tag: 'Firebase');
      final firebaseApp = await ensureFirebaseInitialized();
      if (firebaseApp == null) {
        logger.error('Firebase Core initialization failed', tag: 'Firebase');
        _initialized = false;
        return;
      }
      logger.info(
        'Firebase Core initialized: ${firebaseApp.name}',
        tag: 'Firebase',
      );
      // IMPORTANT: App Check is completely disabled in this version
      logger.info(
        'IMPORTANT: Firebase App Check is DISABLED to fix authentication issues',
        tag: 'Firebase',
      );
      try {
        _auth = FirebaseAuth.instance;
        final currentUser = _auth?.currentUser;
        _authAvailable = true;
        logger.info('Auth initialized and working', tag: 'Firebase');
      } catch (e) {
        logger.error('Auth initialization failed', error: e, tag: 'Firebase');
        _authAvailable = false;
      }
      try {
        logger.debug('Initializing Firestore', tag: 'Firebase');
        String databaseId = 'upliftdb'; // Default
        try {
          databaseId = _configService.firebaseDatabaseId;
        } catch (e) {
          logger.warning(
            'Could not get database ID from config',
            error: e,
            tag: 'Firebase',
          );
        }
        _firestore = FirebaseFirestore.instanceFor(
          app: FirebaseFirestore.instance.app,
          databaseId: databaseId,
        );
        _firestoreAvailable = true;
        _firestore?.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          sslEnabled: true,
        );
        logger.info(
          'Firestore initialized with database: $databaseId',
          tag: 'Firebase',
        );
      } catch (e) {
        logger.error(
          'Firestore initialization failed',
          error: e,
          tag: 'Firebase',
        );
        _firestoreAvailable = false;
      }
      try {
        _storage = FirebaseStorage.instance;
        try {
          _storage?.ref().child('test');
          _storageAvailable = true;
          logger.info('Storage initialized', tag: 'Firebase');
        } catch (storageError) {
          logger.warning(
            'Storage available but operation failed',
            error: storageError,
            tag: 'Firebase',
          );
          _storageAvailable = false;
        }
      } catch (e) {
        logger.error(
          'Storage initialization failed',
          error: e,
          tag: 'Firebase',
        );
        _storageAvailable = false;
      }
      try {
        _messaging = FirebaseMessaging.instance;
        try {
          String? token = await _messaging?.getToken();
          _messagingAvailable = token != null;
          logger.info(
            'Messaging initialized and token obtained',
            tag: 'Firebase',
          );
        } catch (messagingError) {
          logger.warning(
            'Messaging available but operation failed',
            error: messagingError,
            tag: 'Firebase',
          );
          _messagingAvailable = false;
        }
      } catch (e) {
        logger.error(
          'Messaging initialization failed',
          error: e,
          tag: 'Firebase',
        );
        _messagingAvailable = false;
      }
      try {
        _analytics = FirebaseAnalytics.instance;
        _analyticsAvailable = true;
        logger.info('Analytics initialized', tag: 'Firebase');
      } catch (e) {
        logger.error(
          'Analytics initialization failed',
          error: e,
          tag: 'Firebase',
        );
        _analyticsAvailable = false;
      }
      _initialized = _authAvailable ||
          _firestoreAvailable ||
          _storageAvailable ||
          _messagingAvailable ||
          _analyticsAvailable;
      logger.info('Firebase initialized with status:', tag: 'Firebase');
      logger.info(
        '- Auth: ${_authAvailable ? 'Available' : 'Unavailable'}',
        tag: 'Firebase',
      );
      logger.info(
        '- Firestore: ${_firestoreAvailable ? 'Available' : 'Unavailable'}',
        tag: 'Firebase',
      );
      logger.info(
        '- Storage: ${_storageAvailable ? 'Available' : 'Unavailable'}',
        tag: 'Firebase',
      );
      logger.info(
        '- Messaging: ${_messagingAvailable ? 'Available' : 'Unavailable'}',
        tag: 'Firebase',
      );
      logger.info(
        '- Analytics: ${_analyticsAvailable ? 'Available' : 'Unavailable'}',
        tag: 'Firebase',
      );
    } catch (e, stackTrace) {
      logger.error(
        'Error initializing FirebaseService',
        error: e,
        stackTrace: stackTrace,
        tag: 'Firebase',
      );
      _initialized = false;
    }
  }
  Future<void> initMessaging() async {
    logger.debug('Entering initMessaging', tag: 'Firebase');
    if (!_initialized || !_messagingAvailable || _messaging == null) {
      logger.warning(
        'Skipping messaging initialization (not ready)',
        tag: 'Firebase',
      );
      return;
    }
    try {
      logger.debug('Requesting notification permissions', tag: 'Firebase');
      try {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        logger.debug(
          'Permission status: ${settings.authorizationStatus}',
          tag: 'Firebase',
        );
        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          logger.warning('Not authorized for notifications', tag: 'Firebase');
          return;
        }
      } catch (e) {
        logger.error('Error requesting permissions', error: e, tag: 'Firebase');
        return;
      }
      try {
        final token = await _messaging!.getToken();
        if (token != null) {
          logger.debug('Got FCM token', tag: 'Firebase');
        } else {
          logger.warning('Got null FCM token', tag: 'Firebase');
        }
      } catch (e) {
        logger.error('Error getting FCM token', error: e, tag: 'Firebase');
      }
      try {
        FirebaseMessaging.onMessage.listen(
          (message) =>
              logger.debug('Received foreground message', tag: 'Firebase'),
          onError: (e) => logger.error(
            'Message listener error',
            error: e,
            tag: 'Firebase',
          ),
        );
      } catch (e) {
        logger.error(
          'Error setting up message listener',
          error: e,
          tag: 'Firebase',
        );
      }
    } catch (e) {
      logger.error('Error in initMessaging', error: e, tag: 'Firebase');
    }
    logger.debug('Completed initMessaging', tag: 'Firebase');
  }
  Future<void> tryReconnect() async {
    logger.info(
      'Attempting to reconnect to Firebase services...',
      tag: 'Firebase',
    );
    await init();
  }
  Future<void> logEvent(String name, Map<String, dynamic> parameters) async {
    if (!_initialized || !_analyticsAvailable) {
      logger.warning(
        'Skipping analytics event logging: Firebase not ready or analytics unavailable.',
        tag: 'Firebase',
      );
      return;
    }
    try {
      final Map<String, Object> nonNullParams = Map.fromEntries(
        parameters.entries
            .where((entry) => entry.value != null)
            .map((entry) => MapEntry(entry.key, entry.value as Object)),
      );
      await _analytics?.logEvent(name: name, parameters: nonNullParams);
      logger.analytics(name, parameters: parameters, tag: 'Firebase');
    } catch (e) {
      logger.error('Error logging analytics event', error: e, tag: 'Firebase');
    }
  }
  DocumentReference? getUserDocument(String userId) {
    if (!_firestoreAvailable) return null;
    try {
      return _firestore?.collection('users').doc(userId);
    } catch (e) {
      return null;
    }
  }
  Reference? getStorageRef() {
    if (!_storageAvailable) return null;
    try {
      return _storage?.ref();
    } catch (e) {
      return null;
    }
  }
  Future<String?> uploadFile(String path, dynamic file) async {
    if (!_storageAvailable) return null;
    try {
      if (_storage == null) return null;
      final ref = _storage!.ref().child(path);
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      return null;
    }
  }
}
