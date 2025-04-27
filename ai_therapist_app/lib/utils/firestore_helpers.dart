import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/utils/error_handling.dart';

/// Helper class to verify and ensure Firestore collections
class FirestoreHelper {
  // Singleton instance
  static final FirestoreHelper _instance = FirestoreHelper._internal();
  factory FirestoreHelper() => _instance;
  FirestoreHelper._internal() {
    // Initialize Firestore with the specified database ID
    _firestore = FirebaseFirestore.instanceFor(
      app: FirebaseFirestore.instance.app,
      databaseId: 'upliftdb',
    );
  }

  // Firestore instance with custom database
  late final FirebaseFirestore _firestore;

  // Tracking verified collections
  final Set<String> _verifiedCollections = {};

  // Flag if Native mode is confirmed
  bool _isNativeModeConfirmed = false;

  /// Check if Firestore is in Native mode and required collections exist
  Future<bool> verifyFirestoreSetup(
      {List<String> requiredCollections = const []}) async {
    try {
      if (!_isNativeModeConfirmed) {
        final isNativeMode = await _checkNativeMode();
        if (!isNativeMode) {
          debugPrint('WARNING: Firestore is not in Native mode!');
          return false;
        }
        _isNativeModeConfirmed = true;
      }

      // Verify all required collections
      bool allCollectionsExist = true;
      for (final collection in requiredCollections) {
        if (!_verifiedCollections.contains(collection)) {
          final exists = await _verifyCollection(collection);
          if (exists) {
            _verifiedCollections.add(collection);
          } else {
            allCollectionsExist = false;
          }
        }
      }

      return allCollectionsExist;
    } catch (e) {
      debugPrint('Error verifying Firestore setup: $e');
      return false;
    }
  }

  /// Check if Firestore is in Native mode
  Future<bool> _checkNativeMode() async {
    try {
      // Try a very simple transaction with increased timeout - this will fail quickly in Datastore mode
      await _firestore.runTransaction((transaction) async {
        // Empty transaction just to test if Native mode is enabled
        return null;
      }).timeout(const Duration(seconds: 10)); // Increased from 5 to 10 seconds

      debugPrint('Firestore (upliftdb): Native mode confirmed! ✅');
      return true;
    } catch (e) {
      if (e.toString().contains('Datastore Mode') ||
          e.toString().contains('FAILED_PRECONDITION')) {
        debugPrint('Firestore (upliftdb): Project is using Datastore Mode ❌');
        return false;
      }

      // If there's a timeout, try a simpler test
      if (e is TimeoutException) {
        debugPrint(
            'Firestore (upliftdb): Transaction test timed out, trying simpler test...');
        try {
          // Just try to access a collection as a simpler test
          await _firestore
              .collection('_test_collection')
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 5));
          debugPrint(
              'Firestore (upliftdb): Simple collection test passed, assuming Native mode ✅');
          return true;
        } catch (innerError) {
          debugPrint(
              'Firestore (upliftdb): Simple collection test also failed: $innerError');
        }
      }

      // Other error - assume native mode but something else is wrong
      debugPrint('Firestore check error (assuming Native mode): $e');
      return true;
    }
  }

  /// Verify a collection exists
  Future<bool> _verifyCollection(String collectionName) async {
    try {
      final collectionRef = _firestore.collection(collectionName);
      final snapshot = await safeOperation(
        () => collectionRef.limit(1).get(),
        timeoutSeconds: 5,
        operationName: 'Firestore check: $collectionName collection',
      );

      final exists = snapshot != null;
      debugPrint(
          'Firestore (upliftdb): Collection "$collectionName" ${exists ? "exists ✅" : "not found ❓"}');

      return exists;
    } catch (e) {
      debugPrint('Error checking collection "$collectionName": $e');
      return false;
    }
  }

  /// Create a collection if it doesn't exist
  Future<bool> ensureCollection(String collectionName) async {
    try {
      if (_verifiedCollections.contains(collectionName)) {
        return true; // Already verified
      }

      final exists = await _verifyCollection(collectionName);
      if (exists) {
        _verifiedCollections.add(collectionName);
        return true;
      }

      // Create a placeholder document to ensure collection exists
      final docRef =
          _firestore.collection(collectionName).doc('_collection_init');
      await docRef.set({
        'created': FieldValue.serverTimestamp(),
        'initialized': true,
      });

      _verifiedCollections.add(collectionName);
      debugPrint(
          'Firestore (upliftdb): Collection "$collectionName" created ✅');
      return true;
    } catch (e) {
      debugPrint('Error ensuring collection "$collectionName": $e');
      return false;
    }
  }

  /// Ensure all critical collections exist
  Future<bool> ensureCriticalCollections() async {
    final collections = [
      'users',
      'sessions',
      'messages',
      'notifications',
      'app_config'
    ];

    bool allSuccess = true;
    for (final collection in collections) {
      final success = await ensureCollection(collection);
      if (!success) {
        allSuccess = false;
      }
    }

    return allSuccess;
  }
}
