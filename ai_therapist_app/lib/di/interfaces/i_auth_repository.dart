// lib/di/interfaces/i_auth_repository.dart
import '../../domain/entities/user.dart';
abstract class IAuthRepository {
  Future<User> login(String email, String password);
  Future<User> register({
    required String name,
    required String email,
    required String password,
  });
  Future<void> logout();
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<void> requestPasswordReset(String email);
  Future<void> confirmPasswordReset(String token, String newPassword);
  Future<bool> isAuthenticated();
}
