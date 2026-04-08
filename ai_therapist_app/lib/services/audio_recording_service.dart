// lib/services/audio_recording_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:mutex/mutex.dart';
import '../di/interfaces/i_audio_recording_service.dart';
import 'recording_manager.dart';
import 'base_voice_service.dart';
import 'path_manager.dart';
class AudioRecordingService implements IAudioRecordingService {
  late final RecordingManager _recordingManager;
  final SharedRecorderManager _sharedRecorderManager =
      SharedRecorderManager.instance;
  final Mutex _recordingLock = Mutex();
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  bool _isInitialized = false;
  bool _disposed = false;
  String? _lastRecordingPath;
  Map<String, dynamic> _recordingSettings = {};
  String _audioQuality = 'medium';
  Timer? _audioLevelTimer;
  AudioRecordingService({required RecordingManager recordingManager}) {
    _recordingManager = recordingManager;
    _initializeDefaultSettings();
  }
  void _initializeDefaultSettings() {
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
      return;
    }
    try {
      await PathManager.instance.init();
      await _sharedRecorderManager.initialize();
      await _recordingManager.initialize();
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not granted');
      }
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<void> startRecording() async {
    if (_disposed) {
      throw StateError('AudioRecordingService has been disposed');
    }
    await _recordingLock.acquire();
    try {
      if (isRecording) {
        return;
      }
      final hasPermission = await hasMicrophonePermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not available');
      }
      await _recordingManager.startRecording();
      _startAudioLevelMonitoring();
    } catch (e) {
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
    await _recordingLock.acquire();
    try {
      _stopAudioLevelMonitoring();
      final recordingPath = await _recordingManager.stopRecording();
      if (recordingPath != null) {
        _lastRecordingPath = recordingPath;
        return recordingPath;
      } else {
        throw Exception('Failed to stop recording - no file path returned');
      }
    } catch (e) {
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
      return null;
    }
    if (_recordingLock.isLocked) {
      return null;
    }
    await _recordingLock.acquire();
    try {
      _stopAudioLevelMonitoring();
      final recordingPath = await _recordingManager.tryStopRecording();
      if (recordingPath != null) {
        _lastRecordingPath = recordingPath;
        return recordingPath;
      } else {
        return null;
      }
    } catch (e) {
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
        return;
      }
      _stopAudioLevelMonitoring();
      if (_recordingManager.isStreaming) {
        await _recordingManager.stopStreaming();
        return;
      }
      final recordingPath = await _recordingManager.stopRecording();
      if (recordingPath != null) {
        try {
          final file = File(recordingPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {}
      }
      _lastRecordingPath = null;
    } catch (e) {
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
      return hasPermission;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<bool> hasMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      return false;
    }
  }
  @override
  void setAudioQuality(String quality) {
    _audioQuality = quality;
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
        _audioQuality = 'medium';
        _recordingSettings['bitRate'] = 128000;
        _recordingSettings['sampleRate'] = 48000;
        break;
    }
  }
  @override
  void setRecordingSettings(Map<String, dynamic> settings) {
    _recordingSettings.addAll(settings);
  }
  @override
  Future<void> cleanupRecordingFiles() async {
    try {
      final cacheDir = PathManager.instance.cacheDir;
      final recordingsDir = Directory('$cacheDir/recordings');
      if (await recordingsDir.exists()) {
        final files = recordingsDir
            .listSync()
            .where((entity) => entity is File && entity.path.endsWith('.m4a'))
            .cast<File>();
        int deletedCount = 0;
        for (final file in files) {
          try {
            await file.delete();
            deletedCount++;
          } catch (e) {}
        }
      }
    } catch (e) {}
  }
  void _startAudioLevelMonitoring() {
    _stopAudioLevelMonitoring(); // Stop any existing monitoring
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }
      _getRealAmplitude().then((level) {
        if (!_audioLevelController.isClosed) {
          _audioLevelController.add(level);
        }
      }).catchError((e) {
      });
    });
  }
  void _stopAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    _amplitudeHistory.clear();
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(0.0);
    }
  }
  final List<double> _amplitudeHistory = [];
  static const int _smoothingWindow = 3;
  Future<double> _getRealAmplitude() async {
    try {
      if (!isRecording) {
        return 0.0;
      }
      final amplitudeData = await _recordingManager.getCurrentAmplitude();
      if (amplitudeData == null) {
        return 0.0;
      }
      if (amplitudeData.current == double.negativeInfinity ||
          amplitudeData.current.isNaN) {
        return 0.0;
      }
      double normalized = (amplitudeData.current + 60.0) / 60.0;
      normalized = normalized.clamp(0.0, 1.0);
      _amplitudeHistory.add(normalized);
      if (_amplitudeHistory.length > _smoothingWindow) {
        _amplitudeHistory.removeAt(0);
      }
      return _amplitudeHistory.reduce((a, b) => a + b) /
          _amplitudeHistory.length;
    } catch (e) {
      return 0.0; // Safe fallback to silence
    }
  }
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (isRecording) {
      cancelRecording().catchError((e) {
      });
    }
    _stopAudioLevelMonitoring();
    _audioLevelController.close();
    _recordingManager.dispose().catchError((e) {
    });
  }
}
