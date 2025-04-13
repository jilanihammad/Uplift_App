// lib/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';

class AuthService {
  // Use SharedPreferences instead of FlutterSecureStorage for Windows compatibility
  late SharedPreferences _prefs;
  bool _initialized = false;
  
  // Keys for preferences
  static const String AUTH_TOKEN_KEY = 'auth_token';
  static const String EMAIL_KEY = 'user_email';
  static const String PHONE_KEY = 'user_phone';
  static const String HAS_COMPLETED_SIGNUP_KEY = 'has_completed_signup';
  
  // Phone verification variables
  String? _verificationId;
  int? _resendToken;
  
  // Init method to ensure preferences are initialized
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }
  
  // Check if user is logged in - async version
  Future<bool> get isLoggedIn async {
    await _ensureInitialized();
    final token = _prefs.getString(AUTH_TOKEN_KEY);
    return token != null && token.isNotEmpty;
  }
  
  // Check if user has completed signup process
  Future<bool> get hasCompletedSignup async {
    await _ensureInitialized();
    return _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;
  }
  
  // Make sure onboarding status is in sync with signup status
  Future<void> syncWithOnboardingService() async {
    await _ensureInitialized();
    final onboardingService = serviceLocator<OnboardingService>();
    
    final hasCompleted = _prefs.getBool(HAS_COMPLETED_SIGNUP_KEY) ?? false;
    
    print("AuthService: Syncing with OnboardingService - hasCompletedSignup = $hasCompleted");
    
    if (hasCompleted) {
      print("AuthService: User has completed signup, ensuring onboarding is marked complete");
      // If user has completed signup, make sure onboarding is also marked as complete
      await onboardingService.completeOnboarding();
    }
  }
  
  // Sync version for splash screen
  bool get isLoggedInSync {
    try {
      return false; // Simplified - requires async check
    } catch (_) {
      return false;
    }
  }
  
  // Phone number verification (mock)
  Future<bool> verifyPhoneNumber({
    required String phoneNumber,
    required Function onVerificationCompleted,
    required Function onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  }) async {
    try {
      // Mock phone verification for testing
      await Future.delayed(const Duration(seconds: 1));
      _verificationId = 'mock-verification-id-${DateTime.now().millisecondsSinceEpoch}';
      _resendToken = 123456;
      onCodeSent(_verificationId!, _resendToken);
      return true;
    } catch (e) {
      print('Phone verification error: $e');
      return false;
    }
  }
  
  // Sign in with phone verification code (mock)
  Future<bool> signInWithPhoneAuthCredential({
    required String verificationId, 
    required String smsCode
  }) async {
    try {
      await _ensureInitialized();
      // Mock phone sign in
      await Future.delayed(const Duration(seconds: 1));
      await _prefs.setString(AUTH_TOKEN_KEY, 'mock_phone_token_${DateTime.now().millisecondsSinceEpoch}');
      await _prefs.setString(PHONE_KEY, '+1234567890');
      
      // Check if this is first login
      final hasCompleted = await hasCompletedSignup;
      print("AuthService: signInWithPhone - hasCompletedSignup = $hasCompleted");
      
      if (hasCompleted) {
        // User has already completed signup/onboarding
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.completeOnboarding();
        print("AuthService: signInWithPhone - Setting onboarding as complete for returning user");
      } else {
        // Mark as new user (this is their first login with phone)
        await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
        
        // Make sure onboarding is reset for new users
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.resetOnboarding();
        
        print("AuthService: signInWithPhone - Setting up onboarding for new user");
      }
      
      return true;
    } catch (e) {
      print('Phone sign-in error: $e');
      return false;
    }
  }
  
  // Sign in with credential for auto-retrieval
  Future<bool> signInWithCredential(dynamic credential) async {
    try {
      await _ensureInitialized();
      // Mock credential sign in
      await Future.delayed(const Duration(seconds: 1));
      await _prefs.setString(AUTH_TOKEN_KEY, 'mock_auto_phone_token_${DateTime.now().millisecondsSinceEpoch}');
      await _prefs.setString(PHONE_KEY, '+1234567890');
      
      // Check if this is first login
      final hasCompleted = await hasCompletedSignup;
      print("AuthService: signInWithCredential - hasCompletedSignup = $hasCompleted");
      
      if (hasCompleted) {
        // User has already completed signup/onboarding
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.completeOnboarding();
        print("AuthService: signInWithCredential - Setting onboarding as complete for returning user");
      } else {
        // Mark as new user (this is their first login with credential)
        await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
        
        // Reset onboarding for new users
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.resetOnboarding();
        
        print("AuthService: signInWithCredential - Setting up onboarding for new user");
      }
      
      return true;
    } catch (e) {
      print('Auto-retrieval sign-in error: $e');
      return false;
    }
  }
  
  // Login using email and password
  Future<bool> login(String email, String password) async {
    try {
      await _ensureInitialized();
      // Mock authentication
      await Future.delayed(const Duration(seconds: 1));
      await _prefs.setString(AUTH_TOKEN_KEY, 'mock_token_${DateTime.now().millisecondsSinceEpoch}');
      await _prefs.setString(EMAIL_KEY, email);
      
      // Check if the user has completed signup
      final hasCompleted = await hasCompletedSignup;
      print("AuthService: login - hasCompletedSignup = $hasCompleted");
      
      // If user has already completed signup, skip onboarding
      if (hasCompleted) {
        // Ensure onboarding state is marked as complete
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.completeOnboarding();
        print("AuthService: login - Setting onboarding as complete for returning user");
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Login error: $e');
      }
      return false;
    }
  }
  
  // Register new user (mock)
  Future<bool> register(String name, String email, String password) async {
    try {
      await _ensureInitialized();
      
      // Mock registration
      await Future.delayed(const Duration(seconds: 1));
      
      // Store credentials
      await _prefs.setString(AUTH_TOKEN_KEY, 'mock_token_${DateTime.now().millisecondsSinceEpoch}');
      await _prefs.setString(EMAIL_KEY, email);
      
      // Store user data
      await _prefs.setString('user_name', name);
      
      // Mark as new user (this is their first login)
      await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
      
      // Make sure onboarding is reset for new users
      final onboardingService = serviceLocator<OnboardingService>();
      await onboardingService.resetOnboarding();
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Registration error: $e');
      }
      return false;
    }
  }
  
  // Complete signup (marking user as having gone through initial process)
  Future<void> completeSignup() async {
    await _ensureInitialized();
    await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, true);
  }
  
  // Sign in with Google (mock)
  Future<bool> signInWithGoogle() async {
    try {
      await _ensureInitialized();
      
      // Mock Google sign in
      await Future.delayed(const Duration(seconds: 1));
      
      // Store credentials
      await _prefs.setString(AUTH_TOKEN_KEY, 'mock_google_token_${DateTime.now().millisecondsSinceEpoch}');
      await _prefs.setString(EMAIL_KEY, 'google_user@example.com');
      
      // Check if this is first login
      final hasCompleted = await hasCompletedSignup;
      print("AuthService: signInWithGoogle - hasCompletedSignup = $hasCompleted");
      
      if (hasCompleted) {
        // Skip onboarding for returning users
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.completeOnboarding();
        print("AuthService: signInWithGoogle - Setting onboarding as complete for returning user");
      } else {
        // Mark as new user (this is their first login with Google)
        await _prefs.setBool(HAS_COMPLETED_SIGNUP_KEY, false);
        
        // Make sure onboarding is reset for new users
        final onboardingService = serviceLocator<OnboardingService>();
        await onboardingService.resetOnboarding();
        
        print("AuthService: signInWithGoogle - Setting up onboarding for new user");
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Google sign-in error: $e');
      }
      return false;
    }
  }
  
  // Get user info
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
  
  // Logout
  Future<bool> logout() async {
    try {
      await _ensureInitialized();
      
      // Clear auth token
      await _prefs.remove(AUTH_TOKEN_KEY);
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Logout error: $e');
      }
      return false;
    }
  }
}