// lib/di/modules/audio_services_module.dart
import 'package:get_it/get_it.dart';
// Service interfaces
import '../interfaces/i_audio_recording_service.dart';
import '../interfaces/i_tts_service.dart';
import '../interfaces/i_websocket_audio_manager.dart';
import '../interfaces/i_audio_file_manager.dart';
import '../interfaces/i_voice_service.dart';
import '../interfaces/i_audio_settings.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../services/audio_recording_service.dart';
import '../../services/simple_tts_service.dart';
import '../../services/websocket_audio_manager.dart';
import '../../services/audio_file_manager.dart';
import '../../services/voice_session_coordinator.dart';
import '../../services/audio_player_manager.dart';
import '../../services/recording_manager.dart';
import '../../services/gemini_live_duplex_controller.dart';
import '../../services/config_service.dart';
class AudioServicesModule {
  static bool _firstRun = true;
  static void registerServices(GetIt locator) {
    // Note: AudioPlayerManager is typically already registered by service_locator.dart with AudioSettings
    if (!locator.isRegistered<AudioPlayerManager>()) {
      locator.registerLazySingleton<AudioPlayerManager>(() {
        return AudioPlayerManager(audioSettings: locator<IAudioSettings>());
      });
    }
    if (!locator.isRegistered<RecordingManager>()) {
      locator.registerLazySingleton<RecordingManager>(() {
        return RecordingManager();
      });
    }
    if (!locator.isRegistered<IAudioRecordingService>()) {
      locator.registerLazySingleton<IAudioRecordingService>(() {
        return AudioRecordingService(
            recordingManager: locator<RecordingManager>());
      });
    }
    if (!locator.isRegistered<GeminiLiveDuplexController>()) {
      locator.registerLazySingleton<GeminiLiveDuplexController>(() {
        final configService = locator.isRegistered<ConfigService>()
            ? locator<ConfigService>()
            : null;
        return GeminiLiveDuplexController(
          recordingService: locator<IAudioRecordingService>(),
          audioPlayerManager: locator<AudioPlayerManager>(),
          configService: configService,
        );
      });
    }
    // Note: ITTSService may already be registered by service_locator.dart
    if (!locator.isRegistered<ITTSService>()) {
      locator.registerLazySingleton<ITTSService>(() {
        return SimpleTTSService(
          audioSettings: locator<IAudioSettings>(),
          // Note: onTTSComplete callback will be set by AudioGenerator
        );
      });
    }
    if (!locator.isRegistered<IWebSocketAudioManager>()) {
      locator.registerLazySingleton<IWebSocketAudioManager>(() {
        return WebSocketAudioManager(
          apiClient: locator<ApiClient>(),
        );
      });
    }
    // Note: IAudioFileManager may already be registered by service_locator.dart
    if (!locator.isRegistered<IAudioFileManager>()) {
      locator.registerLazySingleton<IAudioFileManager>(() {
        return AudioFileManager();
      });
    }
    if (!locator.isRegistered<IVoiceService>()) {
      locator.registerLazySingleton<IVoiceService>(() {
        return VoiceSessionCoordinator(
          recordingService: locator<IAudioRecordingService>(),
          ttsService: locator<ITTSService>(),
          wsManager: locator<IWebSocketAudioManager>(),
          fileManager: locator<IAudioFileManager>(),
        );
      });
    }
  }
  static void unregisterServices(GetIt locator) {
    final servicesToUnregister = [
      IVoiceService,
      IAudioFileManager,
      IWebSocketAudioManager,
      ITTSService,
      IAudioRecordingService,
      AudioPlayerManager,
    ];
    for (final serviceType in servicesToUnregister) {
      if (locator.isRegistered(instance: serviceType)) {
        try {
          locator.unregister(instance: serviceType);
        } catch (e) {}
      }
    }
  }
  static bool areServicesRegistered(GetIt locator) {
    final requiredServices = [
      AudioPlayerManager,
      IAudioRecordingService,
      ITTSService,
      IWebSocketAudioManager,
      IAudioFileManager,
      IVoiceService,
    ];
    for (final serviceType in requiredServices) {
      if (!locator.isRegistered(instance: serviceType)) {
        return false;
      }
    }
    return true;
  }
  static Future<void> initializeServices(GetIt locator) async {
    try {
      final voiceService = locator<IVoiceService>();
      await voiceService.initialize();
    } catch (e) {
      rethrow;
    }
  }
}
