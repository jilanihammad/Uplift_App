// A service to manage navigation state across the app
import 'dart:async';
import '../di/interfaces/i_navigation_service.dart';

class NavigationService implements INavigationService {
  // Stream controller for bottom navigation bar visibility
  final StreamController<bool> _bottomNavVisibilityController =
      StreamController<bool>.broadcast();

  // Stream to listen for visibility changes
  @override
  Stream<bool> get bottomNavVisibilityStream =>
      _bottomNavVisibilityController.stream;

  // Current visibility state (defaults to true - visible)
  bool _isBottomNavVisible = true;
  @override
  bool get isBottomNavVisible => _isBottomNavVisible;

  // Method to show the bottom navigation bar
  @override
  void showBottomNav() {
    _isBottomNavVisible = true;
    _bottomNavVisibilityController.add(true);
  }

  // Method to hide the bottom navigation bar
  @override
  void hideBottomNav() {
    _isBottomNavVisible = false;
    _bottomNavVisibilityController.add(false);
  }

  // Clean up resources
  @override
  void dispose() {
    _bottomNavVisibilityController.close();
  }
}
