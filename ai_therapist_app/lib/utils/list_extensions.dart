import 'dart:math';

/// Extension methods for List<T>
extension ListExtensions<T> on List<T> {
  /// Returns a random element from the list
  /// Throws [StateError] if the list is empty
  T random() {
    if (isEmpty) {
      throw StateError('Cannot get random element from empty list');
    }
    final random = Random();
    return this[random.nextInt(length)];
  }
}
