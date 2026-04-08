// lib/di/interfaces/i_auth_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
abstract class IAuthService {
  static const String AUTH_TOKEN_KEY = 'auth_token';
  static const String EMAIL_KEY = 'user_email';
  static const String PHONE_KEY = 'user_phone';
  static const String HAS_COMPLETED_SIGNUP_KEY = 'has_completed_signup';
  ValueNotifier<bool> get authStatusChangedController;
  Future<bool> get isLoggedIn;
  Future<bool> get hasCompletedSignup;
  bool get isLoggedInSync;
  Future<Map<String, dynamic>> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  });
  Future<bool> signInWithPhoneAuthCredential({
    required String verificationId,
    required String smsCode,
  });
  Future<bool> signInWithCredential(PhoneAuthCredential credential);
  Future<bool> login(String email, String password);
  Future<bool> register(String name, String email, String password);
  Future<void> completeSignup();
  Future<bool> signInWithGoogle();
  Future<Map<String, dynamic>> getUserInfo();
  Future<bool> logout();
  Future<bool> verifySession();
  Future<void> syncWithOnboardingService();
}
