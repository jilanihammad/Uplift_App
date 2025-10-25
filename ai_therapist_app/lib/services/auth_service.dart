// lib/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
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
        debugPrint("AuthService: User has valid Firebase token");
        return true;
      } catch (e) {
        debugPrint("AuthService: Error refreshing token, signing out user: $e");
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
      debugPrint("AuthService: Starting phone verification for: $phoneNumber");

      // Make sure Firebase App Check is initialized
      try {
        // This is a no-op if already initialized, but ensures it's ready for phone auth
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
        );
        debugPrint("AuthService: Pre-checked Firebase App Check for phone auth");
      } catch (appCheckError) {
        // Log but continue - we have fallbacks in place
        debugPrint("AuthService: AppCheck warning for phone auth: $appCheckError");
      }

      // Validate and format phone number
      String formattedPhoneNumber = phoneNumber.trim();

      // Add country code if missing
      if (!formattedPhoneNumber.startsWith('+')) {
        debugPrint("AuthService: Phone number missing country code, adding +1");
        formattedPhoneNumber =
            '+1${formattedPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
      } else {
        // Just clean non-numeric chars except the +
        formattedPhoneNumber =
            '+${formattedPhoneNumber.substring(1).replaceAll(RegExp(r'[^0-9]'), '')}';
      }

      debugPrint("AuthService: Formatted phone number: $formattedPhoneNumber");

      // Check for rate limiting before making the request
      if (_isPhoneNumberRateLimited(formattedPhoneNumber)) {
        debugPrint(
          "AuthService: Phone number is rate limited, suggesting alternative auth method",
        );
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
          debugPrint("AuthService: Phone auth automatically verified");
          onVerificationCompleted(credential);
        },
        verificationFailed: (FirebaseAuthException error) {
          debugPrint(
            "AuthService: Phone verification failed: ${error.code}: ${error.message}",
          );
          // Log detailed error for debugging
          debugPrint("AuthService: Full error details: ${error.toString()}");

          // Special handling for rate limiting errors
          if (error.code == 'too-many-requests') {
            debugPrint(
              "AuthService: Detected rate limiting, adding to rate limited list",
            );
            _addRateLimitedNumber(formattedPhoneNumber);
          }

          // Special handling for missing client identifier
          if (error.code == 'missing-client-identifier') {
            debugPrint(
              "AuthService: Missing client identifier error - this is usually due to Firebase App Check issues",
            );
            // Try to force App Check token refresh
            try {
              FirebaseAppCheck.instance.getToken(true).then((_) {
                debugPrint("AuthService: Successfully refreshed App Check token");
              }).catchError((e) {
                debugPrint("AuthService: Failed to refresh App Check token: $e");
              });
            } catch (e) {
              debugPrint("AuthService: Error refreshing App Check token: $e");
            }
          }

          onVerificationFailed(error);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint(
            "AuthService: SMS verification code sent to $formattedPhoneNumber",
          );
          _verificationId = verificationId; // Store for later use
          _resendToken = resendToken; // Store for later use
          codeSent = true;
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint("AuthService: SMS auto-retrieval timeout");
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
      debugPrint('Phone verification general error: $e');
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
      Duration(hours: 24),
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

      debugPrint("AuthService: Attempting to sign in with phone verification code");

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
          debugPrint("AuthService: Firebase returned null user after phone auth");
          return false;
        }

        debugPrint(
          "AuthService: Successfully signed in with phone: ${user.phoneNumber}",
        );

        // Store the phone number if available
        await _prefs.setString(PHONE_KEY, user.phoneNumber ?? '');

        // Check if this is first login
        final hasCompleted = await hasCompletedSignup;
        debugPrint(
          "AuthService: signInWithPhone - hasCompletedSignup = $hasCompleted",
        );

        if (hasCompleted) {
          // User has already completed signup/onboarding
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            phoneNumber: user.phoneNumber,
            isNewUser: false,
            authMethod: AuthMethod.phone,
          ));
          debugPrint(
            "AuthService: signInWithPhone - Emitted login event for returning user",
          );
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
          debugPrint(
            "AuthService: signInWithPhone - Emitted login event for new user",
          );
        }

        await _storeFirebaseToken(forceRefresh: true);

        return true;
      } catch (credentialError) {
        debugPrint(
          "AuthService: Error signing in with phone credential: $credentialError",
        );

        if (credentialError.toString().contains("invalid-verification-code")) {
          debugPrint("AuthService: Invalid verification code entered");
        }
        return false;
      }
    } catch (e) {
      debugPrint('Phone sign-in general error: $e');
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
      debugPrint(
        "AuthService: signInWithCredential - hasCompletedSignup = $hasCompleted",
      );

      if (hasCompleted) {
        // User has already completed signup/onboarding
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          phoneNumber: user.phoneNumber,
          isNewUser: false,
          authMethod: AuthMethod.phone,
        ));
        debugPrint(
          "AuthService: signInWithCredential - Emitted login event for returning user",
        );
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
        debugPrint(
          "AuthService: signInWithCredential - Emitted login event for new user",
        );
      }

      await _storeFirebaseToken(forceRefresh: true);

      return true;
    } catch (e) {
      debugPrint('Auto-retrieval sign-in error: $e');
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
      debugPrint("AuthService: login - hasCompletedSignup = $hasCompleted");

      // If user has already completed signup, skip onboarding
      if (hasCompleted) {
        // Emit event for returning user
        await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
          userId: user.uid,
          email: email,
          isNewUser: false,
          authMethod: AuthMethod.email,
        ));
        debugPrint(
          "AuthService: login - Emitted login event for returning user",
        );
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

      debugPrint("AuthService: Starting Google SignIn flow");

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

      debugPrint(
          "AuthService: GoogleSignIn configured with scopes: ['email', 'profile', 'openid']");
      debugPrint(
          "AuthService: GoogleSignIn client ID: 385290373302-leq56ddeh0h2kqlg611v25bptdajttof.apps.googleusercontent.com");

      // First check if user is already signed in with Google
      GoogleSignInAccount? googleUser;

      try {
        // Always try to sign out first to ensure a fresh start
        await googleSignIn.signOut();
        debugPrint("AuthService: Signed out from any previous Google sessions");

        // Direct to interactive sign-in
        debugPrint("AuthService: Triggering Google sign-in dialog");
        googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          debugPrint("AuthService: User cancelled Google Sign-In");
          return false;
        }
        debugPrint(
            "AuthService: Interactive Google signin successful: ${googleUser.email}");
      } catch (e) {
        debugPrint("AuthService: Interactive Google signin error: $e");
        debugPrint("AuthService: Error details: ${e.runtimeType}");

        // Special handling for error code 10 (DEVELOPER_ERROR)
        if (e.toString().contains("ApiException: 10:")) {
          debugPrint(
            "AuthService: Detected configuration error in Google Sign-In (error 10)",
          );
          debugPrint(
            "AuthService: This typically means the SHA-1 certificate fingerprint is not configured in Firebase console",
          );
          // OAuth client ID info is useful for debugging
          debugPrint(
            "AuthService: Using OAuth Client ID: 385290373302-leq56ddeh0h2kqlg611v25bptdajttof.apps.googleusercontent.com",
          );
          // Return false since this requires developer intervention
          return false;
        }

        // For other errors, try email/password fallback
        return false;
      }

      try {
        // Get authentication details
        debugPrint("AuthService: Getting auth tokens for: ${googleUser.email}");
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        // Validate tokens before proceeding
        if (googleAuth.accessToken == null || googleAuth.idToken == null) {
          debugPrint("AuthService: Failed to get valid Google auth tokens");
          return false;
        }

        // Create Firebase credential
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        debugPrint("AuthService: Got Google auth tokens, signing in with Firebase");

        // Sign in with Firebase
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final user = userCredential.user;

        if (user == null) {
          debugPrint("AuthService: Firebase returned null user after Google auth");
          return false;
        }

        debugPrint("AuthService: Successfully signed in with Google: ${user.email}");

        // Store relevant user info
        await _prefs.setString(EMAIL_KEY, user.email ?? '');

        // Check if this is first login
        final hasCompleted = await hasCompletedSignup;
        debugPrint(
          "AuthService: signInWithGoogle - hasCompletedSignup = $hasCompleted",
        );

        if (hasCompleted) {
          // Skip onboarding for returning users
          await _authEventHandler.handleUserLoggedIn(UserLoggedInEvent(
            userId: user.uid,
            email: user.email,
            isNewUser: false,
            authMethod: AuthMethod.google,
          ));
          debugPrint(
            "AuthService: signInWithGoogle - Emitted login event for returning user",
          );
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
          debugPrint(
            "AuthService: signInWithGoogle - Emitted login event for new user",
          );
        }

        await _storeFirebaseToken(forceRefresh: true);

        return true;
      } catch (authError) {
        debugPrint(
          "AuthService: Error during Firebase authentication with Google: $authError",
        );

        // Aggressive error recovery - try to sign out from Google to reset state
        try {
          await googleSignIn.signOut();
          debugPrint("AuthService: Signed out of Google to reset state after error");
        } catch (e) {
          debugPrint("AuthService: Error during Google signout: $e");
        }

        return false;
      }
    } catch (e) {
      debugPrint('Google sign-in error: $e');
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
        debugPrint(
          "AuthService: No Firebase user found during session verification",
        );
        return false;
      }

      // Optionally, check token validity
      try {
        final token = await firebaseUser.getIdToken(true);
        await _persistAuthToken(token);
        return true;
      } catch (e) {
        debugPrint("AuthService: Error refreshing token during verification: $e");
        await logout();
        return false;
      }
    } catch (e) {
      debugPrint("AuthService: Error during session verification: $e");
      return false;
    }
  }
}
