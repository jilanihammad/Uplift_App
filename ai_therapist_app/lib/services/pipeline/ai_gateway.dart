// AI gateway abstraction for the voice pipeline controller.
// Initially a very small surface – it can expand to cover direct TherapyService
// calls once the pipeline starts bypassing VoiceService entirely.

import '../../di/interfaces/i_voice_service.dart';

abstract class AiGateway {
  Future<void> speakText(String text, {String? voice});
  Future<void> stopSpeaking();
}

class VoiceCoordinatorAiGateway implements AiGateway {
  final IVoiceService voiceInterface;

  VoiceCoordinatorAiGateway(this.voiceInterface);

  @override
  Future<void> speakText(String text, {String? voice}) async {
    await voiceInterface.speakText(text, voice: voice);
  }

  @override
  Future<void> stopSpeaking() => voiceInterface.stopAudio();
}
