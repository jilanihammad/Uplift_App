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

  // Login with email and password
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

      // Store the token
      await _prefs.setString('auth_token', response['access_token']);

      // Return the user
      return User.fromJson(response['user']);
    } else {
      // Mock implementation for testing
      await Future.delayed(const Duration(seconds: 1));

      // Store mock token
      await _prefs.setString(
          'auth_token', 'mock_token_${DateTime.now().millisecondsSinceEpoch}');

      // Return mock user
      return User(
        id: '1',
        name: 'Test User',
        email: email,
        createdAt: DateTime.now(),
      );
    }
  }

  // Register a new user
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

      // Store the token
      await _prefs.setString('auth_token', response['access_token']);

      // Return the user
      return User.fromJson(response['user']);
    } else {
      // Mock implementation for testing
      await Future.delayed(const Duration(seconds: 1));

      // Store mock token
      await _prefs.setString(
          'auth_token', 'mock_token_${DateTime.now().millisecondsSinceEpoch}');

      // Return mock user
      return User(
        id: '1',
        name: name,
        email: email,
        createdAt: DateTime.now(),
      );
    }
  }

  // Logout user
  @override
  Future<void> logout() async {
    await _initPrefs();
    try {
      if (apiClient != null) {
        await apiClient!.post('/api/v1/auth/logout', {});
      }
    } catch (e) {
      // Ignore errors during logout
    } finally {
      // Always clear the token
      await _prefs.remove('auth_token');
    }
  }

  // Change password
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

  // Request password reset
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

  // Confirm password reset
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

  // Check if user is authenticated
  @override
  Future<bool> isAuthenticated() async {
    await _initPrefs();
    final token = _prefs.getString('auth_token');
    return token != null;
  }
}
