// lib/data/datasources/local/secure_storage.dart
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Store auth token
  Future<void> saveToken(String token) async {
    await _initPrefs();
    await _prefs.setString('auth_token', token);
  }

  // Retrieve auth token
  Future<String?> getToken() async {
    await _initPrefs();
    return _prefs.getString('auth_token');
  }

  // Delete auth token
  Future<void> deleteToken() async {
    await _initPrefs();
    await _prefs.remove('auth_token');
  }

  // Store user ID
  Future<void> saveUserId(String userId) async {
    await _initPrefs();
    await _prefs.setString('user_id', userId);
  }

  // Retrieve user ID
  Future<String?> getUserId() async {
    await _initPrefs();
    return _prefs.getString('user_id');
  }

  // Store encrypted data (Note: SharedPreferences is not secure, this is a temporary solution)
  Future<void> saveEncrypted(String key, String value) async {
    await _initPrefs();
    await _prefs.setString(key, value);
  }

  // Retrieve encrypted data
  Future<String?> getEncrypted(String key) async {
    await _initPrefs();
    return _prefs.getString(key);
  }

  // Delete encrypted data
  Future<void> deleteEncrypted(String key) async {
    await _initPrefs();
    await _prefs.remove(key);
  }

  // Delete all encrypted data
  Future<void> deleteAll() async {
    await _initPrefs();
    await _prefs.clear();
  }
}
