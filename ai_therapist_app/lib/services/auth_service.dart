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
  // Keys for shared preferences
  static const AUTH_TOKEN_KEY = 'auth_token';
  static const EMAIL_KEY = 'user_email';
  static const PHONE_KEY = 'user_phone';
  static const HAS_COMPLETED_SIGNUP_KEY = 'has_completed_signup';

  // Auth status changed stream controller
  @override
  final authStatusChangedController = ValueNotifier<bool>(false);

  // SharedPreferences instance
  late SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(),
  );
  bool _initialized = false;
  String? _cachedAuthToken;

  // For phone auth
  String? _verificationId;
  int? _resendToken;

  // Dependencies injected via constructor
  final UserProfileService _userProfileService;
  final IAuthEventHandler _authEventHandler;

  // Constructor with dependency injection
  AuthService({
    required UserProfileService userProfileService,
    required IAuthEventHandler authEventHandler,
  })  : _userProfileService = userProfileService,
        _authEventHandler = authEventHandler;

  // Ensure the service is initialized before use
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
      if (kDebugMode) {
        debugPrint('AuthService: Failed to refresh Firebase token: $e');
      }
      return null;
    }
  }

  // Helper method to get current user ID
  Future<String> _getCurrentUserId() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      return firebaseUser.uid;
    }
    // Fallback to generated ID
    return 'user_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Check if user is logged in
  @override
  Future<bool> get isLoggedIn async {
    await _ensureInitialized();

    // Check if we're using Firebase Auth
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      // Verify the token is still valid
      try {
        // Force token refresh to ensure it's valid and cache it
        final token = await firebaseUser.getIdToken(true);
        await _persistAuthToken(token);
        return true;
      } catch (e) {
        await logout();
        return false;
      }
    }

    // Fall back to token check
    return _cachedAuthToken != null && _cachedAuthToken!.isNotEmpty;
  }

  // Check if user has completed signup process
  @override
  Future<bool> get hasCompletedSignup async {
    await _ensureInitialized();
    return _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;
  }

  // Make sure onboarding status is in sync with signup status
  @override
  Future<void> syncWithOnboardingService() async {
    await _ensureInitialized();

    try {
      // No need to check for null with dependency injection

      final hasCompleted = _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;

      if (kDebugMode) {
        debugPrint(
          "AuthService: Syncing with AuthCoordinator - hasCompletedSignup = $hasCompleted",
        );
      }

      if (hasCompleted) {
        if (kDebugMode) {
          debugPrint(
            "AuthService: User has completed signup, emitting signup completed event",
          );
        }
        // Emit event that user has completed signup
        await _authEventHandler
            .handleUserSignupCompleted(UserSignupCompletedEvent(
          userId: await _getCurrentUserId(),
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("AuthService: Error syncing with AuthCoordinator: $e");
      }
      // Continue without syncing
    }
  }

  // Sync version for splash screen
  @override
  bool get isLoggedInSync {
    try {
      return false; // Simplified - requires async check
    } catch (_) {
      return false;
    }
  }

  // Phone number verification with Firebase
  @override
  Future<Map<String, dynamic>> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  }) async {
    try {

      // Make sure Firebase App Check is initialized
      try {
        // This is a no-op if already initialized, but ensures it's ready for phone auth
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
        );
      } catch (appCheckError) {
        // Log but continue - we have fallbacks in place
      }

      // Validate and format phone number
      String formattedPhoneNumber = phoneNumber.trim();

      // Add country code if missing
      if (!formattedPhoneNumber.startsWith('+')) {
        formattedPhoneNumber =
            '+1${formattedPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
      } else {
        // Just clean non-numeric chars except the +
        formattedPhoneNumber =
            '+${formattedPhoneNumber.substring(1).replaceAll(RegExp(r'[^0-9]'), '')}';
      }

      // Check for rate limiting before making the request
      if (_isPhoneNumberRateLimited(formattedPhoneNumber)) {
        return {
          'success': false,
          'error': 'rate_limited',
          'message':
              'Too many verification attempts. Please try again later or use another sign-in method.',
        };
      }

      // Set a shorter timeout for better UX
      const Duration timeout = Duration(seconds: 30);

      // Flag for successful code sent
      bool codeSent = false;

      // Use carefully formatted phone number
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {
          onVerificationCompleted(credential);
        },
        verificationFailed: (FirebaseAuthException error) {
          // Special handling for rate limiting errors
          if (error.code == 'too-many-requests') {
            _addRateLimitedNumber(formattedPhoneNumber);
          }

          // Special handling for missing client identifier
          if (error.code == 'missing-client-identifier') {
            // Try to force App Check token refresh
            try {
              FirebaseAppCheck.instance.getToken(true).then((_) {
                // Token refreshed successfully
              }).catchError((_) {
                // Non-fatal: App Check token refresh failed
              });
            } catch (_) {
              // Non-fatal: App Check not available
            }
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

  // Additional private methods to handle rate limiting
  final Map<String, DateTime> _rateLimitedPhoneNumbers = {};

  bool _isPhoneNumberRateLimited(String phoneNumber) {
    final limitExpiry = _rateLimitedPhoneNumbers[phoneNumber];
    if (limitExpiry == null) return false;

    // Check if the rate limit has expired (24 hours)
    final now = DateTime.now();
    if (now.isAfter(limitExpiry)) {
      _rateLimitedPhoneNumbers.remove(phoneNumber);
      return false;
    }

    return true;
  }

  void _addRateLimitedNumber(String phoneNumber) {
    // Set rate limit for 24 hours
    _rateLimitedPhoneNumbers[phoneNumber] = DateTime.now().add(
      const Duration(hours: 24),
    );
  }

  // Sign in with phone verification code using Firebase
  @override
  Future<bool> signInWithPhoneAuthCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      await _ensureInitialized();


      // Create the phone auth credential
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );

      // Sign in with credential with error handling
      try {
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final user = userCredential.user;

        if (user == null) {
          return false;
        }


        // Store the phone number if available
        await _prefs.setString(PHONE_KEY, user.phoneNumber ?? '');

        // Check if this is first login
        final hasCompleted = await hasCompletedSignup;

        if (hasCompleted) {
          // User has already completed signup/onboarding
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            phoneNumber: user.phoneNumber,
            isNewUser: false,
            authMethod: AuthMethod.phone,
          ));
        } else {
          // Mark as new user (this is their first login with phone)
          await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);

          // Emit event for new user
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

  // Sign in with credential for auto-retrieval using Firebase
  @override
  Future<bool> signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await _ensureInitialized();

      // Sign in with Firebase
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (user == null) {
        return false;
      }

      // Store the phone number if available
      await _prefs.setString(PHONE_KEY, user.phoneNumber ?? '');

      // Check if this is first login
      final hasCompleted = await hasCompletedSignup;

      if (hasCompleted) {
        // User has already completed signup/onboarding
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          phoneNumber: user.phoneNumber,
          isNewUser: false,
          authMethod: AuthMethod.phone,
        ));
      } else {
        // Mark as new user (this is their first login with credential)
        await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);

        // Emit event for new user
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

  // Login using email and password
  @override
  Future<bool> login(String email, String password) async {
    try {
      await _ensureInitialized();

      // Use Firebase Auth instead of mock implementation
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return false;
      }

      // Store additional info
      await _prefs.setString(EMAIL_KEY, email);

      // Check if the user has completed signup
      final hasCompleted = await hasCompletedSignup;

      // If user has already completed signup, skip onboarding
      if (hasCompleted) {
        // Emit event for returning user
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          email: email,
          isNewUser: false,
          authMethod: AuthMethod.email,
        ));
      } else {
        // Emit event for new user
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
      if (kDebugMode) {
        debugPrint('Login error: $e');
      }
      return false;
    }
  }

  // Register new user with Firebase
  @override
  Future<bool> register(String name, String email, String password) async {
    try {
      await _ensureInitialized();

      // Use Firebase Auth instead of mock
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return false;
      }

      // Update display name
      await user.updateDisplayName(name);

      // Store user data
      await _prefs.setString(EMAIL_KEY, email);
      await _prefs.setString('user_name', name);

      // Mark as new user (this is their first login)
      await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);

      // Emit registration completed event
      await _authEventHandler
          .handleUserRegistrationCompleted(UserRegistrationCompletedEvent(
        userId: user.uid,
        email: email,
        name: name,
      ));

      await _storeFirebaseToken(forceRefresh: true);

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Registration error: $e');
      }
      return false;
    }
  }

  // Complete signup (marking user as having gone through initial process)
  @override
  Future<void> completeSignup() async {
    await _ensureInitialized();
    await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, true);

    // Emit signup completed event
    final userId = await _getCurrentUserId();
    await _authEventHandler.handleUserSignupCompleted(UserSignupCompletedEvent(
      userId: userId,
    ));
    if (kDebugMode) {
      debugPrint('AuthService: Emitted signup completed event');
    }
  }

  // Sign in with Google - real implementation
  @override
  Future<bool> signInWithGoogle() async {
    try {
      await _ensureInitialized();


      // SKIP Firebase App Check - causing too many problems
      // Just attempt Google Sign-In directly

      // Configure Google Sign-In with minimal scopes to reduce permission issues
      final GoogleSignIn googleSignIn = GoogleSignIn(
        // Include all three recommended OAuth scopes - hardcoded to ensure consistency
        scopes: ['email', 'profile', 'openid'],

        // Use the OAuth client ID directly here - hardcoded to ensure it's always used
        serverClientId:
            '385290373302-leq56ddeh0h2kqlg611v25bptdajttof.apps.googleusercontent.com',
      );


      // First check if user is already signed in with Google
      GoogleSignInAccount? googleUser;

      try {
        // Always try to sign out first to ensure a fresh start
        await googleSignIn.signOut();

        // Direct to interactive sign-in
        googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          return false;
        }
      } catch (e) {

        // Special handling for error code 10 (DEVELOPER_ERROR)
        if (e.toString().contains("ApiException: 10:")) {
          // OAuth client ID info is useful for debugging
          // Return false since this requires developer intervention
          return false;
        }

        // For other errors, try email/password fallback
        return false;
      }

      try {
        // Get authentication details
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        // Validate tokens before proceeding
        if (googleAuth.accessToken == null || googleAuth.idToken == null) {
          return false;
        }

        // Create Firebase credential
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );


        // Sign in with Firebase
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final user = userCredential.user;

        if (user == null) {
          return false;
        }


        // Store relevant user info
        await _prefs.setString(EMAIL_KEY, user.email ?? '');

        // Check if this is first login
        final hasCompleted = await hasCompletedSignup;

        if (hasCompleted) {
          // Skip onboarding for returning users
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            email: user.email,
            isNewUser: false,
            authMethod: AuthMethod.google,
          ));
        } else {
          // Mark as new user (this is their first login with Google)
          await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);

          // Emit event for new user
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

        // Aggressive error recovery - try to sign out from Google to reset state
        try {
          await googleSignIn.signOut();
        } catch (_) {
          // Best-effort sign out for error recovery
        }

        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // Get user info
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

  // Logout - updated to handle Firebase auth
  @override
  Future<bool> logout() async {
    try {
      await _ensureInitialized();

      // Get user ID before logout
      final userId = await _getCurrentUserId();

      // Firebase logout
      await FirebaseAuth.instance.signOut();

      // Clear local auth token
      await _secureStorage.delete(key: AUTH_TOKEN_KEY);
      await _prefs.remove(AUTH_TOKEN_KEY);
      _cachedAuthToken = null;
      _apiClientInstance?.clearAuthToken();

      // Emit logout event
      await _authEventHandler.handleUserLoggedOut(UserLoggedOutEvent(
        userId: userId,
      ));
      if (kDebugMode) {
        debugPrint('AuthService: Emitted logout event');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Logout error: $e');
      }
      return false;
    }
  }

  /// Force session verification and refresh
  @override
  Future<bool> verifySession() async {
    await _ensureInitialized();

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        return false;
      }

      // Optionally, check token validity
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
