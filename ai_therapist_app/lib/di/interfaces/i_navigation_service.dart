// lib/di/interfaces/i_navigation_service.dart
abstract class INavigationService {
  Stream<bool> get bottomNavVisibilityStream;
  bool get isBottomNavVisible;
  void showBottomNav();
  void hideBottomNav();
  void dispose();
}
