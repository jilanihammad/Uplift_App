// A service to manage navigation state across the app
import 'dart:async';
import '../di/interfaces/i_navigation_service.dart';
class NavigationService implements INavigationService {
  final StreamController<bool> _bottomNavVisibilityController =
      StreamController<bool>.broadcast();
  @override
  Stream<bool> get bottomNavVisibilityStream =>
      _bottomNavVisibilityController.stream;
  bool _isBottomNavVisible = true;
  @override
  bool get isBottomNavVisible => _isBottomNavVisible;
  @override
  void showBottomNav() {
    _isBottomNavVisible = true;
    _bottomNavVisibilityController.add(true);
  }
  @override
  void hideBottomNav() {
    _isBottomNavVisible = false;
    _bottomNavVisibilityController.add(false);
  }
  @override
  void dispose() {
    _bottomNavVisibilityController.close();
  }
}
