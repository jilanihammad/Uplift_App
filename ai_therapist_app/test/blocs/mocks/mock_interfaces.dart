import 'package:ai_therapist_app/di/interfaces/i_voice_service.dart';
import 'package:ai_therapist_app/di/interfaces/i_tts_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/audio_player_manager.dart';
import 'package:ai_therapist_app/services/auto_listening_coordinator.dart';
import 'package:ai_therapist_app/services/vad_manager.dart';
import 'package:ai_therapist_app/services/enhanced_vad_manager.dart';
import 'package:ai_therapist_app/services/facades/session_voice_facade.dart';
import 'package:mocktail/mocktail.dart';

class MockVoiceService extends Mock implements VoiceService {}

class MockInterfaceVoiceService extends Mock implements IVoiceService {}

class MockITTSService extends Mock implements ITTSService {}

class MockAudioPlayerManager extends Mock implements AudioPlayerManager {}

class MockAutoListeningCoordinator extends Mock
    implements AutoListeningCoordinator {}

class MockVADManager extends Mock implements VADManager {}

class MockEnhancedVADManager extends Mock implements EnhancedVADManager {}

class MockSessionVoiceFacade extends Mock implements SessionVoiceFacade {}
