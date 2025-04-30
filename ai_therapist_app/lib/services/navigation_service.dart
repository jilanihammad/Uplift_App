// A service to manage navigation state across the app
import 'dart:async';

class NavigationService {
  // Stream controller for bottom navigation bar visibility
  final StreamController<bool> _bottomNavVisibilityController =
      StreamController<bool>.broadcast();

  // Stream to listen for visibility changes
  Stream<bool> get bottomNavVisibilityStream =>
      _bottomNavVisibilityController.stream;

  // Current visibility state (defaults to true - visible)
  bool _isBottomNavVisible = true;
  bool get isBottomNavVisible => _isBottomNavVisible;

  // Method to show the bottom navigation bar
  void showBottomNav() {
    _isBottomNavVisible = true;
    _bottomNavVisibilityController.add(true);
  }

  // Method to hide the bottom navigation bar
  void hideBottomNav() {
    _isBottomNavVisible = false;
    _bottomNavVisibilityController.add(false);
  }

  // Clean up resources
  void dispose() {
    _bottomNavVisibilityController.close();
  }
}
