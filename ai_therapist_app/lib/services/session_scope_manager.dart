// lib/services/session_scope_manager.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

// Service interfaces
import '../di/interfaces/i_voice_service.dart';
import '../di/interfaces/i_audio_recording_service.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_websocket_audio_manager.dart';
import '../di/interfaces/i_audio_file_manager.dart';
import '../di/interfaces/i_audio_settings.dart';

// Service implementations
import 'voice_session_coordinator.dart';
import 'auto_listening_coordinator.dart';
import 'audio_player_manager.dart';
import 'voice_service.dart';
import 'recording_manager.dart';
import '../utils/disposable.dart';
import '../di/service_locator.dart';

/// Manages session-scoped services using factory pattern.
/// Creates fresh instances for each therapy session to prevent state bleed
/// and automatically handles disposal when sessions end.
class SessionScopeManager {
  final Map<Type, dynamic> _sessionServices = {};
  final List<dynamic> _disposableServices = [];
  
  /// Whether a session is currently active
  bool get inSession => _sessionServices.isNotEmpty;
  
  /// Creates new session-scoped service instances.
  /// Throws [StateError] if a session is already in progress.
  Future<void> createSessionScope() async {
    // Re-entrancy guard
    if (inSession) {
      throw StateError('Session already in progress. Call destroySessionScope() first.');
    }
    
    try {
      await _createSessionServices();
      
      if (kDebugMode) {
        debugPrint('[SessionScope] Created session scope with ${_sessionServices.length} services');
      }
      
    } catch (e) {
      // Error handling during creation - cleanup partial state
      if (kDebugMode) {
        debugPrint('[SessionScope] Error during scope creation: $e');
      }
      
      await _cleanupPartialServices();
      rethrow;
    }
  }
  
  /// Destroys the current session scope and disposes all services.
  /// Safe to call multiple times or when no session is active.
  /// Has overall timeout protection to prevent disposal from hanging.
  Future<void> destroySessionScope() async {
    if (!inSession) return;
    
    // Add overall timeout protection for disposal
    try {
      await Future.any([
        _performDisposal(),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException('Session scope disposal timeout', const Duration(seconds: 10));
        }),
      ]);
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionScope] Disposal timed out: $e');
      }
      
      // Force cleanup on timeout
      forceCleanup();
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionScope] Disposal failed: $e');
      }
      
      // Force cleanup on any error
      forceCleanup();
      rethrow;
    }
  }
  
  /// Internal disposal implementation with proper error handling
  Future<void> _performDisposal() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      if (kDebugMode) {
        debugPrint('[SessionScope] Destroying session scope with ${_disposableServices.length} disposable services');
      }
      
      // Group services by disposal type for optimal cleanup order
      final asyncServices = <dynamic>[];
      final syncServices = <dynamic>[];
      
      for (final service in _disposableServices.reversed) {
        if (service is AsyncDisposable) {
          asyncServices.add(service);
        } else {
          syncServices.add(service);
        }
      }
      
      // Dispose async services first (AudioPlayerManager, etc.) with proper timing
      if (asyncServices.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[SessionScope] Disposing ${asyncServices.length} async services');
        }
        
        for (final service in asyncServices) {
          try {
            // Special handling for AudioPlayerManager session cleanup
            if (service.runtimeType.toString() == 'AudioPlayerManager') {
              // Use session-specific cleanup for proper TTS state management
              await service.sessionEndCleanup();
              if (kDebugMode) {
                debugPrint('[SessionScope] AudioPlayerManager session cleanup completed');
              }
            } else if (service is SessionDisposable) {
              await service.disposeAsync();
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[SessionScope] Error async disposing ${service.runtimeType}: $e');
            }
            // Continue with other services even if one fails
          }
        }
      }
      
      // Then dispose sync services  
      if (syncServices.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[SessionScope] Disposing ${syncServices.length} sync services');
        }
        
        for (final service in syncServices) {
          try {
            if (service is SessionDisposable) {
              service.dispose();
            } else {
              // Try calling dispose method dynamically for legacy services
              try {
                service.dispose();
              } catch (disposeError) {
                if (kDebugMode) {
                  debugPrint('[SessionScope] Service ${service.runtimeType} does not have dispose method: $disposeError');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[SessionScope] Error disposing service ${service.runtimeType}: $e');
            }
          }
        }
      }
      
      _sessionServices.clear();
      _disposableServices.clear();
      
      stopwatch.stop();
      
      if (kDebugMode) {
        debugPrint('[SessionScope] Session scope destroyed in ${stopwatch.elapsedMilliseconds}ms');
      }
      
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('[SessionScope] Error during scope destruction (${stopwatch.elapsedMilliseconds}ms): $e');
      }
      
      // Force cleanup even on error to prevent stuck states
      _sessionServices.clear();
      _disposableServices.clear();
    }
  }
  
  /// Gets a service instance from the current session scope.
  /// Throws [StateError] if no session is active.
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
  
  /// Create all session-scoped service instances.
  /// These services get fresh instances for each session.
  Future<void> _createSessionServices() async {
    try {
      // AudioPlayerManager - session-specific audio playback (create first)
      if (kDebugMode) {
        debugPrint('[SessionScope] Creating AudioPlayerManager');
      }
      
      final audioPlayerManager = AudioPlayerManager(
        audioSettings: serviceLocator<IAudioSettings>() // app-scoped
      );
      _sessionServices[AudioPlayerManager] = audioPlayerManager;
      _disposableServices.add(audioPlayerManager);
      
      // AutoListeningCoordinator - VAD and auto-listening management
      if (kDebugMode) {
        debugPrint('[SessionScope] Creating AutoListeningCoordinator');
      }
      
      final autoListeningCoordinator = AutoListeningCoordinator(
        audioPlayerManager: audioPlayerManager, // session-scoped
        recordingManager: serviceLocator<RecordingManager>(), // app-scoped
        voiceService: serviceLocator<VoiceService>(), // app-scoped
      );
      _sessionServices[AutoListeningCoordinator] = autoListeningCoordinator;
      _disposableServices.add(autoListeningCoordinator);
      
      // VoiceSessionCoordinator - main voice session orchestrator
      if (kDebugMode) {
        debugPrint('[SessionScope] Creating VoiceSessionCoordinator');
      }
      
      final voiceSessionCoordinator = VoiceSessionCoordinator(
        recordingService: serviceLocator<IAudioRecordingService>(), // app-scoped
        ttsService: serviceLocator<ITTSService>(),                   // app-scoped  
        wsManager: serviceLocator<IWebSocketAudioManager>(),         // app-scoped
        fileManager: serviceLocator<IAudioFileManager>(),            // app-scoped
      );
      _sessionServices[VoiceSessionCoordinator] = voiceSessionCoordinator;
      _sessionServices[IVoiceService] = voiceSessionCoordinator; // Interface alias
      _disposableServices.add(voiceSessionCoordinator);
      
      if (kDebugMode) {
        debugPrint('[SessionScope] Created ${_sessionServices.length} session services');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionScope] Error creating session services: $e');
      }
      rethrow;
    }
  }
  
  /// Cleanup partially created services on error
  Future<void> _cleanupPartialServices() async {
    await destroySessionScope();
  }
  
  /// Force cleanup for emergency situations.
  /// Use only when normal cleanup fails.
  void forceCleanup() {
    if (kDebugMode) {
      debugPrint('[SessionScope] Force cleanup initiated');
    }
    
    _sessionServices.clear();
    _disposableServices.clear();
  }
}