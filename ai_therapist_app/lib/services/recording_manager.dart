import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../utils/box_logger.dart';
import '../utils/log_channels.dart';
import 'base_voice_service.dart';
import 'path_manager.dart';
class SharedRecorderManager {
  static final SharedRecorderManager _instance =
      SharedRecorderManager._internal();
  static SharedRecorderManager get instance => _instance;
  late final AudioRecorder _recorder;
  bool _isInitialized = false;
  String? _currentUser; // Track which service is using the recorder
  bool get _recordingTraceEnabled => kDebugMode && LogChannels.recordingTrace;
  void _logRecorder(
    String message, {
    String emoji = '🎙️',
    Map<String, String>? details,
    bool trace = false,
  }) {
    if (trace && !_recordingTraceEnabled) return;
    BoxLogger.debug(emoji, 'SharedRecorder', message, details: details);
  }
  SharedRecorderManager._internal();
  Future<void> initialize() async {
    if (_isInitialized) return;
    _recorder = AudioRecorder();
    _isInitialized = true;
    _logRecorder('Initialized AudioRecorder instance', trace: true);
  }
  Future<bool> requestAccess(String userId) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentUser != null && _currentUser != userId) {
      if (await _recorder.isRecording()) {
        _logRecorder(
          'Recorder busy, denying $userId',
          emoji: '⚠️',
          details: {'currentUser': _currentUser ?? 'unknown'},
        );
        return false;
      } else {
        _currentUser = userId;
        _logRecorder('Granting access after idle', details: {'user': userId});
        return true;
      }
    }
    _currentUser = userId;
    _logRecorder('Granted access', details: {'user': userId});
    return true;
  }
  void releaseAccess(String userId) {
    if (_currentUser == userId) {
      _currentUser = null;
      _logRecorder('Released access', details: {'user': userId});
    }
  }
  AudioRecorder? getRecorder(String userId) {
    if (_currentUser != userId) {
      _logRecorder(
        'Access denied',
        emoji: '⚠️',
        details: {'requested': userId, 'current': _currentUser ?? 'none'},
        trace: true,
      );
      return null;
    }
    return _recorder;
  }
  bool get isInUse => _currentUser != null;
  String? get currentUser => _currentUser;
}
class NotRecordingException implements Exception {
  final String message;
  NotRecordingException([this.message = 'Recorder is not recording']);
  @override
  String toString() => 'NotRecordingException: $message';
}
class RecordingManager {
  static const String _userId = 'RecordingManager';
  AudioRecorder? get _recorder =>
      SharedRecorderManager.instance.getRecorder(_userId);
  final StreamController<RecordingState> _recordingStateController =
      StreamController<RecordingState>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();
  final StreamController<String> _recordingCompleteController =
      StreamController<String>.broadcast();
  Stream<RecordingState> get recordingStateStream =>
      _recordingStateController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  Stream<String> get recordingCompleteStream =>
      _recordingCompleteController.stream;
  RecordingState _currentState = RecordingState.stopped;
  RecordingState get currentState => _currentState;
  bool get isStreaming => _isStreamingMode;
  String? _lastRecordedPath;
  String? get lastRecordedPath => _lastRecordedPath;
  final Set<String> _pendingTranscriptionPaths = <String>{};
  DateTime? _recordingStartTime;
  bool _isStopping = false;
  bool _isStreamingMode = false;
  StreamController<Uint8List>? _streamController;
  StreamSubscription<List<int>>? _streamSubscription;
  RecordingManager();
  Future<void> initialize() async {
    try {
      await requestPermissions();
    } catch (e) {
      _errorController.add('Failed to initialize recording: $e');
      _updateState(RecordingState.error);
    }
  }
  Future<Stream<Uint8List>> startStreaming({
    int sampleRate = 24000,
    int numChannels = 1,
  }) async {
    if (_isStreamingMode) {
      return _streamController!.stream;
    }
    final hasAccess =
        await SharedRecorderManager.instance.requestAccess(_userId);
    if (!hasAccess) {
      _errorController.add('Cannot access recorder - already in use');
      _updateState(RecordingState.error);
      throw StateError('Recorder already in use');
    }
    final recorder = _recorder;
    if (recorder == null) {
      _errorController.add('Recorder not available');
      _updateState(RecordingState.error);
      SharedRecorderManager.instance.releaseAccess(_userId);
      throw StateError('Recorder not available');
    }
    if (await recorder.hasPermission() == false) {
      _errorController.add('Microphone permission not granted');
      _updateState(RecordingState.error);
      SharedRecorderManager.instance.releaseAccess(_userId);
      throw StateError('Microphone permission not granted');
    }
    if (_currentState == RecordingState.recording) {
      _errorController.add('Already recording to file - stop before streaming');
      SharedRecorderManager.instance.releaseAccess(_userId);
      throw StateError('Recorder already in file recording mode');
    }
    try {
      final rawStream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: numChannels,
        ),
      );
      _streamController = StreamController<Uint8List>.broadcast();
      _streamSubscription = rawStream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            _streamController?.add(Uint8List.fromList(chunk));
          }
        },
        onError: (error) {
          _streamController?.addError(error);
        },
        onDone: () {
          _streamController?.close();
        },
      );
      _isStreamingMode = true;
      _recordingStartTime = DateTime.now();
      _updateState(RecordingState.recording);
      return _streamController!.stream;
    } catch (e) {
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      await _streamController?.close();
      _streamController = null;
      SharedRecorderManager.instance.releaseAccess(_userId);
      _errorController.add('Error starting streaming recorder: $e');
      _updateState(RecordingState.error);
      rethrow;
    }
  }
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
  Future<void> startRecording() async {
    if (_isStreamingMode) {
      _errorController
          .add('Cannot start file recording while streaming is active');
      throw StateError('Cannot start file recording while streaming');
    }
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
      return;
    }
    try {
      final String uuid = const Uuid().v4();
      final String filePath = PathManager.instance.recordingFile(uuid);
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
      } on Exception catch (primaryError) {
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            numChannels: 1,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );
      }
      _lastRecordedPath = filePath;
      _recordingStartTime = DateTime.now(); // Track start time
      _updateState(RecordingState.recording);
    } catch (e) {
      _errorController.add('Error starting recording: $e');
      _updateState(RecordingState.error);
    }
  }
  Future<void> stopStreaming() async {
    if (!_isStreamingMode) {
      return;
    }
    final recorder = _recorder;
    try {
      if (recorder != null) {
        await recorder.stop();
      }
    } catch (e) {
    } finally {
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      if (_streamController != null && !(_streamController!.isClosed)) {
        await _streamController!.close();
      }
      _streamController = null;
      _isStreamingMode = false;
      _recordingStartTime = null;
      SharedRecorderManager.instance.releaseAccess(_userId);
      _updateState(RecordingState.stopped);
    }
  }
  Future<String?> stopRecording() async {
    if (_isStreamingMode) {
      throw NotRecordingException(
          'Recorder is currently streaming; call stopStreaming instead');
    }
    if (_isStopping) {
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
        SharedRecorderManager.instance.releaseAccess(_userId);
        throw NotRecordingException();
      }
      return await _performStopRecording(recorder);
    } finally {
      _isStopping = false;
    }
  }
  Future<String?> _performStopRecording(AudioRecorder recorder) async {
    try {
      _updateState(RecordingState.processing);
      await recorder.stop();
      SharedRecorderManager.instance.releaseAccess(_userId);
      if (_lastRecordedPath == null) {
        throw Exception('No recording path available - this should not happen');
      }
      _updateState(RecordingState.stopped);
      _recordingStartTime = null; // Reset start time
      return _lastRecordedPath!;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      _updateState(RecordingState.error);
      return null;
    }
  }
  Future<String?> tryStopRecording() async {
    if (_isStreamingMode) {
      return null;
    }
    if (_isStopping) {
      return null;
    }
    if (_lastRecordedPath == null) {
      return null;
    }
    _isStopping = true;
    try {
      final recorder = _recorder;
      if (recorder == null) {
        return null;
      }
      final isRecording = await recorder.isRecording();
      if (!isRecording) {
        SharedRecorderManager.instance.releaseAccess(_userId);
        return null;
      }
      final completedFile = _lastRecordedPath;
      _updateState(RecordingState.processing);
      await recorder.stop();
      SharedRecorderManager.instance.releaseAccess(_userId);
      if (completedFile != null && !io.File(completedFile).existsSync()) {
        _lastRecordedPath = null;
        _updateState(RecordingState.stopped);
        _recordingStartTime = null;
        return null;
      }
      _lastRecordedPath = null;
      _updateState(RecordingState.stopped);
      _recordingStartTime = null;
      if (completedFile != null && !_recordingCompleteController.isClosed) {
        _recordingCompleteController.add(completedFile);
      }
      return completedFile;
    } catch (e) {
      _errorController.add('Error stopping recording: $e');
      _updateState(RecordingState.error);
      return null;
    } finally {
      _isStopping = false;
    }
  }
  void _updateState(RecordingState state) {
    _currentState = state;
    _recordingStateController.add(state);
  }
  Duration get elapsed {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }
  void markFileAsPendingTranscription(String filePath) {
    _pendingTranscriptionPaths.add(filePath);
    if (_lastRecordedPath == filePath) {
      _lastRecordedPath = null;
    }
  }
  void markTranscriptionComplete(String filePath) {
    _pendingTranscriptionPaths.remove(filePath);
  }
  Set<String> get pendingTranscriptionPaths =>
      Set.from(_pendingTranscriptionPaths);
  Future<Amplitude?> getCurrentAmplitude() async {
    final recorder = _recorder;
    if (recorder == null || _currentState != RecordingState.recording) {
      return null;
    }
    try {
      return await recorder.getAmplitude();
    } catch (e) {
      return null;
    }
  }
  Future<void> dispose() async {
    if (_isStreamingMode) {
      await stopStreaming();
    } else {
      final recorder = _recorder;
      if (recorder != null) {
        try {
          if (await recorder.isRecording()) {
            await recorder.stop();
          }
        } catch (e) {}
      }
      SharedRecorderManager.instance.releaseAccess(_userId);
    }
    await _recordingStateController.close();
    await _errorController.close();
    await _recordingCompleteController.close();
  }
}
