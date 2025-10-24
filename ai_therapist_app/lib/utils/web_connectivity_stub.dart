// lib/utils/web_connectivity_stub.dart
// This file provides stub implementations for connectivity_plus on web
import 'dart:async';

enum ConnectivityResult { bluetooth, wifi, ethernet, mobile, none, vpn, other }

class Connectivity {
  // Simple implementation for web that assumes the connection is always available
  Future<ConnectivityResult> checkConnectivity() async {
    return ConnectivityResult.wifi;
  }

  // Simple implementation that emits a fake connectivity event every 30 seconds
  Stream<ConnectivityResult> get onConnectivityChanged {
    return Stream.periodic(const Duration(seconds: 30), (_) {
      return ConnectivityResult.wifi;
    });
  }
}
