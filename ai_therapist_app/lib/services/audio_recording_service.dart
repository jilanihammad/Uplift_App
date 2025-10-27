// lib/services/audio_recording_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:mutex/mutex.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';

import '../di/interfaces/i_audio_recording_service.dart';
import 'recording_manager.dart';
import 'base_voice_service.dart';
import 'path_manager.dart';

/// AudioRecordingService - Focused service for audio recording operations
///
/// Extracts recording functionality from the monolithic VoiceService into
/// a dedicated, maintainable service focused solely on audio recording.
///
/// Key Features:
/// - Thread-safe recording operations using mutex locks
/// - Proper permission management
/// - Audio level monitoring
/// - State management with streams
/// - Integration with existing RecordingManager
/// - Comprehensive error handling
class AudioRecordingService implements IAudioRecordingService {
  // Recording manager for core recording operations
  late final RecordingManager _recordingManager;

  // Shared recorder manager for hardware access
  final SharedRecorderManager _sharedRecorderManager =
      SharedRecorderManager.instance;

  // Mutex to prevent race conditions
  final Mutex _recordingLock = Mutex();

  // Stream controllers
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();

  // Current state tracking
  bool _isInitialized = false;
  bool _disposed = false;
  String? _lastRecordingPath;
  Map<String, dynamic> _recordingSettings = {};

  // Audio quality configuration
  String _audioQuality = 'medium';

  // Timer for audio level monitoring
  Timer? _audioLevelTimer;

  /// Constructor with required RecordingManager injection
  /// This prevents race conditions by ensuring all services use the same instance
  AudioRecordingService({required RecordingManager recordingManager}) {
    _recordingManager = recordingManager;
    _initializeDefaultSettings();
  }

  /// Initialize default recording settings
  void _initializeDefaultSettings() {
    // Prefer RNNoise-aligned settings: mono 48 kHz, with 44.1 kHz fallback elsewhere
    _recordingSettings = {
      'encoder': AudioEncoder.aacLc,
      'bitRate': 128000,
      'sampleRate': 48000,
      'numChannels': 1,
    };
  }

  @override
  bool get isRecording =>
      _recordingManager.currentState == RecordingState.recording;

  @override
  Stream<RecordingState> get recordingStateStream =>
      _recordingManager.recordingStateStream;

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  bool get isInitialized => _isInitialized;

  @override
  String? get lastRecordingPath => _lastRecordingPath;

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('AudioRecordingService already initialized');
      }
      return;
    }

    try {
      // Initialize PathManager first
      await PathManager.instance.init();

      // Initialize shared recorder manager
      await _sharedRecorderManager.initialize();

      // Initialize recording manager
      await _recordingManager.initialize();

      // Request microphone permissions
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not granted');
      }

      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('AudioRecordingService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing AudioRecordingService: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> startRecording() async {
    if (_disposed) {
      throw StateError('AudioRecordingService has been disposed');
    }

    // Use mutex to prevent concurrent recording operations
    await _recordingLock.acquire();

    try {
      if (kDebugMode) {
        AppLogger.d(' AudioRecordingService: Starting recording');
      }

      // Check if already recording
      if (isRecording) {
        if (kDebugMode) {
          AppLogger.d(' AudioRecordingService: Already recording, ignoring');
        }
        return;
      }

      // Ensure we have permissions
      final hasPermission = await hasMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not available');
      }

      // Start recording through RecordingManager
      await _recordingManager.startRecording();

      // Start audio level monitoring
      _startAudioLevelMonitoring();

      if (kDebugMode) {
        AppLogger.d(' AudioRecordingService: Recording started successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error starting recording: $e');
      }
      rethrow;
    } finally {
      _recordingLock.release();
    }
  }

  @override
  Future<Stream<Uint8List>> startStreaming({
    int sampleRate = 24000,
    int numChannels = 1,
  }) async {
    if (_disposed) {
      throw StateError('AudioRecordingService has been disposed');
    }

    await _recordingLock.acquire();
    try {
      final hasPermission = await hasMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not available');
      }

      final stream = await _recordingManager.startStreaming(
        sampleRate: sampleRate,
        numChannels: numChannels,
      );

      _startAudioLevelMonitoring();
      return stream;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error starting streaming: $e');
      }
      rethrow;
    } finally {
      if (_recordingLock.isLocked) {
        _recordingLock.release();
      }
    }
  }

  @override
  Future<String> stopRecording() async {
    if (_disposed) {
      throw StateError('AudioRecordingService has been disposed');
    }

    // Use mutex to prevent concurrent operations
    await _recordingLock.acquire();

    try {
      if (kDebugMode) {
        AppLogger.d(' AudioRecordingService: Stopping recording');
      }

      // Stop audio level monitoring
      _stopAudioLevelMonitoring();

      // Stop recording through RecordingManager
      final recordingPath = await _recordingManager.stopRecording();

      if (recordingPath != null) {
        _lastRecordingPath = recordingPath;

        if (kDebugMode) {
          AppLogger.d(
              ' AudioRecordingService: Recording stopped, file: $recordingPath');
        }

        return recordingPath;
      } else {
        throw Exception('Failed to stop recording - no file path returned');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error stopping recording: $e');
      }
      rethrow;
    } finally {
      _recordingLock.release();
    }
  }

  @override
  Future<void> stopStreaming() async {
    if (_disposed) {
      return;
    }

    await _recordingLock.acquire();
    try {
      _stopAudioLevelMonitoring();
      await _recordingManager.stopStreaming();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error stopping streaming: $e');
      }
      rethrow;
    } finally {
      if (_recordingLock.isLocked) {
        _recordingLock.release();
      }
    }
  }

  @override
  Future<String?> tryStopRecording() async {
    if (_disposed) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ AudioRecordingService: tryStopRecording called on disposed service');
      }
      return null;
    }

    if (_recordingLock.isLocked) {
      if (kDebugMode) {
        debugPrint(
            '🔄 AudioRecordingService: tryStopRecording - recording operation in progress');
      }
      return null;
    }
    await _recordingLock.acquire();

    try {
      if (kDebugMode) {
        AppLogger.d(
            '🔄 AudioRecordingService: Attempting to stop recording (idempotent)');
      }

      // Stop audio level monitoring
      _stopAudioLevelMonitoring();

      // Try to stop recording through RecordingManager (thread-safe)
      final recordingPath = await _recordingManager.tryStopRecording();

      if (recordingPath != null) {
        _lastRecordingPath = recordingPath;

        if (kDebugMode) {
          AppLogger.d(
              '✅ AudioRecordingService: Recording stopped successfully, file: $recordingPath');
        }

        return recordingPath;
      } else {
        if (kDebugMode) {
          AppLogger.d(
              '✅ AudioRecordingService: Recording already stopped or not recording');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error in tryStopRecording: $e');
      }
      return null; // Never throw
    } finally {
      if (_recordingLock.isLocked) {
        _recordingLock.release();
      }
    }
  }

  @override
  Future<void> pauseRecording() async {
    // Note: The record package doesn't support pause/resume natively
    // This would need to be implemented by stopping and resuming recording
    // For now, we'll throw an unsupported operation exception
    throw UnsupportedError(
        'Pause/resume not supported by underlying recording library');
  }

  @override
  Future<void> resumeRecording() async {
    // Note: The record package doesn't support pause/resume natively
    throw UnsupportedError(
        'Pause/resume not supported by underlying recording library');
  }

  @override
  Future<void> cancelRecording() async {
    if (_disposed) {
      return;
    }

    await _recordingLock.acquire();

    try {
      if (!isRecording) {
        if (kDebugMode) {
          AppLogger.d(' AudioRecordingService: No active recording to cancel');
        }
        return;
      }

      if (kDebugMode) {
        AppLogger.d(' AudioRecordingService: Canceling recording');
      }

      // Stop audio level monitoring
      _stopAudioLevelMonitoring();

      if (_recordingManager.isStreaming) {
        await _recordingManager.stopStreaming();
        return;
      }

      // Stop recording through RecordingManager
      final recordingPath = await _recordingManager.stopRecording();

      // Delete the recorded file if it exists
      if (recordingPath != null) {
        try {
          final file = File(recordingPath);
          if (await file.exists()) {
            await file.delete();
            if (kDebugMode) {
              AppLogger.d(
                  ' AudioRecordingService: Deleted canceled recording file');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '⚠️ AudioRecordingService: Could not delete canceled recording: $e');
          }
        }
      }

      _lastRecordingPath = null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error canceling recording: $e');
      }
      rethrow;
    } finally {
      _recordingLock.release();
    }
  }

  @override
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      final hasPermission = status == PermissionStatus.granted;

      if (kDebugMode) {
        AppLogger.d(' AudioRecordingService: Microphone permission: $status');
      }

      return hasPermission;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '❌ AudioRecordingService: Error requesting microphone permission: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> hasMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '❌ AudioRecordingService: Error checking microphone permission: $e');
      }
      return false;
    }
  }

  @override
  void setAudioQuality(String quality) {
    _audioQuality = quality;

    // Update recording settings based on quality
    switch (quality.toLowerCase()) {
      case 'low':
        _recordingSettings['bitRate'] = 64000;
        _recordingSettings['sampleRate'] = 22050;
        break;
      case 'medium':
        _recordingSettings['bitRate'] = 128000;
        _recordingSettings['sampleRate'] =
            48000; // prefer 48 kHz for RNNoise alignment
        break;
      case 'high':
        _recordingSettings['bitRate'] = 256000;
        _recordingSettings['sampleRate'] = 48000;
        break;
      default:
        if (kDebugMode) {
          debugPrint(
              '⚠️ AudioRecordingService: Unknown audio quality: $quality, using medium');
        }
        _audioQuality = 'medium';
        _recordingSettings['bitRate'] = 128000;
        _recordingSettings['sampleRate'] = 48000;
        break;
    }

    if (kDebugMode) {
      AppLogger.d(
          ' AudioRecordingService: Audio quality set to $_audioQuality');
    }
  }

  @override
  void setRecordingSettings(Map<String, dynamic> settings) {
    _recordingSettings.addAll(settings);

    if (kDebugMode) {
      AppLogger.d(
          ' AudioRecordingService: Recording settings updated: $_recordingSettings');
    }
  }

  @override
  Future<void> cleanupRecordingFiles() async {
    try {
      // Get recording directory
      final cacheDir = PathManager.instance.cacheDir;
      final recordingsDir = Directory('$cacheDir/recordings');

      if (await recordingsDir.exists()) {
        // List all recording files
        final files = recordingsDir
            .listSync()
            .where((entity) => entity is File && entity.path.endsWith('.m4a'))
            .cast<File>();

        int deletedCount = 0;

        for (final file in files) {
          try {
            await file.delete();
            deletedCount++;
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '⚠️ AudioRecordingService: Could not delete ${file.path}: $e');
            }
          }
        }

        if (kDebugMode) {
          AppLogger.d(
              ' AudioRecordingService: Cleaned up $deletedCount recording files');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ AudioRecordingService: Error cleaning up recording files: $e');
      }
    }
  }

  /// Start monitoring audio levels during recording
  void _startAudioLevelMonitoring() {
    _stopAudioLevelMonitoring(); // Stop any existing monitoring

    // Phase 3: Real amplitude monitoring at 20Hz (50ms intervals)
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }

      // Get real amplitude from microphone (async, fire-and-forget)
      _getRealAmplitude().then((level) {
        if (!_audioLevelController.isClosed) {
          _audioLevelController.add(level);
        }
      }).catchError((e) {
        // Ignore errors, will fall back to 0.0 in getRealAmplitude
      });
    });
  }

  /// Stop monitoring audio levels
  void _stopAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;

    // Phase 3: Clear amplitude history to avoid stale data
    _amplitudeHistory.clear();

    // Send final zero level
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(0.0);
    }
  }

  // Phase 3: Amplitude smoothing variables
  final List<double> _amplitudeHistory = [];
  static const int _smoothingWindow = 3;

  /// Get real amplitude from microphone with error handling and smoothing
  Future<double> _getRealAmplitude() async {
    try {
      if (!isRecording) {
        return 0.0;
      }

      // Get amplitude from the recording manager
      final amplitudeData = await _recordingManager.getCurrentAmplitude();
      if (amplitudeData == null) {
        return 0.0;
      }

      if (amplitudeData.current == double.negativeInfinity ||
          amplitudeData.current.isNaN) {
        return 0.0;
      }

      // Normalize dB to 0.0-1.0 range (typical range: -60dB to 0dB for speech)
      double normalized = (amplitudeData.current + 60.0) / 60.0;
      normalized = normalized.clamp(0.0, 1.0);

      // Add to smoothing window
      _amplitudeHistory.add(normalized);
      if (_amplitudeHistory.length > _smoothingWindow) {
        _amplitudeHistory.removeAt(0);
      }

      // Return moving average
      return _amplitudeHistory.reduce((a, b) => a + b) /
          _amplitudeHistory.length;
    } catch (e) {
      if (kDebugMode) {
        // Only log occasionally to avoid spam
        if (DateTime.now().millisecondsSinceEpoch % 1000 < 100) {
          debugPrint(
              'AudioRecordingService: Error getting amplitude: $e, falling back to silence');
        }
      }
      return 0.0; // Safe fallback to silence
    }
  }

  @override
  void dispose() {
    if (_disposed) return;

    if (kDebugMode) {
      AppLogger.d(' AudioRecordingService: Disposing');
    }

    _disposed = true;

    // Stop any ongoing recording
    if (isRecording) {
      // Use a fire-and-forget approach for disposal to avoid blocking
      cancelRecording().catchError((e) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ AudioRecordingService: Error during disposal recording cancel: $e');
        }
      });
    }

    // Stop audio level monitoring
    _stopAudioLevelMonitoring();

    // Close stream controllers
    _audioLevelController.close();

    // Dispose recording manager
    _recordingManager.dispose().catchError((e) {
      if (kDebugMode) {
        debugPrint('⚠️ AudioRecordingService: Error disposing RecordingManager: $e');
      }
    });

    if (kDebugMode) {
      AppLogger.d(' AudioRecordingService: Disposed successfully');
    }
  }
}
