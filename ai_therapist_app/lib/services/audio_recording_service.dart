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
  final SharedRecorderManager _sharedRecorderManager = SharedRecorderManager.instance;
  
  // Mutex to prevent race conditions
  final Mutex _recordingLock = Mutex();
  
  // Stream controllers
  final StreamController<double> _audioLevelController = StreamController<double>.broadcast();
  
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
    _recordingSettings = {
      'encoder': AudioEncoder.aacLc,
      'bitRate': 128000,
      'sampleRate': 44100,
      'numChannels': 1,
    };
  }
  
  @override
  bool get isRecording => _recordingManager.currentState == RecordingState.recording;
  
  @override
  Stream<RecordingState> get recordingStateStream => _recordingManager.recordingStateStream;
  
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
        print('AudioRecordingService already initialized');
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
        print('AudioRecordingService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing AudioRecordingService: $e');
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
        print('🎙️ AudioRecordingService: Starting recording');
      }
      
      // Check if already recording
      if (isRecording) {
        if (kDebugMode) {
          print('🎙️ AudioRecordingService: Already recording, ignoring');
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
        print('🎙️ AudioRecordingService: Recording started successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioRecordingService: Error starting recording: $e');
      }
      rethrow;
    } finally {
      _recordingLock.release();
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
        print('🎙️ AudioRecordingService: Stopping recording');
      }
      
      // Stop audio level monitoring
      _stopAudioLevelMonitoring();
      
      // Stop recording through RecordingManager
      final recordingPath = await _recordingManager.stopRecording();
      
      if (recordingPath != null) {
        _lastRecordingPath = recordingPath;
        
        if (kDebugMode) {
          print('🎙️ AudioRecordingService: Recording stopped, file: $recordingPath');
        }
        
        return recordingPath;
      } else {
        throw Exception('Failed to stop recording - no file path returned');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioRecordingService: Error stopping recording: $e');
      }
      rethrow;
    } finally {
      _recordingLock.release();
    }
  }
  
  @override
  Future<void> pauseRecording() async {
    // Note: The record package doesn't support pause/resume natively
    // This would need to be implemented by stopping and resuming recording
    // For now, we'll throw an unsupported operation exception
    throw UnsupportedError('Pause/resume not supported by underlying recording library');
  }
  
  @override
  Future<void> resumeRecording() async {
    // Note: The record package doesn't support pause/resume natively
    throw UnsupportedError('Pause/resume not supported by underlying recording library');
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
          print('🎙️ AudioRecordingService: No active recording to cancel');
        }
        return;
      }
      
      if (kDebugMode) {
        print('🎙️ AudioRecordingService: Canceling recording');
      }
      
      // Stop audio level monitoring
      _stopAudioLevelMonitoring();
      
      // Stop recording through RecordingManager
      final recordingPath = await _recordingManager.stopRecording();
      
      // Delete the recorded file if it exists
      if (recordingPath != null) {
        try {
          final file = File(recordingPath);
          if (await file.exists()) {
            await file.delete();
            if (kDebugMode) {
              print('🎙️ AudioRecordingService: Deleted canceled recording file');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ AudioRecordingService: Could not delete canceled recording: $e');
          }
        }
      }
      
      _lastRecordingPath = null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioRecordingService: Error canceling recording: $e');
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
        print('🎙️ AudioRecordingService: Microphone permission: $status');
      }
      
      return hasPermission;
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioRecordingService: Error requesting microphone permission: $e');
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
        print('❌ AudioRecordingService: Error checking microphone permission: $e');
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
        _recordingSettings['sampleRate'] = 44100;
        break;
      case 'high':
        _recordingSettings['bitRate'] = 256000;
        _recordingSettings['sampleRate'] = 48000;
        break;
      default:
        if (kDebugMode) {
          print('⚠️ AudioRecordingService: Unknown audio quality: $quality, using medium');
        }
        _audioQuality = 'medium';
        _recordingSettings['bitRate'] = 128000;
        _recordingSettings['sampleRate'] = 44100;
        break;
    }
    
    if (kDebugMode) {
      print('🎙️ AudioRecordingService: Audio quality set to $_audioQuality');
    }
  }
  
  @override
  void setRecordingSettings(Map<String, dynamic> settings) {
    _recordingSettings.addAll(settings);
    
    if (kDebugMode) {
      print('🎙️ AudioRecordingService: Recording settings updated: $_recordingSettings');
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
        final files = recordingsDir.listSync()
            .where((entity) => entity is File && entity.path.endsWith('.m4a'))
            .cast<File>();
        
        int deletedCount = 0;
        
        for (final file in files) {
          try {
            await file.delete();
            deletedCount++;
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ AudioRecordingService: Could not delete ${file.path}: $e');
            }
          }
        }
        
        if (kDebugMode) {
          print('🎙️ AudioRecordingService: Cleaned up $deletedCount recording files');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioRecordingService: Error cleaning up recording files: $e');
      }
    }
  }
  
  /// Start monitoring audio levels during recording
  void _startAudioLevelMonitoring() {
    _stopAudioLevelMonitoring(); // Stop any existing monitoring
    
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!isRecording) {
        timer.cancel();
        return;
      }
      
      // Generate simulated audio level (0.0 to 1.0)
      // In a real implementation, this would get actual audio levels from the recorder
      final level = _generateSimulatedAudioLevel();
      _audioLevelController.add(level);
    });
  }
  
  /// Stop monitoring audio levels
  void _stopAudioLevelMonitoring() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    
    // Send final zero level
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(0.0);
    }
  }
  
  /// Generate simulated audio level for demonstration
  /// In a real implementation, this would interface with the actual recorder
  double _generateSimulatedAudioLevel() {
    // Simple simulation - varies between 0.1 and 0.8
    final randomValue = (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;
    return 0.1 + (randomValue * 0.7);
  }
  
  @override
  void dispose() {
    if (_disposed) return;
    
    if (kDebugMode) {
      print('🎙️ AudioRecordingService: Disposing');
    }
    
    _disposed = true;
    
    // Stop any ongoing recording
    if (isRecording) {
      // Use a fire-and-forget approach for disposal to avoid blocking
      cancelRecording().catchError((e) {
        if (kDebugMode) {
          print('⚠️ AudioRecordingService: Error during disposal recording cancel: $e');
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
        print('⚠️ AudioRecordingService: Error disposing RecordingManager: $e');
      }
    });
    
    if (kDebugMode) {
      print('🎙️ AudioRecordingService: Disposed successfully');
    }
  }
}