// lib/services/session_scope_manager.dart
import 'dart:async';
// Service interfaces
import '../di/interfaces/i_voice_service.dart';
import '../di/interfaces/i_audio_recording_service.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../di/interfaces/i_audio_file_manager.dart';
import '../di/interfaces/i_audio_settings.dart';
import 'voice_session_coordinator.dart';
import 'audio_player_manager.dart';
import 'voice_service.dart';
import 'recording_manager.dart';
import '../utils/disposable.dart';
import '../di/service_locator.dart';
class SessionScopeManager {
  final Map<Type, dynamic> _sessionServices = {};
  final List<dynamic> _disposableServices = [];
  bool get inSession => _sessionServices.isNotEmpty;
  Future<void> createSessionScope() async {
    if (inSession) {
      throw StateError(
          'Session already in progress. Call destroySessionScope() first.');
    }
    try {
      await _createSessionServices();
    } catch (e) {
      await _cleanupPartialServices();
      rethrow;
    }
  }
  Future<void> destroySessionScope() async {
    if (!inSession) return;
    try {
      await Future.any([
        _performDisposal(),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException(
              'Session scope disposal timeout', const Duration(seconds: 10));
        }),
      ]);
    } on TimeoutException catch (e) {
      forceCleanup();
      rethrow;
    } catch (e) {
      forceCleanup();
      rethrow;
    }
  }
  Future<void> _performDisposal() async {
    final stopwatch = Stopwatch()..start();
    try {
      final asyncServices = <dynamic>[];
      final syncServices = <dynamic>[];
      for (final service in _disposableServices.reversed) {
        if (service is AsyncDisposable) {
          asyncServices.add(service);
        } else {
          syncServices.add(service);
        }
      }
      if (asyncServices.isNotEmpty) {
        for (final service in asyncServices) {
          try {
            if (service.runtimeType.toString() == 'AudioPlayerManager') {
              await service.sessionEndCleanup();
            } else if (service is SessionDisposable) {
              await service.disposeAsync();
            }
          } catch (e) {}
        }
      }
      if (syncServices.isNotEmpty) {
        for (final service in syncServices) {
          try {
            if (service is SessionDisposable) {
              service.dispose();
            } else {
              try {
                service.dispose();
              } catch (disposeError) {}
            }
          } catch (e) {}
        }
      }
      _sessionServices.clear();
      _disposableServices.clear();
      stopwatch.stop();
    } catch (e) {
      stopwatch.stop();
      _sessionServices.clear();
      _disposableServices.clear();
    }
  }
  T get<T extends Object>() {
    if (!inSession) {
      throw StateError('No active session. Call createSessionScope() first.');
    }
    final service = _sessionServices[T];
    if (service == null) {
      throw StateError('Service of type $T not found in session scope');
    }
    return service as T;
  }
  Future<void> _createSessionServices() async {
    try {
      final audioPlayerManager = AudioPlayerManager(
          audioSettings: serviceLocator<IAudioSettings>() // app-scoped
          );
      _sessionServices[AudioPlayerManager] = audioPlayerManager;
      _disposableServices.add(audioPlayerManager);
      final voiceSessionCoordinator = VoiceSessionCoordinator(
        recordingService:
            serviceLocator<IAudioRecordingService>(), // app-scoped
        ttsService: serviceLocator<ITTSService>(), // app-scoped
        wsManager: serviceLocator<IWebSocketAudioManager>(), // app-scoped
        fileManager: serviceLocator<IAudioFileManager>(), // app-scoped
      );
      _sessionServices[VoiceSessionCoordinator] = voiceSessionCoordinator;
      _sessionServices[IVoiceService] =
          voiceSessionCoordinator; // Interface alias
      _disposableServices.add(voiceSessionCoordinator);
    } catch (e) {
      rethrow;
    }
  }
  Future<void> _cleanupPartialServices() async {
    await destroySessionScope();
  }
  void forceCleanup() {
    _sessionServices.clear();
    _disposableServices.clear();
  }
}
