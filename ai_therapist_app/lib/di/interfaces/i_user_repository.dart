// lib/di/interfaces/i_user_repository.dart

import '../../domain/entities/user.dart';

/// Interface for user repository operations
/// Provides contract for user profile management and preferences
/// 
/// This interface defines all user-related operations including
/// profile retrieval, updates, preferences management, and user identification.
abstract class IUserRepository {
  
  // Profile Management
  
  /// Get the current user's profile
  /// 
  /// Returns a [User] object with current profile information
  /// Throws an exception if user is not authenticated or profile cannot be retrieved
  Future<User> getUserProfile();
  
  /// Update user profile information
  /// 
  /// [name] - Optional new name for the user
  /// [email] - Optional new email address
  /// [profileImage] - Optional new profile image URL or path
  /// Returns updated [User] object
  /// Throws an exception if update fails
  Future<User> updateProfile({
    String? name,
    String? email,
    String? profileImage,
  });
  
  // Preferences Management
  
  /// Update user preferences
  /// 
  /// [preferences] - Map of preference keys to values
  /// Returns updated [User] object with new preferences
  /// Throws an exception if update fails
  Future<User> updatePreferences(Map<String, dynamic> preferences);
  
  // User Identification
  
  /// Get the current user's ID
  /// 
  /// Returns the user ID string if authenticated
  /// Returns null if no user is currently logged in
  Future<String?> getUserId();
}