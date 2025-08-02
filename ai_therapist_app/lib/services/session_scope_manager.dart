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
import 'websocket_audio_manager.dart';
import '../data/datasources/remote/api_client.dart';
import '../utils/disposable.dart';
import '../di/service_locator.dart';
import '../utils/app_logger.dart';

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
    
    // ENHANCED: Track session initialization latency
    final initStopwatch = Stopwatch()..start();
    
    try {
      await _createSessionServices();
      
      initStopwatch.stop();
      
      if (kDebugMode) {
        debugPrint('[SessionScope] Created session scope with ${_sessionServices.length} services');
      }
      
      // Track successful session initialization
      AppLogger.trackSessionInitLatency(initStopwatch.elapsed);
      
    } catch (e) {
      initStopwatch.stop();
      
      // Error handling during creation - cleanup partial state
      if (kDebugMode) {
        debugPrint('[SessionScope] Error during scope creation: $e');
      }
      
      // Track failed initialization
      AppLogger.trackDisposalError('SessionScope', 'Init failed: $e');
      
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
          throw TimeoutException('Session scope disposal timeout');
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
      
      // ENHANCED: Dispose async services concurrently with Future.wait for better performance
      if (asyncServices.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[SessionScope] Disposing ${asyncServices.length} async services concurrently');
        }
        
        final disposalFutures = <Future<void>>[];
        
        for (final service in asyncServices) {
          final serviceName = service.runtimeType.toString();
          
          if (serviceName == 'AudioPlayerManager') {
            // Special handling for AudioPlayerManager session cleanup
            disposalFutures.add(
              service.sessionEndCleanup().catchError((e) {
                if (kDebugMode) {
                  debugPrint('[SessionScope] Error in AudioPlayerManager cleanup: $e');
                }
                // Don't rethrow - continue with other services
                return Future.value();
              })
            );
          } else if (service is SessionDisposable) {
            disposalFutures.add(
              service.disposeAsync().catchError((e) {
                if (kDebugMode) {
                  debugPrint('[SessionScope] Error async disposing $serviceName: $e');
                }
                // Don't rethrow - continue with other services
                return Future.value();
              })
            );
          }
        }
        
        // Wait for all async disposals to complete before proceeding
        if (disposalFutures.isNotEmpty) {
          final asyncStopwatch = Stopwatch()..start();
          await Future.wait(disposalFutures);
          asyncStopwatch.stop();
          
          if (kDebugMode) {
            debugPrint('[SessionScope] All async services disposed successfully');
          }
          
          // Track async disposal performance
          AppLogger.trackAsyncDisposalTime(asyncStopwatch.elapsed, disposalFutures.length);
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
      
      // ENHANCED FIX: Clean up service registrations to prevent dead object access
      if (kDebugMode) {
        debugPrint('[SessionScope] Cleaning up DI registrations for fresh session');
      }
      
      // Reset VoiceService singleton state for clean session transition
      try {
        final voiceService = serviceLocator<VoiceService>();
        await voiceService.resetSessionState();
        debugPrint('[SessionScope] VoiceService state reset for session cleanup');
      } catch (e) {
        debugPrint('[SessionScope] Error resetting VoiceService state: $e');
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
      
      // VoiceService is now a singleton and not session-scoped
      // It will be shared across sessions but we need to reset its state between sessions
      
      // AutoListeningCoordinator - VAD and auto-listening management  
      if (kDebugMode) {
        debugPrint('[SessionScope] Creating AutoListeningCoordinator');
      }
      
      final autoListeningCoordinator = AutoListeningCoordinator(
        audioPlayerManager: audioPlayerManager, // session-scoped
        recordingManager: serviceLocator<RecordingManager>(), // app-scoped
        voiceService: serviceLocator<VoiceService>(), // app-scoped singleton
      );
      _sessionServices[AutoListeningCoordinator] = autoListeningCoordinator;
      _disposableServices.add(autoListeningCoordinator);
      
      // VoiceSessionCoordinator - main voice session orchestrator
      if (kDebugMode) {
        debugPrint('[SessionScope] Creating VoiceSessionCoordinator');
      }
      
      // Create fresh WebSocketAudioManager for this session (to avoid disposed instance issue)
      final sessionWebSocketManager = WebSocketAudioManager(
        apiClient: serviceLocator<ApiClient>(),
      );
      _sessionServices[IWebSocketAudioManager] = sessionWebSocketManager;
      _disposableServices.add(sessionWebSocketManager);
      
      final voiceSessionCoordinator = VoiceSessionCoordinator(
        recordingService: serviceLocator<IAudioRecordingService>(), // app-scoped
        ttsService: serviceLocator<ITTSService>(),                   // app-scoped  
        wsManager: sessionWebSocketManager,                          // session-scoped (fresh instance)
        fileManager: serviceLocator<IAudioFileManager>(),            // app-scoped
        voiceService: serviceLocator<VoiceService>(),                // app-scoped singleton
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