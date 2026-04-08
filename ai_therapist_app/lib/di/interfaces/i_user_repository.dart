// lib/di/interfaces/i_user_repository.dart
import '../../domain/entities/user.dart';
abstract class IUserRepository {
  Future<User> getUserProfile();
  Future<User> updateProfile({
    String? name,
    String? email,
    String? profileImage,
  });
  Future<User> updatePreferences(Map<String, dynamic> preferences);
  Future<String?> getUserId();
}
