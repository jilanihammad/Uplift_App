// lib/data/repositories/auth_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user.dart';
import '../../di/interfaces/i_auth_repository.dart';
import '../../di/interfaces/i_api_client.dart';
class AuthRepository implements IAuthRepository {
  final IApiClient? apiClient;
  late SharedPreferences _prefs;
  bool _initialized = false;
  AuthRepository({
    this.apiClient,
  }) {
    _initPrefs();
  }
  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }
  @override
  Future<User> login(String email, String password) async {
    await _initPrefs();
    if (apiClient != null) {
      final response = await apiClient!.post(
        '/api/v1/auth/login',
        {
          'email': email,
          'password': password,
        },
      );
      await _prefs.setString('auth_token', response['access_token']);
      return User.fromJson(response['user']);
    } else {
      await Future.delayed(const Duration(seconds: 1));
      await _prefs.setString(
          'auth_token', 'mock_token_${DateTime.now().millisecondsSinceEpoch}');
      return User(
        id: '1',
        name: 'Test User',
        email: email,
        createdAt: DateTime.now(),
      );
    }
  }
  @override
  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _initPrefs();
    if (apiClient != null) {
      final response = await apiClient!.post(
        '/api/v1/auth/register',
        {
          'name': name,
          'email': email,
          'password': password,
        },
      );
      await _prefs.setString('auth_token', response['access_token']);
      return User.fromJson(response['user']);
    } else {
      await Future.delayed(const Duration(seconds: 1));
      await _prefs.setString(
          'auth_token', 'mock_token_${DateTime.now().millisecondsSinceEpoch}');
      return User(
        id: '1',
        name: name,
        email: email,
        createdAt: DateTime.now(),
      );
    }
  }
  @override
  Future<void> logout() async {
    await _initPrefs();
    try {
      if (apiClient != null) {
        await apiClient!.post('/api/v1/auth/logout', {});
      }
    } catch (e) {
    } finally {
      await _prefs.remove('auth_token');
    }
  }
  @override
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    if (apiClient != null) {
      await apiClient!.post(
        '/api/v1/auth/change-password',
        {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    }
  }
  @override
  Future<void> requestPasswordReset(String email) async {
    if (apiClient != null) {
      await apiClient!.post(
        '/api/v1/auth/reset-password-request',
        {
          'email': email,
        },
      );
    }
  }
  @override
  Future<void> confirmPasswordReset(String token, String newPassword) async {
    if (apiClient != null) {
      await apiClient!.post(
        '/api/v1/auth/reset-password-confirm',
        {
          'token': token,
          'new_password': newPassword,
        },
      );
    }
  }
  @override
  Future<bool> isAuthenticated() async {
    await _initPrefs();
    final token = _prefs.getString('auth_token');
    return token != null;
  }
}
