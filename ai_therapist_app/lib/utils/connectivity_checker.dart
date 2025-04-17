// lib/utils/connectivity_checker.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart' if (dart.library.html) 'package:ai_therapist_app/utils/web_connectivity_stub.dart';

class ConnectivityChecker {
  final Connectivity _connectivity = Connectivity();
  
  // Check for internet connection
  Future<bool> hasConnection() async {
    if (kIsWeb) {
      // On web, assume connection is always available
      return true;
    }
    
    try {
      // Get the connectivity result
      final dynamic result = await _connectivity.checkConnectivity();
      
      // Handle different return types
      if (result is Iterable) {
        // For platforms returning a list of connectivity results
        for (var r in result) {
          if (r != ConnectivityResult.none) {
            return true;
          }
        }
        return false;
      } else {
        // For platforms returning a single result (including web stub)
        return result != ConnectivityResult.none;
      }
    } catch (e) {
      print('Error checking connectivity: $e');
      // Default to assuming no connection on error
      return false;
    }
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
      
      // Check if disconnected based on result type
      bool isDisconnected = false;
      
      if (result is Iterable) {
        // All results must be 'none' to be considered disconnected
        isDisconnected = true;
        for (var r in result) {
          if (r != ConnectivityResult.none) {
            isDisconnected = false;
            break;
          }
        } 
      } else {
        // Single result
        isDisconnected = result == ConnectivityResult.none;
      }
      
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