// lib/utils/web_connectivity_stub.dart
// This file provides stub implementations for connectivity_plus on web
import 'dart:async';
enum ConnectivityResult { bluetooth, wifi, ethernet, mobile, none, vpn, other }
class Connectivity {
  Future<ConnectivityResult> checkConnectivity() async {
    return ConnectivityResult.wifi;
  }
  Stream<ConnectivityResult> get onConnectivityChanged {
    return Stream.periodic(const Duration(seconds: 30), (_) {
      return ConnectivityResult.wifi;
    });
  }
}
