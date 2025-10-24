// lib/data/repositories/user_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user.dart';
import '../../di/interfaces/i_user_repository.dart';
import '../../di/interfaces/i_api_client.dart';

class UserRepository implements IUserRepository {
  final IApiClient apiClient;
  late SharedPreferences _prefs;
  bool _initialized = false;

  UserRepository({
    required this.apiClient,
  }) {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Get user profile
  @override
  Future<User> getUserProfile() async {
    final response = await apiClient.get('/api/v1/users/me');
    return User.fromJson(response);
  }

  // Update user profile
  @override
  Future<User> updateProfile({
    String? name,
    String? email,
    String? profileImage,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (profileImage != null) body['profile_image'] = profileImage;

    final response = await apiClient.put(
      '/api/v1/users/me',
      body,
    );

    return User.fromJson(response);
  }

  // Update user preferences
  @override
  Future<User> updatePreferences(Map<String, dynamic> preferences) async {
    final response = await apiClient.put(
      '/api/v1/users/me/preferences',
      {
        'preferences': preferences,
      },
    );

    return User.fromJson(response);
  }

  // Get user ID
  @override
  Future<String?> getUserId() async {
    await _initPrefs();
    return _prefs.getString('user_id');
  }
}
