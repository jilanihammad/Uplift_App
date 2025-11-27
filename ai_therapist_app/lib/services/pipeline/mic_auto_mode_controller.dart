import '../../di/interfaces/i_voice_service.dart';

abstract class MicAutoModeController {
  Future<void> enableAutoMode();
  Future<void> disableAutoMode();
  void triggerListening();
  bool get isAutoModeEnabled;
}

class VoiceServiceMicController implements MicAutoModeController {
  final IVoiceService voiceService;

  VoiceServiceMicController(this.voiceService);

  @override
  Future<void> enableAutoMode() => voiceService.enableAutoMode();

  @override
  Future<void> disableAutoMode() => voiceService.disableAutoMode();

  @override
  void triggerListening() => voiceService.triggerListening();

  @override
  bool get isAutoModeEnabled => voiceService.isAutoModeEnabled;
}
