// lib/di/interfaces/i_navigation_service.dart

/// Interface for navigation service operations
/// Provides contract for app navigation state management
abstract class INavigationService {
  // Visibility stream
  Stream<bool> get bottomNavVisibilityStream;

  // Current state
  bool get isBottomNavVisible;

  // Navigation control
  void showBottomNav();
  void hideBottomNav();

  // Resource management
  void dispose();
}
