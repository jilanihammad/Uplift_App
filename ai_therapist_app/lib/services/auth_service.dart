// lib/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ai_therapist_app/di/interfaces/i_auth_service.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';
import 'package:ai_therapist_app/di/interfaces/i_auth_event_handler.dart';
import 'package:ai_therapist_app/di/events/auth_events.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/i_api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class AuthService implements IAuthService {
  static const AUTH_TOKEN_KEY = 'auth_token';
  static const EMAIL_KEY = 'user_email';
  static const PHONE_KEY = 'user_phone';
  static const HAS_COMPLETED_SIGNUP_KEY = 'has_completed_signup';
  @override
  final authStatusChangedController = ValueNotifier<bool>(false);
  late SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(),
  );
  bool _initialized = false;
  String? _cachedAuthToken;
  String? _verificationId;
  int? _resendToken;
  final UserProfileService _userProfileService;
  final IAuthEventHandler _authEventHandler;
  AuthService({
    required UserProfileService userProfileService,
    required IAuthEventHandler authEventHandler,
  })  : _userProfileService = userProfileService,
        _authEventHandler = authEventHandler;
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      String? secureToken = await _secureStorage.read(key: AUTH_TOKEN_KEY);
      final legacyToken = _prefs.getString(AUTH_TOKEN_KEY);
      if (secureToken == null &&
          legacyToken != null &&
          legacyToken.isNotEmpty) {
        secureToken = legacyToken;
        await _secureStorage.write(key: AUTH_TOKEN_KEY, value: legacyToken);
        await _prefs.remove(AUTH_TOKEN_KEY);
      }
      _cachedAuthToken = secureToken;
      final apiClient = _apiClientInstance;
      if (_cachedAuthToken != null &&
          _cachedAuthToken!.isNotEmpty &&
          apiClient != null) {
        apiClient.setAuthToken(_cachedAuthToken!);
      }
      if ((_cachedAuthToken == null || _cachedAuthToken!.isEmpty) &&
          FirebaseAuth.instance.currentUser != null) {
        await _storeFirebaseToken(forceRefresh: false);
      }
    }
  }
  IApiClient? get _apiClientInstance {
    try {
      return DependencyContainer().apiClient;
    } catch (_) {
      return null;
    }
  }
  Future<void> _persistAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      return;
    }
    await _ensureInitialized();
    await _secureStorage.write(key: AUTH_TOKEN_KEY, value: token);
    await _prefs.remove(AUTH_TOKEN_KEY);
    _cachedAuthToken = token;
    final apiClient = _apiClientInstance;
    if (apiClient != null) {
      apiClient.setAuthToken(token);
    }
  }
  Future<String?> _storeFirebaseToken({bool forceRefresh = false}) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        return null;
      }
      final token = await firebaseUser.getIdToken(forceRefresh);
      await _persistAuthToken(token);
      return token;
    } catch (e) {
      return null;
    }
  }
  Future<String> _getCurrentUserId() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      return firebaseUser.uid;
    }
    return 'user_${DateTime.now().millisecondsSinceEpoch}';
  }
  @override
  Future<bool> get isLoggedIn async {
    await _ensureInitialized();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      try {
        final token = await firebaseUser.getIdToken(true);
        await _persistAuthToken(token);
        return true;
      } catch (e) {
        await logout();
        return false;
      }
    }
    return _cachedAuthToken != null && _cachedAuthToken!.isNotEmpty;
  }
  @override
  Future<bool> get hasCompletedSignup async {
    await _ensureInitialized();
    return _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;
  }
  @override
  Future<void> syncWithOnboardingService() async {
    await _ensureInitialized();
    try {
      final hasCompleted = _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;
      if (hasCompleted) {
        await _authEventHandler
            .handleUserSignupCompleted(UserSignupCompletedEvent(
          userId: await _getCurrentUserId(),
        ));
      }
    } catch (e) {}
  }
  @override
  bool get isLoggedInSync {
    try {
      return false; // Simplified - requires async check
    } catch (_) {
      return false;
    }
  }
  @override
  Future<Map<String, dynamic>> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  }) async {
    try {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
        );
      } catch (appCheckError) {}
      String formattedPhoneNumber = phoneNumber.trim();
      if (!formattedPhoneNumber.startsWith('+')) {
        formattedPhoneNumber =
            '+1${formattedPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
      } else {
        formattedPhoneNumber =
            '+${formattedPhoneNumber.substring(1).replaceAll(RegExp(r'[^0-9]'), '')}';
      }
      if (_isPhoneNumberRateLimited(formattedPhoneNumber)) {
        return {
          'success': false,
          'error': 'rate_limited',
          'message':
              'Too many verification attempts. Please try again later or use another sign-in method.',
        };
      }
      const Duration timeout = Duration(seconds: 30);
      bool codeSent = false;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {
          onVerificationCompleted(credential);
        },
        verificationFailed: (FirebaseAuthException error) {
          if (error.code == 'too-many-requests') {
            _addRateLimitedNumber(formattedPhoneNumber);
          }
          if (error.code == 'missing-client-identifier') {
            try {
              FirebaseAppCheck.instance.getToken(true).then((_) {
              }).catchError((_) {
              });
            } catch (_) {}
          }
          onVerificationFailed(error);
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId; // Store for later use
          _resendToken = resendToken; // Store for later use
          codeSent = true;
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          onCodeAutoRetrievalTimeout(verificationId);
        },
        timeout: timeout,
      );
      return {
        'success': true,
        'codeSent': codeSent,
        'phoneNumber': formattedPhoneNumber,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'general_error',
        'message': 'Unable to send verification code. Please try again later.',
      };
    }
  }
  final Map<String, DateTime> _rateLimitedPhoneNumbers = {};
  bool _isPhoneNumberRateLimited(String phoneNumber) {
    final limitExpiry = _rateLimitedPhoneNumbers[phoneNumber];
    if (limitExpiry == null) return false;
    final now = DateTime.now();
    if (now.isAfter(limitExpiry)) {
      _rateLimitedPhoneNumbers.remove(phoneNumber);
      return false;
    }
    return true;
  }
  void _addRateLimitedNumber(String phoneNumber) {
    _rateLimitedPhoneNumbers[phoneNumber] = DateTime.now().add(
      const Duration(hours: 24),
    );
  }
  @override
  Future<bool> signInWithPhoneAuthCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      await _ensureInitialized();
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      try {
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final user = userCredential.user;
        if (user == null) {
          return false;
        }
        await _prefs.setString(PHONE_KEY, user.phoneNumber ?? '');
        final hasCompleted = await hasCompletedSignup;
        if (hasCompleted) {
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            phoneNumber: user.phoneNumber,
            isNewUser: false,
            authMethod: AuthMethod.phone,
          ));
        } else {
          await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            phoneNumber: user.phoneNumber,
            isNewUser: true,
            authMethod: AuthMethod.phone,
          ));
        }
        await _storeFirebaseToken(forceRefresh: true);
        return true;
      } catch (credentialError) {
        if (credentialError.toString().contains("invalid-verification-code")) {
        }
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  @override
  Future<bool> signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await _ensureInitialized();
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      if (user == null) {
        return false;
      }
      await _prefs.setString(PHONE_KEY, user.phoneNumber ?? '');
      final hasCompleted = await hasCompletedSignup;
      if (hasCompleted) {
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          phoneNumber: user.phoneNumber,
          isNewUser: false,
          authMethod: AuthMethod.phone,
        ));
      } else {
        await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          phoneNumber: user.phoneNumber,
          isNewUser: true,
          authMethod: AuthMethod.phone,
        ));
      }
      await _storeFirebaseToken(forceRefresh: true);
      return true;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<bool> login(String email, String password) async {
    try {
      await _ensureInitialized();
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        return false;
      }
      await _prefs.setString(EMAIL_KEY, email);
      final hasCompleted = await hasCompletedSignup;
      if (hasCompleted) {
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          email: email,
          isNewUser: false,
          authMethod: AuthMethod.email,
        ));
      } else {
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          email: email,
          isNewUser: true,
          authMethod: AuthMethod.email,
        ));
      }
      await _storeFirebaseToken(forceRefresh: true);
      return true;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<bool> register(String name, String email, String password) async {
    try {
      await _ensureInitialized();
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        return false;
      }
      await user.updateDisplayName(name);
      await _prefs.setString(EMAIL_KEY, email);
      await _prefs.setString('user_name', name);
      await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
      await _authEventHandler
          .handleUserRegistrationCompleted(UserRegistrationCompletedEvent(
        userId: user.uid,
        email: email,
        name: name,
      ));
      await _storeFirebaseToken(forceRefresh: true);
      return true;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<void> completeSignup() async {
    await _ensureInitialized();
    await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, true);
    final userId = await _getCurrentUserId();
    await _authEventHandler.handleUserSignupCompleted(UserSignupCompletedEvent(
      userId: userId,
    ));
  }
  @override
  Future<bool> signInWithGoogle() async {
    try {
      await _ensureInitialized();
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile', 'openid'],
        serverClientId:
            '385290373302-leq56ddeh0h2kqlg611v25bptdajttof.apps.googleusercontent.com',
      );
      GoogleSignInAccount? googleUser;
      try {
        await googleSignIn.signOut();
        googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return false;
        }
      } catch (e) {
        if (e.toString().contains("ApiException: 10:")) {
          return false;
        }
        return false;
      }
      try {
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        if (googleAuth.accessToken == null || googleAuth.idToken == null) {
          return false;
        }
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final user = userCredential.user;
        if (user == null) {
          return false;
        }
        await _prefs.setString(EMAIL_KEY, user.email ?? '');
        final hasCompleted = await hasCompletedSignup;
        if (hasCompleted) {
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            email: user.email,
            isNewUser: false,
            authMethod: AuthMethod.google,
          ));
        } else {
          await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            email: user.email,
            isNewUser: true,
            authMethod: AuthMethod.google,
          ));
        }
        await _storeFirebaseToken(forceRefresh: true);
        return true;
      } catch (authError) {
        try {
          await googleSignIn.signOut();
        } catch (_) {}
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  @override
  Future<Map<String, dynamic>> getUserInfo() async {
    await _ensureInitialized();
    final email = _prefs.getString(EMAIL_KEY) ?? '';
    final phone = _prefs.getString(PHONE_KEY) ?? '';
    final name = _prefs.getString('user_name') ?? 'User';
    return {
      'email': email,
      'phone': phone,
      'name': name,
      'id': 'user_${DateTime.now().millisecondsSinceEpoch}',
    };
  }
  @override
  Future<bool> logout() async {
    try {
      await _ensureInitialized();
      final userId = await _getCurrentUserId();
      await FirebaseAuth.instance.signOut();
      await _secureStorage.delete(key: AUTH_TOKEN_KEY);
      await _prefs.remove(AUTH_TOKEN_KEY);
      _cachedAuthToken = null;
      _apiClientInstance?.clearAuthToken();
      await _authEventHandler.handleUserLoggedOut(UserLoggedOutEvent(
        userId: userId,
      ));
      return true;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<bool> verifySession() async {
    await _ensureInitialized();
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        return false;
      }
      try {
        final token = await firebaseUser.getIdToken(true);
        await _persistAuthToken(token);
        return true;
      } catch (e) {
        await logout();
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}
