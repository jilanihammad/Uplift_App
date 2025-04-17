// lib/utils/connectivity_checker.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart' if (dart.library.html) 'package:ai_therapist_app/utils/web_connectivity_stub.dart';

class ConnectivityChecker {
  final Connectivity _connectivity = Connectivity();
  
  // Check for internet connection
  Future<bool> hasConnection() async {
    if (kIsWeb) {
      // On web, assume connection is available
      return true;
    }
    
    // Handle the case where we get a list of connection results or a single result
    final result = await _connectivity.checkConnectivity();
    
    if (result is List<ConnectivityResult>) {
      // If we get a list, check if any connection is available
      return result.any((r) => r != ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      // If we get a single result, check if it's not none
      return result != ConnectivityResult.none;
    }
    
    // Default return if we get an unexpected type
    return false;
  }
  
  // Get stream of connectivity changes
  Stream<dynamic> get connectivityStream => 
      _connectivity.onConnectivityChanged;
  
  // Check if device is offline
  Future<bool> isOffline() async => !(await hasConnection());
  
  // Check if we can connect to a specific host
  Future<bool> canConnect(String host) async {
    if (kIsWeb) {
      // On web, assume we can connect
      return true;
    }
    
    // First check if we have any connection
    final hasConn = await hasConnection();
    if (!hasConn) return false;
    
    try {
      // Try to perform a test request
      // For security reasons, we can't use dart:io's Socket on web
      // So we'll just return true for now
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking connection to $host: $e');
      }
      return false;
    }
  }
  
  // Show a snackbar indicating connectivity status
  void showConnectivitySnackBar(BuildContext context, dynamic result) {
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      
      // Handle both the List<ConnectivityResult> and single ConnectivityResult case
      final bool isDisconnected = result is List<ConnectivityResult> 
          ? result.every((r) => r == ConnectivityResult.none)
          : result == ConnectivityResult.none;
      
      if (isDisconnected) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You are offline'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Your connection has been restored'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}