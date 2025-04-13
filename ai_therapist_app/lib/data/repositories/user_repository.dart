// lib/data/repositories/user_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../datasources/remote/api_client.dart';
import '../../domain/entities/user.dart';

class UserRepository {
  final ApiClient apiClient;
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
  Future<User> getUserProfile() async {
    final response = await apiClient.get('/api/v1/users/me');
    return User.fromJson(response);
  }
  
  // Update user profile
  Future<User> updateProfile({
    String? name,
    String? email,
    String? profileImage,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (profileImage != null) body['profile_image'] = profileImage;
    
    final response = await apiClient.patch(
      '/api/v1/users/me',
      body: body,
    );
    
    return User.fromJson(response);
  }
  
  // Update user preferences
  Future<User> updatePreferences(Map<String, dynamic> preferences) async {
    final response = await apiClient.patch(
      '/api/v1/users/me/preferences',
      body: {
        'preferences': preferences,
      },
    );
    
    return User.fromJson(response);
  }
  
  // Get user ID
  Future<String?> getUserId() async {
    await _initPrefs();
    return _prefs.getString('user_id');
  }
}