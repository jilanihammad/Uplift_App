// lib/services/pipeline/voice_pipeline_dependencies.dart
// Clean dependency container for VoicePipelineController

import '../voice_service.dart';
import '../audio_player_manager.dart';
import '../recording_manager.dart';

/// Dependencies required by VoicePipelineController
/// This replaces the scattered dependencies from the old architecture
class VoicePipelineDependencies {
  final VoiceService voiceService;
  final AudioPlayerManager audioPlayerManager;
  final RecordingManager recordingManager;

  const VoicePipelineDependencies({
    required this.voiceService,
    required this.audioPlayerManager,
    required this.recordingManager,
  });

  /// Factory for creating dependencies from service locator
  static VoicePipelineDependencies fromLocator() {
    // This will be implemented to pull from GetIt/service locator
    throw UnimplementedError('Use DependencyContainer to resolve dependencies');
  }
}

/// Factory type for creating VoicePipelineController instances
typedef VoicePipelineControllerFactory = VoicePipelineController Function({
  required VoicePipelineDependencies dependencies,
  bool Function()? micMutedGetter,
  bool Function()? canStartListening,
});
