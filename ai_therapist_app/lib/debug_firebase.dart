import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/services/firebase_service.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';

class FirebaseDebugScreen extends StatefulWidget {
  const FirebaseDebugScreen({Key? key}) : super(key: key);

  @override
  State<FirebaseDebugScreen> createState() => _FirebaseDebugScreenState();
}

class _FirebaseDebugScreenState extends State<FirebaseDebugScreen> {
  String _status = 'Checking Firebase status...';
  String _authStatus = 'Checking Auth status...';
  String _firestoreStatus = 'Checking Firestore status...';
  String _messagingStatus = 'Checking Messaging status...';
  String _storageStatus = 'Checking Storage status...';
  bool _isLoading = true;
  int _retryCount = 0;
  String _projectId = '';
  String _region = '';

  @override
  void initState() {
    super.initState();
    _checkFirebaseConnection();
  }

  Future<void> _checkFirebaseConnection() async {
    setState(() {
      _isLoading = true;
      _retryCount++;
    });

    try {
      // Check if Firebase is initialized
      bool isInitialized = Firebase.apps.isNotEmpty;
      setState(() {
        _status = isInitialized
            ? 'Firebase is initialized correctly'
            : 'Firebase is NOT initialized';
      });

      // Try to get project info
      try {
        final options = Firebase.app().options;
        _projectId = options.projectId;
        // Firebase doesn't directly expose region, but we can infer it
        final appId = options.appId;
        _region = 'us-central1'; // Default
        if (appId.contains('europe')) _region = 'europe-west1';
        if (appId.contains('asia')) _region = 'asia-east1';
      } catch (e) {
        if (kDebugMode) {
          print('Could not get project info: $e');
        }
      }

      // Check Auth
      try {
        // Don't sign in anonymously anymore
        final user = FirebaseAuth.instance.currentUser;
        setState(() {
          _authStatus = user != null
              ? 'Auth is working correctly. User: ${user.email ?? user.uid}'
              : 'Auth is working but no user is signed in';
        });
      } catch (e) {
        setState(() {
          _authStatus = 'Auth error: $e';
        });
      }

      // Check Firestore with retries
      try {
        bool firestoreConnected = false;
        for (int i = 0; i < 3 && !firestoreConnected; i++) {
          try {
            final result = await FirebaseFirestore.instance
                .collection('_debug_test')
                .doc('test')
                .get()
                .timeout(Duration(seconds: 5 + (i * 2)));
            firestoreConnected = true;
            setState(() {
              _firestoreStatus = 'Firestore is working correctly';
            });
            break;
          } catch (retryError) {
            if (kDebugMode) {
              print('Firestore attempt ${i + 1} failed: $retryError');
            }
            await Future.delayed(Duration(seconds: 1 + i));
            if (i == 2) {
              setState(() {
                _firestoreStatus = 'Firestore error after retries: $retryError';
              });
            }
          }
        }
      } catch (e) {
        setState(() {
          _firestoreStatus = 'Firestore error: $e';
        });
      }

      // Check Storage
      try {
        final ref = FirebaseStorage.instance.ref().child('_debug_test');
        setState(() {
          _storageStatus = 'Storage is working correctly';
        });
      } catch (e) {
        setState(() {
          _storageStatus = 'Storage error: $e';
        });
      }

      // Check Messaging (FCM)
      try {
        final token = await FirebaseMessaging.instance.getToken();
        setState(() {
          _messagingStatus = token != null
              ? 'Messaging is working correctly. Token: ${token.substring(0, 10)}...'
              : 'Could not get FCM token';
        });
      } catch (e) {
        setState(() {
          _messagingStatus = 'Messaging error: $e';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Firebase error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _forceReconnect() async {
    setState(() {
      _isLoading = true;
      _status = 'Forcing reconnection...';
      _authStatus = 'Reconnecting...';
      _firestoreStatus = 'Reconnecting...';
      _messagingStatus = 'Reconnecting...';
      _storageStatus = 'Reconnecting...';
    });

    try {
      // Get the Firebase service and force a reconnect
      if (DependencyContainer().isRegistered<FirebaseService>()) {
        await DependencyContainer().get<FirebaseService>().tryReconnect();
        if (kDebugMode) {
          print('Reconnect attempt completed');
        }
      } else {
        if (kDebugMode) {
          print('FirebaseService not registered in dependency container');
        }
      }

      // Check status again
      await _checkFirebaseConnection();
    } catch (e) {
      if (kDebugMode) {
        print('Error during reconnect: $e');
      }
      setState(() {
        _isLoading = false;
        _status = 'Reconnect error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showFirebaseInfo(context);
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attempt #$_retryCount',
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Project: $_projectId (${_region})',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  _buildStatusCard('Firebase Core', _status),
                  const SizedBox(height: 16),
                  _buildStatusCard('Firebase Auth', _authStatus),
                  const SizedBox(height: 16),
                  _buildStatusCard('Cloud Firestore', _firestoreStatus),
                  const SizedBox(height: 16),
                  _buildStatusCard('Firebase Storage', _storageStatus),
                  const SizedBox(height: 16),
                  _buildStatusCard('Firebase Messaging', _messagingStatus),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _checkFirebaseConnection,
                        child: const Text('Retry Connection Test'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _forceReconnect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Force Reconnect'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFirebaseHelp(),
                ],
              ),
            ),
    );
  }

  void _showFirebaseInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Firebase Project Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project ID: $_projectId'),
            const SizedBox(height: 8),
            Text('Region: $_region'),
            const SizedBox(height: 16),
            const Text('Common Issues:'),
            const SizedBox(height: 8),
            const Text('• Firestore: Check security rules and connectivity'),
            const Text('• Messaging: Ensure FCM setup is complete'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildFirebaseHelp() {
    // Determine the most critical issue
    String helpText = '';
    bool hasAuthIssue = _authStatus.contains('error');
    bool hasFirestoreIssue = _firestoreStatus.contains('error');

    if (hasAuthIssue && _authStatus.contains('admin-restricted-operation')) {
      helpText =
          'Auth Issue: Enable Anonymous Authentication in the Firebase Console > Authentication > Sign-in methods';
    } else if (hasFirestoreIssue && _firestoreStatus.contains('unavailable')) {
      helpText =
          'Firestore Issue: This may be a temporary connectivity issue. Try again in a few minutes or check your project\'s Firestore database setup.';
    }

    if (helpText.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.amber[100],
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Troubleshooting Suggestions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(helpText),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String message) {
    final isSuccess = message.contains('working correctly');
    final isError = message.contains('error');

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (isSuccess)
                  const Icon(Icons.check_circle, color: Colors.green)
                else if (isError)
                  const Icon(Icons.error, color: Colors.red)
                else
                  const Icon(Icons.hourglass_empty, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}
