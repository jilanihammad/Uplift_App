// lib/services/user_profile_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../di/interfaces/i_user_profile_service.dart';

class UserProfileService implements IUserProfileService {
  static const String _profileKey = 'user_profile';
  
  // Current profile in memory
  UserProfile? _currentProfile;
  
  // Getter for current profile
  @override
  UserProfile? get profile => _currentProfile;
  
  // Value notifier for profile changes
  final _profileChangedController = ValueNotifier<UserProfile?>(null);
  
  // Observable stream of profile changes
  @override
  ValueNotifier<UserProfile?> get profileChanged => _profileChangedController;
  
  // Initialize profile service
  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final profileString = prefs.getString(_profileKey);
    
    if (profileString != null) {
      try {
        final json = jsonDecode(profileString);
        _currentProfile = UserProfile.fromJson(json);
        _profileChangedController.value = _currentProfile;
      } catch (e) {
        debugPrint('Error loading user profile: $e');
      }
    }
  }
  
  // Save profile to storage
  @override
  Future<void> saveProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(profile.toJson());
      await prefs.setString(_profileKey, json);
      
      _currentProfile = profile;
      _profileChangedController.value = _currentProfile;
    } catch (e) {
      debugPrint('Error saving user profile: $e');
    }
  }
  
  // Update profile with new data
  @override
  Future<void> updateProfile({
    String? name,
    String? email,
    String? gender,
    String? primaryReason,
    List<String>? goals,
    TherapyExperience? therapyExperience,
    List<String>? helpfulTherapyElements,
    String? moodDescription,
    TypicalCopingStrategy? copingStrategy,
    SupportStyle? preferredSupportStyle,
    List<String>? energizers,
    CBTFamiliarity? cbtFamiliarity,
  }) async {
    if (_currentProfile == null) {
      if (name == null) {
        throw Exception('Cannot create a profile without a name');
      }
      
      // Create a new profile
      final newProfile = UserProfile(
        name: name,
        email: email,
        gender: gender,
        primaryReason: primaryReason,
        goals: goals ?? [],
        therapyExperience: therapyExperience ?? TherapyExperience.none,
        helpfulTherapyElements: helpfulTherapyElements ?? [],
        moodDescription: moodDescription,
        copingStrategy: copingStrategy ?? TypicalCopingStrategy.notSure,
        preferredSupportStyle: preferredSupportStyle ?? SupportStyle.notSure,
        energizers: energizers ?? [],
        cbtFamiliarity: cbtFamiliarity ?? CBTFamiliarity.notFamiliar,
      );
      
      await saveProfile(newProfile);
    } else {
      // Update existing profile
      final updatedProfile = _currentProfile!.copyWith(
        name: name,
        email: email,
        gender: gender,
        primaryReason: primaryReason,
        goals: goals,
        therapyExperience: therapyExperience,
        helpfulTherapyElements: helpfulTherapyElements,
        moodDescription: moodDescription,
        copingStrategy: copingStrategy,
        preferredSupportStyle: preferredSupportStyle,
        energizers: energizers,
        cbtFamiliarity: cbtFamiliarity,
      );
      
      await saveProfile(updatedProfile);
    }
  }
  
  // Check if the user has completed the initial setup
  @override
  bool get hasCompletedOnboarding => _currentProfile != null;
  
  // Reset profile (for testing or account deletion)
  @override
  Future<void> resetProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    
    _currentProfile = null;
    _profileChangedController.value = null;
  }
} 