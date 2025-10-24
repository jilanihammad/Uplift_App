// lib/di/interfaces/i_auth_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Interface for authentication service
/// Provides contract for all authentication-related operations using event-driven pattern
abstract class IAuthService {
  // Constants for shared preferences keys
  static const String AUTH_TOKEN_KEY = 'auth_token';
  static const String EMAIL_KEY = 'user_email';
  static const String PHONE_KEY = 'user_phone';
  static const String HAS_COMPLETED_SIGNUP_KEY = 'has_completed_signup';

  // Auth status changed stream controller
  ValueNotifier<bool> get authStatusChangedController;

  // Authentication state
  Future<bool> get isLoggedIn;
  Future<bool> get hasCompletedSignup;
  bool get isLoggedInSync;

  // Phone number verification with Firebase
  Future<Map<String, dynamic>> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  });

  // Sign in with phone verification code using Firebase
  Future<bool> signInWithPhoneAuthCredential({
    required String verificationId,
    required String smsCode,
  });

  // Sign in with credential for auto-retrieval using Firebase
  Future<bool> signInWithCredential(PhoneAuthCredential credential);

  // Login using email and password
  Future<bool> login(String email, String password);

  // Register new user with Firebase
  Future<bool> register(String name, String email, String password);

  // Complete signup (marking user as having gone through initial process)
  Future<void> completeSignup();

  // Sign in with Google - real implementation
  Future<bool> signInWithGoogle();

  // Get user info
  Future<Map<String, dynamic>> getUserInfo();

  // Logout - updated to handle Firebase auth
  Future<bool> logout();

  // Force session verification and refresh
  Future<bool> verifySession();

  // Sync with onboarding service using event-driven pattern
  Future<void> syncWithOnboardingService();
}
