import '../voice_service.dart';
import '../auto_listening_snapshot_source.dart';
import '../audio_player_manager.dart';
import '../recording_manager.dart';
import '../voice_session_coordinator.dart';
import 'audio_capture.dart';
import 'audio_playback.dart';
import 'ai_gateway.dart';
import 'mic_auto_mode_controller.dart';

class VoicePipelineDependencies {
  final VoiceService voiceService;
  final AutoListeningSnapshotSource autoListening;
  final AudioPlayerManager? audioPlayerManager;
  final RecordingManager? recordingManager;
  final VoiceSessionCoordinator? sessionCoordinator;
  final AudioCapture? audioCapture;
  final AudioPlayback? audioPlayback;
  final AiGateway? aiGateway;
  final MicAutoModeController? micController;

  const VoicePipelineDependencies({
    required this.voiceService,
    required this.autoListening,
    this.audioPlayerManager,
    this.recordingManager,
    this.sessionCoordinator,
    this.audioCapture,
    this.audioPlayback,
    this.aiGateway,
    this.micController,
  });
}
