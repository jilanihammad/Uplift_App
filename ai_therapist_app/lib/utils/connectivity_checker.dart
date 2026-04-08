// lib/utils/connectivity_checker.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart'
    if (dart.library.html) 'package:ai_therapist_app/utils/web_connectivity_stub.dart';
class ConnectivityChecker {
  final Connectivity _connectivity = Connectivity();
  Future<bool> hasConnection() async {
    if (kIsWeb) {
      return true;
    }
    try {
      final dynamic result = await _connectivity.checkConnectivity();
      if (result is Iterable) {
        for (var r in result) {
          if (r != ConnectivityResult.none) {
            return true;
          }
        }
        return false;
      } else {
        return result != ConnectivityResult.none;
      }
    } catch (e) {
      return false;
    }
  }
  Stream<dynamic> get connectivityStream => _connectivity.onConnectivityChanged;
  Future<bool> isOffline() async => !(await hasConnection());
  Future<bool> canConnect(String host) async {
    if (kIsWeb) {
      return true;
    }
    final hasConn = await hasConnection();
    if (!hasConn) return false;
    try {
      return true;
    } catch (e) {
      return false;
    }
  }
  void showConnectivitySnackBar(BuildContext context, dynamic result) {
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      bool isDisconnected = false;
      if (result is Iterable) {
        isDisconnected = true;
        for (var r in result) {
          if (r != ConnectivityResult.none) {
            isDisconnected = false;
            break;
          }
        }
      } else {
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
