import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides the authenticated Firebase user context for local data scoping.
class UserContextService {
  UserContextService._internal();

  static final UserContextService _instance = UserContextService._internal();

  factory UserContextService() => _instance;

  static const _localUserKey = 'user_context.local_user_id';

  String? _cachedLocalUserId;

  /// Returns the current Firebase user ID, or null when no user is signed in.
  String? getCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;

  /// Returns authenticated state.
  bool isUserAuthenticated() => FirebaseAuth.instance.currentUser != null;

  /// Lazily resolves the active user identifier for local storage scoping.
  ///
  /// If a Firebase user is authenticated, their UID is returned.
  /// Otherwise a device-scoped anonymous ID is generated and cached.
  Future<String> getActiveUserId() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      return firebaseUser.uid;
    }

    if (_cachedLocalUserId != null) {
      return _cachedLocalUserId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localUserKey);
    if (stored != null && stored.isNotEmpty) {
      _cachedLocalUserId = stored;
      return stored;
    }

    final generated = 'local_${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_localUserKey, generated);
    _cachedLocalUserId = generated;
    debugPrint('UserContextService: created local scoped user_id=$generated');
    return generated;
  }

  /// Convenience accessors for optional profile information.
  String? getCurrentUserEmail() => FirebaseAuth.instance.currentUser?.email;

  String? getCurrentUserPhone() =>
      FirebaseAuth.instance.currentUser?.phoneNumber;

  Map<String, dynamic> getCurrentUserInfo() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const {};
    }

    return {
      'uid': user.uid,
      'email': user.email,
      'phone': user.phoneNumber,
      'displayName': user.displayName,
      'providers': user.providerData.map((p) => p.providerId).toList(),
    };
  }
}
