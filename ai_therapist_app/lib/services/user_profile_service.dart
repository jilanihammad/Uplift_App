// lib/services/user_profile_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../di/interfaces/i_user_profile_service.dart';
class UserProfileService implements IUserProfileService {
  static const String _profileKey = 'user_profile';
  static const String _firstNameKey = 'user_first_name';
  UserProfile? _currentProfile;
  @override
  UserProfile? get profile => _currentProfile;
  final _profileChangedController = ValueNotifier<UserProfile?>(null);
  @override
  ValueNotifier<UserProfile?> get profileChanged => _profileChangedController;
  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final profileString = prefs.getString(_profileKey);
    if (profileString != null) {
      try {
        final json = jsonDecode(profileString);
        _currentProfile = UserProfile.fromJson(json);
        _profileChangedController.value = _currentProfile;
      } catch (e) {}
    }
  }
  @override
  Future<void> saveProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(profile.toJson());
      await prefs.setString(_profileKey, json);
      _currentProfile = profile;
      _profileChangedController.value = _currentProfile;
    } catch (e) {}
  }
  @override
  Future<void> updateProfile({
    String? name,
    String? firstName,
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
      String? autoFirstName = firstName;
      if (autoFirstName == null && name.isNotEmpty) {
        autoFirstName = name.split(' ').first;
      }
      final newProfile = UserProfile(
        name: name,
        firstName: autoFirstName,
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
      String? finalFirstName = firstName;
      if (firstName == null && name != null && name.isNotEmpty) {
        finalFirstName = name.split(' ').first;
      }
      final updatedProfile = _currentProfile!.copyWith(
        name: name,
        firstName: finalFirstName,
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
  Future<void> updateFirstName(String firstName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_firstNameKey, firstName);
      await updateProfile(firstName: firstName);
    } catch (e) {}
  }
  Future<String?> getCachedFirstName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_firstNameKey);
    } catch (e) {
      return null;
    }
  }
  @override
  bool get hasCompletedOnboarding => _currentProfile != null;
  @override
  Future<void> resetProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    _currentProfile = null;
    _profileChangedController.value = null;
  }
}
