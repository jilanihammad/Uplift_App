import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'base_voice_service.dart';

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
      final Directory tempDir = await getTemporaryDirectory();
      final String uuid = const Uuid().v4();
      final String filePath = '${tempDir.path}/$uuid.m4a';

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

  // Stop recording audio
  Future<String> stopRecording() async {
    final isRecording = await _recorder.isRecording();
    if (!isRecording) {
      _errorController.add('Recorder is not recording');
      if (kDebugMode) {
        print('⚠️ Stop recording called but recorder was not recording');
      }
      return '';
    }

    try {
      _updateState(RecordingState.processing);

      // Stop recording
      final path = await _recorder.stop();

      if (path == null) {
        throw Exception('Recording path is null after stopping recorder');
      }

      _lastRecordedPath = path;
      _updateState(RecordingState.stopped);

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
      return '';
    }
  }

  // Update the recording state and notify listeners
  void _updateState(RecordingState state) {
    _currentState = state;
    _recordingStateController.add(state);
  }

  // Clean up resources
  Future<void> dispose() async {
    await _recorder.stop();
    await _recordingStateController.close();
    await _errorController.close();
  }
}
