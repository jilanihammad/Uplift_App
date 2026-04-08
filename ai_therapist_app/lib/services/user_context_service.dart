import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'package:ai_therapist_app/utils/logging_service.dart';
const _authGuardTag = 'AuthGuard';
class UserContextService {
  UserContextService._internal();
  static final UserContextService _instance = UserContextService._internal();
  factory UserContextService() => _instance;
  static const _localUserKey = 'user_context.local_user_id';
  String? _cachedLocalUserId;
  String? getCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;
  bool isUserAuthenticated() => FirebaseAuth.instance.currentUser != null;
  bool isSignedIn() => isUserAuthenticated();
  String? getSignedInUserId({String? operation}) {
    final userId = getCurrentUserId();
    if (userId == null || userId.isEmpty) {
      if (operation != null) {
        final message = 'Auth guard bail – $operation (user signed out)';
        logger.info(message, tag: _authGuardTag);
        developer.log(message, name: _authGuardTag);
      }
      return null;
    }
    return userId;
  }
  @Deprecated('Use getSignedInUserId() combined with auth guards instead.')
  Future<String> getActiveUserId() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      return firebaseUser.uid;
    }
    final stored = await _loadCachedLocalUserId();
    if (stored != null) {
      return stored;
    }
    throw const AuthRequiredException('No authenticated user available');
  }
  Future<String?> _loadCachedLocalUserId() async {
    if (_cachedLocalUserId != null) {
      return _cachedLocalUserId;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localUserKey);
    if (stored != null && stored.isNotEmpty) {
      _cachedLocalUserId = stored;
      return stored;
    }
    return null;
  }
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
class AuthRequiredException implements Exception {
  const AuthRequiredException(this.message);
  final String message;
  @override
  String toString() => 'AuthRequiredException: $message';
}
