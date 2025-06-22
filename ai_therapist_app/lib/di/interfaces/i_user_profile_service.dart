// lib/di/interfaces/i_user_profile_service.dart

import 'package:flutter/material.dart';
import '../../models/user_profile.dart';

/// Interface for user profile service operations
/// Provides contract for user profile management and onboarding state
abstract class IUserProfileService {
  // Current profile
  UserProfile? get profile;
  ValueNotifier<UserProfile?> get profileChanged;
  
  // Profile state
  bool get hasCompletedOnboarding;
  
  // Profile management
  Future<void> init();
  Future<void> saveProfile(UserProfile profile);
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
  });
  Future<void> resetProfile();
}