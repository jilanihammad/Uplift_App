// lib/di/modules/audio_services_module.dart

import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';

// Service interfaces
import '../interfaces/i_audio_recording_service.dart';
import '../interfaces/i_tts_service.dart';
import '../interfaces/i_websocket_audio_manager.dart';
import '../interfaces/i_audio_file_manager.dart';
import '../interfaces/i_voice_service.dart';
import '../../data/datasources/remote/api_client.dart';

// Service implementations  
import '../../services/audio_recording_service.dart';
import '../../services/simple_tts_service.dart';
import '../../services/websocket_audio_manager.dart';
import '../../services/audio_file_manager.dart';
import '../../services/voice_session_coordinator.dart';
import '../../services/audio_player_manager.dart';
import '../../services/recording_manager.dart';

/// Module for registering refactored audio services
/// Replaces the monolithic VoiceService with focused, single-responsibility services
class AudioServicesModule {
  static bool _firstRun = true;
  
  /// Register all audio services with dependency injection
  static void registerServices(GetIt locator) {
    // Phase 2.2.5: Guard verbose DI logging to prevent spam during rebuilds
    if (kDebugMode && _firstRun) {
      print('[AudioServicesModule] Registering refactored audio services...');
      _firstRun = false;
    }

    // Register AudioPlayerManager (required by TTSService)
    // Note: AudioPlayerManager may already be registered by service_locator.dart
    if (!locator.isRegistered<AudioPlayerManager>()) {
      locator.registerLazySingleton<AudioPlayerManager>(() {
        return AudioPlayerManager();
      });
    }

    // Register RecordingManager as SINGLETON - prevents race conditions
    if (!locator.isRegistered<RecordingManager>()) {
      locator.registerLazySingleton<RecordingManager>(() {
        return RecordingManager();
      });
    }

    // Register AudioRecordingService with singleton RecordingManager
    if (!locator.isRegistered<IAudioRecordingService>()) {
      locator.registerLazySingleton<IAudioRecordingService>(() {
        return AudioRecordingService(recordingManager: locator<RecordingManager>());
      });
    }

    // Register SimpleTTSService (best-in-class single-owner pattern)
    // Note: ITTSService may already be registered by service_locator.dart
    if (!locator.isRegistered<ITTSService>()) {
      locator.registerLazySingleton<ITTSService>(() {
        return SimpleTTSService(
          audioPlayerManager: locator<AudioPlayerManager>(),
          // Note: onTTSComplete callback will be set by AudioGenerator
          // when it calls setTTSStateCallback() - no circular dependency
        );
      });
    }

    // Register WebSocketAudioManager
    if (!locator.isRegistered<IWebSocketAudioManager>()) {
      locator.registerLazySingleton<IWebSocketAudioManager>(() {
        return WebSocketAudioManager(
          apiClient: locator<ApiClient>(),
        );
      });
    }

    // Register AudioFileManager
    // Note: IAudioFileManager may already be registered by service_locator.dart
    if (!locator.isRegistered<IAudioFileManager>()) {
      locator.registerLazySingleton<IAudioFileManager>(() {
        return AudioFileManager();
      });
    }

    // Register VoiceSessionCoordinator as IVoiceService
    // This replaces the old monolithic VoiceService registration
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

    // Phase 2.2.5: Removed verbose completion logging
  }

  /// Unregister all audio services (for testing or cleanup)
  static void unregisterServices(GetIt locator) {
    if (kDebugMode) {
      print('[AudioServicesModule] Unregistering audio services...');
    }

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
          if (kDebugMode) {
            print('[AudioServicesModule] Unregistered $serviceType');
          }
        } catch (e) {
          if (kDebugMode) {
            print('[AudioServicesModule] Failed to unregister $serviceType: $e');
          }
        }
      }
    }

    if (kDebugMode) {
      print('[AudioServicesModule] Audio services unregistered');
    }
  }

  /// Check if all audio services are properly registered
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
        if (kDebugMode) {
          print('[AudioServicesModule] Service not registered: $serviceType');
        }
        return false;
      }
    }

    if (kDebugMode) {
      print('[AudioServicesModule] All required audio services are registered');
    }
    return true;
  }

  /// Initialize all audio services
  static Future<void> initializeServices(GetIt locator) async {
    if (kDebugMode) {
      print('[AudioServicesModule] Initializing audio services...');
    }

    try {
      // Initialize the main IVoiceService (VoiceSessionCoordinator)
      // This will initialize all dependent services
      final voiceService = locator<IVoiceService>();
      await voiceService.initialize();

      if (kDebugMode) {
        print('[AudioServicesModule] All audio services initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AudioServicesModule] Failed to initialize audio services: $e');
      }
      rethrow;
    }
  }
}