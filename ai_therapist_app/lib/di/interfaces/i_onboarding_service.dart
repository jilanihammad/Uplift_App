// lib/di/interfaces/i_onboarding_service.dart

import 'dart:async';

/// Interface for onboarding service operations
/// Provides contract for user onboarding flow management
abstract class IOnboardingService {
  // Onboarding flow
  Future<void> startOnboarding(String userId);
  Future<void> completeOnboarding(String userId);
  Future<bool> isOnboardingComplete(String userId);
  
  // Step management
  Future<void> completeStep(String userId, String stepId);
  Future<void> skipStep(String userId, String stepId);
  Future<List<String>> getCompletedSteps(String userId);
  Future<String?> getCurrentStep(String userId);
  Future<String?> getNextStep(String userId);
  
  // Profile setup
  Future<void> updateProfileStep(String userId, Map<String, dynamic> profileData);
  Future<void> setTherapyGoals(String userId, List<String> goals);
  Future<void> setTherapyExperience(String userId, String experience);
  Future<void> setPreferredStyle(String userId, String style);
  
  // Preferences setup
  Future<void> setNotificationPreferences(String userId, Map<String, bool> preferences);
  Future<void> setSessionPreferences(String userId, Map<String, dynamic> preferences);
  Future<void> setPrivacyPreferences(String userId, Map<String, bool> preferences);
  
  // Initial assessments
  Future<void> saveMoodAssessment(String userId, Map<String, dynamic> assessment);
  Future<void> saveCopingStrategiesAssessment(String userId, List<String> strategies);
  Future<void> saveWellnessGoals(String userId, List<String> goals);
  
  // Onboarding data
  Future<Map<String, dynamic>?> getOnboardingData(String userId);
  Future<void> saveOnboardingData(String userId, Map<String, dynamic> data);
  Future<void> clearOnboardingData(String userId);
  
  // Progress tracking
  Future<double> getOnboardingProgress(String userId);
  Future<int> getEstimatedTimeRemaining(String userId);
  
  // Validation
  Future<bool> validateProfileData(Map<String, dynamic> data);
  Future<List<String>> getValidationErrors(Map<String, dynamic> data);
  
  // Recommendations
  Future<List<String>> getRecommendedTherapyStyles(String userId);
  Future<Map<String, dynamic>> getPersonalizedRecommendations(String userId);
  
  // Introduction content
  Future<List<Map<String, dynamic>>> getWelcomeContent();
  Future<List<Map<String, dynamic>>> getFeatureIntroductions();
  Future<Map<String, dynamic>> getCBTIntroduction();
  
  // State management
  bool get isInitialized;
  Future<void> initialize();
  void dispose();
}