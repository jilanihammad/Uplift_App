// lib/di/interfaces/i_auth_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_profile.dart';

/// Interface for authentication service
/// Provides contract for all authentication-related operations
abstract class IAuthService {
  // Authentication state
  Stream<User?> get authStateChanges;
  User? get currentUser;
  bool get isAuthenticated;

  // Email authentication
  Future<UserCredential?> signInWithEmail(String email, String password);
  Future<UserCredential?> registerWithEmail(String email, String password, String name);
  
  // Phone authentication
  Future<void> signInWithPhone(String phoneNumber);
  Future<UserCredential?> verifyPhoneNumber(String verificationId, String smsCode);
  
  // Google authentication
  Future<UserCredential?> signInWithGoogle();
  
  // Session management
  Future<void> signOut();
  Future<void> deleteAccount();
  
  // User profile
  Future<void> updateUserProfile(UserProfile profile);
  Future<UserProfile?> getUserProfile();
  
  // Password management
  Future<void> sendPasswordResetEmail(String email);
  Future<void> updatePassword(String newPassword);
  
  // Account verification
  Future<void> sendEmailVerification();
  
  // Session validation
  Future<bool> validateSession();
  Future<void> refreshToken();
  
  // Initialization
  Future<void> initialize();
  void dispose();
}