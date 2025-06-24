// lib/di/interfaces/i_auth_repository.dart

import '../../domain/entities/user.dart';

/// Interface for authentication repository operations
/// Provides contract for user authentication, registration, and session management
/// 
/// This interface defines all authentication-related operations including
/// login, registration, logout, password management, and authentication status checks.
abstract class IAuthRepository {
  
  // Authentication Operations
  
  /// Login with email and password
  /// 
  /// [email] - User's email address
  /// [password] - User's password
  /// Returns a [User] object upon successful authentication
  /// Throws an exception if authentication fails
  Future<User> login(String email, String password);
  
  /// Register a new user
  /// 
  /// [name] - User's full name
  /// [email] - User's email address
  /// [password] - User's desired password
  /// Returns a [User] object upon successful registration
  /// Throws an exception if registration fails
  Future<User> register({
    required String name,
    required String email,
    required String password,
  });
  
  /// Logout the current user
  /// 
  /// Clears authentication tokens and session data
  /// Safe to call even if no user is currently logged in
  Future<void> logout();
  
  // Password Management
  
  /// Change user's password
  /// 
  /// [currentPassword] - User's current password for verification
  /// [newPassword] - User's new desired password
  /// Throws an exception if current password is incorrect or change fails
  Future<void> changePassword(String currentPassword, String newPassword);
  
  /// Request password reset
  /// 
  /// [email] - Email address to send password reset instructions
  /// Sends password reset email to the specified address
  /// Does not throw if email doesn't exist (for security reasons)
  Future<void> requestPasswordReset(String email);
  
  /// Confirm password reset with token
  /// 
  /// [token] - Password reset token received via email
  /// [newPassword] - User's new desired password
  /// Throws an exception if token is invalid or expired
  Future<void> confirmPasswordReset(String token, String newPassword);
  
  // Authentication Status
  
  /// Check if a user is currently authenticated
  /// 
  /// Returns true if user has a valid authentication token
  /// Returns false if no user is logged in or token is invalid
  Future<bool> isAuthenticated();
}