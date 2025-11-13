import '../auto_listening_coordinator.dart';

abstract class MicAutoModeController {
  Future<void> enableAutoMode();
  Future<void> disableAutoMode();
  void triggerListening();
  bool get isAutoModeEnabled;
}

class AutoListeningMicController implements MicAutoModeController {
  final AutoListeningCoordinator coordinator;

  AutoListeningMicController(this.coordinator);

  @override
  Future<void> enableAutoMode() => coordinator.enableAutoMode();

  @override
  Future<void> disableAutoMode() => coordinator.disableAutoMode();

  @override
  void triggerListening() => coordinator.triggerListening();

  @override
  bool get isAutoModeEnabled => coordinator.autoModeEnabled;
}
