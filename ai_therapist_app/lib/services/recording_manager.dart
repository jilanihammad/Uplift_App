import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';
import 'base_voice_service.dart';
import 'path_manager.dart';

/// Shared recorder manager to prevent dual AudioRecorder instances
/// Used by both RecordingManager and VADManager to avoid conflicts
class SharedRecorderManager {
  static final SharedRecorderManager _instance =
      SharedRecorderManager._internal();
  static SharedRecorderManager get instance => _instance;

  late final AudioRecorder _recorder;
  bool _isInitialized = false;
  String? _currentUser; // Track which service is using the recorder

  SharedRecorderManager._internal();

  /// Initialize the shared recorder
  Future<void> initialize() async {
    if (_isInitialized) return;

    _recorder = AudioRecorder();
    _isInitialized = true;

    if (kDebugMode) {
      debugPrint(
          '🎙️ SharedRecorderManager: Initialized single AudioRecorder instance');
    }
  }

  /// Request exclusive access to the recorder
  Future<bool> requestAccess(String userId) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Check if already in use by someone else
    if (_currentUser != null && _currentUser != userId) {
      if (await _recorder.isRecording()) {
        if (kDebugMode) {
          debugPrint(
              '🎙️ SharedRecorderManager: Recorder busy with $_currentUser, denying $userId');
        }
        return false;
      } else {
        // Previous user finished, allow new user
        _currentUser = userId;
        if (kDebugMode) {
          debugPrint(
              '🎙️ SharedRecorderManager: Previous session ended, granting access to $userId');
        }
        return true;
      }
    }

    // Grant access
    _currentUser = userId;
    if (kDebugMode) {
      AppLogger.d(' SharedRecorderManager: Granted access to $userId');
    }
    return true;
  }

  /// Release access to the recorder
  void releaseAccess(String userId) {
    if (_currentUser == userId) {
      _currentUser = null;
      if (kDebugMode) {
        AppLogger.d(' SharedRecorderManager: Released access from $userId');
      }
    }
  }

  /// Get the shared recorder instance (only if you have access)
  AudioRecorder? getRecorder(String userId) {
    if (_currentUser != userId) {
      if (kDebugMode) {
        debugPrint(
            '🎙️ SharedRecorderManager: Access denied to $userId, current user: $_currentUser');
      }
      return null;
    }
    return _recorder;
  }

  /// Check if recorder is currently in use
  bool get isInUse => _currentUser != null;

  /// Get current user
  String? get currentUser => _currentUser;
}

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
  // Use shared recorder instead of creating our own
  static const String _userId = 'RecordingManager';
  AudioRecorder? get _recorder =>
      SharedRecorderManager.instance.getRecorder(_userId);

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

  // RACE CONDITION FIX: Track files pending transcription to prevent collision
  final Set<String> _pendingTranscriptionPaths = <String>{};

  // Add start time tracking
  DateTime? _recordingStartTime;

  // RACE CONDITION FIX: Atomic protection for stopRecording
  bool _isStopping = false;

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
    // Request access to shared recorder
    final hasAccess =
        await SharedRecorderManager.instance.requestAccess(_userId);
    if (!hasAccess) {
      _errorController.add('Cannot access recorder - already in use');
      _updateState(RecordingState.error);
      return;
    }

    final recorder = _recorder;
    if (recorder == null) {
      _errorController.add('Recorder not available');
      _updateState(RecordingState.error);
      return;
    }

    if (await recorder.hasPermission() == false) {
      _errorController.add('Microphone permission not granted');
      _updateState(RecordingState.error);
      SharedRecorderManager.instance.releaseAccess(_userId);
      return;
    }

    final isRecording = await recorder.isRecording();
    if (isRecording) {
      if (kDebugMode) {
        debugPrint('Already recording, ignoring startRecording call');
      }
      return;
    }

    try {
      // Create a unique file path for the recording
      final String uuid = const Uuid().v4();
      final String filePath = PathManager.instance.recordingFile(uuid);

      // 🚨 CORRUPTION DIAGNOSTIC - Verify path is still clean after PathManager
      debugPrint('🛡️ RecordingManager.startRecording() received path: $filePath');

      // Configure recording: prefer mono 48 kHz to align with RNNoise
      // Fallback to 44.1 kHz on devices that don't support 48 kHz
      try {
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            numChannels: 1,
            bitRate: 128000,
            sampleRate: 48000,
          ),
          path: filePath,
        );
        if (kDebugMode) {
          AppLogger.d(
              ' RecordingManager: Started recording at 48 kHz mono (preferred)');
        }
      } on Exception catch (primaryError) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ RecordingManager: 48 kHz start failed ($primaryError), retrying at 44.1 kHz');
        }
        // Retry with 44.1 kHz (widely supported)
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            numChannels: 1,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );
        if (kDebugMode) {
          AppLogger.d(
              ' RecordingManager: Started recording at 44.1 kHz mono (fallback)');
        }
      }

      _lastRecordedPath = filePath;

      // 🚨 CORRUPTION DIAGNOSTIC - Check if path corrupted after storing
      debugPrint(
          '🛡️ RecordingManager._lastRecordedPath stored as: $_lastRecordedPath');

      _recordingStartTime = DateTime.now(); // Track start time
      _updateState(RecordingState.recording);

      if (kDebugMode) {
        debugPrint('⏺️ Recording started at path: $filePath');
      }
    } catch (e) {
      _errorController.add('Error starting recording: $e');
      _updateState(RecordingState.error);
      if (kDebugMode) {
        debugPrint('Error starting recording: $e');
      }
    }
  }

  /// Stops the current recording session if active.
  ///
  /// Returns the path to the recorded file, or null if not recording.
  /// Throws [NotRecordingException] if called when not recording.
  Future<String?> stopRecording() async {
    // RACE CONDITION FIX: Atomic stop protection (prevents overlapping releases)
    // Double-stop guard: Early return if already stopping
    if (_isStopping) {
      if (kDebugMode) {
        debugPrint(
            '🛡️ RecordingManager: Already stopping, ignoring duplicate stopRecording call');
      }
      return null;
    }

    _isStopping = true;

    try {
      final recorder = _recorder;
      if (recorder == null) {
        _errorController.add('Recorder not available');
        throw NotRecordingException('Recorder not available');
      }

      final isRecording = await recorder.isRecording();
      if (!isRecording) {
        _errorController.add('Recorder is not recording');
        if (kDebugMode) {
          debugPrint('⚠️ Stop recording called but recorder was not recording');
        }
        // Release access and throw error
        SharedRecorderManager.instance.releaseAccess(_userId);
        throw NotRecordingException();
      }

      return await _performStopRecording(recorder);
    } finally {
      _isStopping = false;
    }
  }

  /// Internal stop recording implementation
  Future<String?> _performStopRecording(AudioRecorder recorder) async {
    try {
      _updateState(RecordingState.processing);

      // 🚨 CORRUPTION DIAGNOSTIC - Check path before stopping
      debugPrint(
          '🛡️ RecordingManager.stopRecording() _lastRecordedPath BEFORE stop: $_lastRecordedPath');

      // Stop recording - but don't trust the returned path as it may be corrupted
      await recorder.stop();

      // Release access to shared recorder
      SharedRecorderManager.instance.releaseAccess(_userId);

      // 🚨 CORRUPTION DIAGNOSTIC - Check path after stopping
      debugPrint(
          '🛡️ RecordingManager.stopRecording() _lastRecordedPath AFTER stop: $_lastRecordedPath');

      // Use our stored clean path from PathManager instead of the returned path
      if (_lastRecordedPath == null) {
        throw Exception('No recording path available - this should not happen');
      }

      _updateState(RecordingState.stopped);
      _recordingStartTime = null; // Reset start time

      if (kDebugMode) {
        debugPrint('⏹️ Recording stopped, file saved at: $_lastRecordedPath');
      }

      return _lastRecordedPath!;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      _updateState(RecordingState.error);
      if (kDebugMode) {
        debugPrint('❌ Error stopping recording: $e');
      }
      return null;
    }
  }

  /// Thread-safe idempotent recording stop that never throws
  /// Returns null if already stopped or operation in progress
  Future<String?> tryStopRecording() async {
    // Quick fast path - already stopping or nothing to stop
    if (_isStopping) {
      if (kDebugMode) {
        debugPrint(
            '🔄 RecordingManager.tryStopRecording(): Operation already in flight');
      }
      return null;
    }

    if (_lastRecordedPath == null) {
      if (kDebugMode) {
        debugPrint('✅ RecordingManager.tryStopRecording(): Already stopped');
      }
      return null;
    }

    // Set flag to prevent concurrent operations
    _isStopping = true;

    try {
      final recorder = _recorder;
      if (recorder == null) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ RecordingManager.tryStopRecording(): Recorder not available');
        }
        return null;
      }

      final isRecording = await recorder.isRecording();
      if (!isRecording) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ RecordingManager.tryStopRecording(): Recorder not recording');
        }
        // Still clean up and return null
        SharedRecorderManager.instance.releaseAccess(_userId);
        return null;
      }

      // Cache path before clearing for return value
      final completedFile = _lastRecordedPath;

      _updateState(RecordingState.processing);

      if (kDebugMode) {
        debugPrint(
            '🛡️ RecordingManager.tryStopRecording() completedFile BEFORE stop: $completedFile');
      }

      // Stop recording
      await recorder.stop();

      // Release access to shared recorder
      SharedRecorderManager.instance.releaseAccess(_userId);

      if (kDebugMode) {
        debugPrint(
            '🛡️ RecordingManager.tryStopRecording() completedFile AFTER stop: $completedFile');
      }

      // Handle MPEG4Writer short-circuit case
      if (completedFile != null && !io.File(completedFile).existsSync()) {
        if (kDebugMode) {
          debugPrint('⚠️ MPEG4Writer short-circuited - no file created');
        }
        _lastRecordedPath = null;
        _updateState(RecordingState.stopped);
        _recordingStartTime = null;
        return null;
      }

      // Clear path after successful completion
      _lastRecordedPath = null;
      _updateState(RecordingState.stopped);
      _recordingStartTime = null;

      if (kDebugMode) {
        debugPrint(
            '⏹️ Recording stopped successfully, file saved at: $completedFile');
      }

      return completedFile;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      _updateState(RecordingState.error);
      if (kDebugMode) {
        debugPrint('❌ Error in tryStopRecording: $e');
      }
      // Don't clear path on error - may need for retry
      return null;
    } finally {
      // Always clear the flag to prevent deadlock
      _isStopping = false;
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

  /// RACE CONDITION FIX: Mark file as pending transcription to prevent path reuse
  void markFileAsPendingTranscription(String filePath) {
    _pendingTranscriptionPaths.add(filePath);
    // Clear _lastRecordedPath to prevent reuse during async transcription
    if (_lastRecordedPath == filePath) {
      _lastRecordedPath = null;
    }
    if (kDebugMode) {
      debugPrint('🛡️ RecordingManager: Marked $filePath as pending transcription');
    }
  }

  /// RACE CONDITION FIX: Mark file transcription as complete and allow cleanup
  void markTranscriptionComplete(String filePath) {
    _pendingTranscriptionPaths.remove(filePath);
    if (kDebugMode) {
      debugPrint(
          '🛡️ RecordingManager: Transcription complete for $filePath, can be cleaned up');
    }
  }

  /// Get list of files pending transcription (for debugging)
  Set<String> get pendingTranscriptionPaths =>
      Set.from(_pendingTranscriptionPaths);

  /// Get current microphone amplitude (for audio level monitoring)
  /// Returns null if not recording or recorder unavailable
  Future<Amplitude?> getCurrentAmplitude() async {
    final recorder = _recorder;
    if (recorder == null || _currentState != RecordingState.recording) {
      return null;
    }

    try {
      return await recorder.getAmplitude();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('RecordingManager: Error getting amplitude: $e');
      }
      return null;
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    final recorder = _recorder;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (e) {
        // Ignore errors on dispose
      }
    }
    // Release access to shared recorder
    SharedRecorderManager.instance.releaseAccess(_userId);

    await _recordingStateController.close();
    await _errorController.close();
  }
}
