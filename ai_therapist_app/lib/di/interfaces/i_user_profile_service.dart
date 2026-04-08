// lib/di/interfaces/i_user_profile_service.dart
import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
abstract class IUserProfileService {
  UserProfile? get profile;
  ValueNotifier<UserProfile?> get profileChanged;
  bool get hasCompletedOnboarding;
  Future<void> init();
  Future<void> saveProfile(UserProfile profile);
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
  });
  Future<void> resetProfile();
}
