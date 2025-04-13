// lib/domain/repositories/auth_repository.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_therapist_app/domain/entities/user.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/di/service_locator.dart';

class AuthRepository {
  final String baseUrl;
  final http.Client _httpClient;
  late SharedPreferences _prefs;
  late AuthService _authService;
  bool _initialized = false;

  AuthRepository({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    _authService = serviceLocator<AuthService>();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return await _authService.isLoggedIn;
  }

  // Get user profile
  Future<User> getUserProfile() async {
    try {
      await _initPrefs();
      final userInfo = await _authService.getUserInfo();
      
      // Check if user data exists in storage
      final userData = _prefs.getString('user_data');
      if (userData != null) {
        return User.fromJson(jsonDecode(userData));
      }
      
      // Create user from AuthService info
      final user = User(
        id: userInfo['uid'] ?? '1',
        name: userInfo['name'] ?? 'User',
        email: userInfo['email'] ?? 'user@example.com',
        photoUrl: userInfo['photoUrl'],
        phoneNumber: userInfo['phone'],
        createdAt: DateTime.now(),
      );
      
      // Store user data
      await _prefs.setString(
        'user_data',
        jsonEncode(user.toJson()),
      );
      
      return user;
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  // Login with email and password
  Future<User> login(String email, String password) async {
    try {
      final success = await _authService.login(email, password);
      
      if (!success) {
        throw Exception('Login failed');
      }
      
      return await getUserProfile();
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  // Register new user
  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final success = await _authService.register(name, email, password);
      
      if (!success) {
        throw Exception('Registration failed');
      }
      
      return await getUserProfile();
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }
  
  // Sign in with Google
  Future<User> signInWithGoogle() async {
    try {
      final success = await _authService.signInWithGoogle();
      
      if (!success) {
        throw Exception('Google sign-in failed');
      }
      
      return await getUserProfile();
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
  }
  
  // Verify phone number
  Future<Map<String, dynamic>> verifyPhoneNumber(String phoneNumber) async {
    try {
      // Simulate verification code being sent
      await Future.delayed(const Duration(seconds: 1));
      
      final verificationId = 'mock-verification-id-${DateTime.now().millisecondsSinceEpoch}';
      final resendToken = 123456;
      
      return {
        'success': true,
        'verificationId': verificationId,
        'resendToken': resendToken,
        'message': null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Phone verification failed: $e',
      };
    }
  }
  
  // Sign in with phone verification code
  Future<User> signInWithPhoneAuthCredential(String verificationId, String smsCode) async {
    try {
      final success = await _authService.signInWithPhoneAuthCredential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      
      if (!success) {
        throw Exception('Phone verification failed');
      }
      
      return await getUserProfile();
    } catch (e) {
      throw Exception('Phone verification failed: $e');
    }
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
  }
}