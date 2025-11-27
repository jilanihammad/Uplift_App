import 'auto_listening_coordinator.dart';

/// Read-only view used by the VoicePipelineController to mirror
/// AutoListeningCoordinator state without exposing mutating APIs.
abstract class AutoListeningSnapshotSource {
  Stream<AutoListeningState> get stateStream;
  Stream<bool> get autoModeEnabledStream;
  AutoListeningState get currentState;
  bool get autoModeEnabled;
}

class AutoListeningCoordinatorSnapshotSource
    implements AutoListeningSnapshotSource {
  AutoListeningCoordinatorSnapshotSource(this._coordinator);

  final AutoListeningCoordinator _coordinator;

  @override
  Stream<AutoListeningState> get stateStream => _coordinator.stateStream;

  @override
  Stream<bool> get autoModeEnabledStream =>
      _coordinator.autoModeEnabledStream;

  @override
  AutoListeningState get currentState => _coordinator.currentState;

  @override
  bool get autoModeEnabled => _coordinator.autoModeEnabled;
}
