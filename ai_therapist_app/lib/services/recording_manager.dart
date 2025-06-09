import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'base_voice_service.dart';
import 'path_manager.dart';

// Add at the very top of the file, before RecordingManager
class NotRecordingException implements Exception {
  final String message;
  NotRecordingException([this.message = 'Recorder is not recording']);
  @override
  String toString() => 'NotRecordingException: $message';
}

/// Manages audio recording functionality
///
/// Responsible for starting/stopping recording, handling permissions,
/// and managing recording state
class RecordingManager {
  // Recording instance
  final AudioRecorder _recorder = AudioRecorder();

  // Stream controllers
  final StreamController<RecordingState> _recordingStateController =
      StreamController<RecordingState>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  // Streams for external components to listen to
  Stream<RecordingState> get recordingStateStream =>
      _recordingStateController.stream;
  Stream<String?> get errorStream => _errorController.stream;

  // Current recording state
  RecordingState _currentState = RecordingState.stopped;
  RecordingState get currentState => _currentState;

  // Recorded audio file path
  String? _lastRecordedPath;
  String? get lastRecordedPath => _lastRecordedPath;

  // Add start time tracking
  DateTime? _recordingStartTime;

  // Constructor
  RecordingManager();

  // Initialize the recording manager
  Future<void> initialize() async {
    try {
      await requestPermissions();
    } catch (e) {
      _errorController.add('Failed to initialize recording: $e');
      _updateState(RecordingState.error);
    }
  }

  // Request necessary permissions
  Future<bool> requestPermissions() async {
    try {
      final status = await Permission.microphone.request();
      final hasPermission = status == PermissionStatus.granted;

      if (!hasPermission) {
        _errorController.add('Microphone permission not granted');
        return false;
      }

      return true;
    } catch (e) {
      _errorController.add('Error requesting microphone permission: $e');
      return false;
    }
  }

  // Start recording audio
  Future<void> startRecording() async {
    if (await _recorder.hasPermission() == false) {
      _errorController.add('Microphone permission not granted');
      _updateState(RecordingState.error);
      return;
    }

    final isRecording = await _recorder.isRecording();
    if (isRecording) {
      if (kDebugMode) {
        print('Already recording, ignoring startRecording call');
      }
      return;
    }

    try {
      // Create a unique file path for the recording
      final String uuid = const Uuid().v4();
      final String filePath = PathManager.instance.recordingFile(uuid);

      // 🚨 CORRUPTION DIAGNOSTIC - Verify path is still clean after PathManager
      print('🛡️ RecordingManager.startRecording() received path: $filePath');

      // Configure recording
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      _lastRecordedPath = filePath;

      // 🚨 CORRUPTION DIAGNOSTIC - Check if path corrupted after storing
      print(
          '🛡️ RecordingManager._lastRecordedPath stored as: $_lastRecordedPath');

      _recordingStartTime = DateTime.now(); // Track start time
      _updateState(RecordingState.recording);

      if (kDebugMode) {
        print('⏺️ Recording started at path: $filePath');
      }
    } catch (e) {
      _errorController.add('Error starting recording: $e');
      _updateState(RecordingState.error);
      if (kDebugMode) {
        print('Error starting recording: $e');
      }
    }
  }

  /// Stops the current recording session if active.
  ///
  /// Returns the path to the recorded file, or null if not recording.
  /// Throws [NotRecordingException] if called when not recording.
  Future<String?> stopRecording() async {
    final isRecording = await _recorder.isRecording();
    if (!isRecording) {
      _errorController.add('Recorder is not recording');
      if (kDebugMode) {
        print('⚠️ Stop recording called but recorder was not recording');
      }
      // Throw a typed error and return null
      throw NotRecordingException();
    }

    try {
      _updateState(RecordingState.processing);

      // 🚨 CORRUPTION DIAGNOSTIC - Check path before stopping
      print(
          '🛡️ RecordingManager.stopRecording() _lastRecordedPath BEFORE stop: $_lastRecordedPath');

      // Stop recording - but don't trust the returned path as it may be corrupted
      await _recorder.stop();

      // 🚨 CORRUPTION DIAGNOSTIC - Check path after stopping
      print(
          '🛡️ RecordingManager.stopRecording() _lastRecordedPath AFTER stop: $_lastRecordedPath');

      // Use our stored clean path from PathManager instead of the returned path
      if (_lastRecordedPath == null) {
        throw Exception('No recording path available - this should not happen');
      }

      _updateState(RecordingState.stopped);
      _recordingStartTime = null; // Reset start time

      if (kDebugMode) {
        print('⏹️ Recording stopped, file saved at: $_lastRecordedPath');
      }

      return _lastRecordedPath!;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      _updateState(RecordingState.error);
      if (kDebugMode) {
        print('❌ Error stopping recording: $e');
      }
      return null;
    }
  }

  // Update the recording state and notify listeners
  void _updateState(RecordingState state) {
    _currentState = state;
    _recordingStateController.add(state);
  }

  // Add elapsed getter
  Duration get elapsed {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  // Clean up resources
  Future<void> dispose() async {
    await _recorder.stop();
    await _recordingStateController.close();
    await _errorController.close();
  }
}
