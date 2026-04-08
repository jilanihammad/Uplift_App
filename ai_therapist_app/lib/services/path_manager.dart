import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
class PathManager {
  static PathManager? _instance;
  static PathManager get instance => _instance ??= PathManager._();
  PathManager._();
  static const String SUBDIR_TTS = 'tts';
  static const String SUBDIR_RECORDINGS = 'recordings';
  static const String SUBDIR_VAD = 'vad';
  static const String TTS_PREFIX = 'tts_stream_';
  static const String TTS_DEFAULT_EXT = 'wav';
  static const String RECORDING_EXT = 'm4a';
  static const String VAD_FILENAME =
      'vad_monitor.m4a'; // Keep .m4a for VAD compatibility
  late final String _cacheDir;
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  bool _initStarted = false;
  Future<void> init() async {
    if (_isInitialized) return;
    if (_initStarted) {
      return _initCompleter.future;
    }
    _initStarted = true;
    try {
      final dir = await getTemporaryDirectory();
      _cacheDir = p.normalize(dir
          .path); // Normalize path first to handle legitimate .. from emulators
      if (_cacheDir.contains('..') ||
          _cacheDir.contains('ccom.') ||
          _cacheDir.contains('mayaa.') ||
          _cacheDir.contains('cachee') ||
          _cacheDir.isEmpty) {
        throw StateError('Corrupted cache directory path detected: $_cacheDir');
      }
      _isInitialized = true;
      _initCompleter.complete();
    } catch (e, st) {
      _initCompleter.completeError(e, st);
      rethrow;
    }
  }
  String ttsFile([String? id, String ext = TTS_DEFAULT_EXT]) {
    _ensureInitialized();
    final safeId = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final safeExt = ext.replaceAll(RegExp(r'[./\\]'), '');
    final filePath =
        _buildSecurePath([SUBDIR_TTS], '$TTS_PREFIX$safeId.$safeExt');
    return filePath;
  }
  String recordingFile(String uuid) {
    _ensureInitialized();
    if (!RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(uuid)) {
      throw ArgumentError('Invalid UUID format: $uuid');
    }
    final filePath =
        _buildSecurePath([SUBDIR_RECORDINGS], '$uuid.$RECORDING_EXT');
    return filePath;
  }
  String vadMonitorFile() {
    _ensureInitialized();
    final filePath = _buildSecurePath([SUBDIR_VAD], VAD_FILENAME);
    return filePath;
  }
  String _buildSecurePath(List<String> subdirs, String filename) {
    String path = _cacheDir;
    for (final subdir in subdirs) {
      path = p.join(path, subdir);
    }
    path = p.join(path, filename);
    final isTestEnv = path.contains('test_cache') || path.contains('temp');
    final hasCorruption = path.contains('..') ||
        path.contains('ccom.') ||
        path.contains('mayaa.') ||
        (path.contains('cachee') && !isTestEnv);
    if (hasCorruption) {
      throw StateError('Path corruption detected during build: $path');
    }
    _ensureDirectoryExists(p.dirname(path));
    return path;
  }
  String sanitizeFileName(String name) {
    final dir = p.dirname(name);
    final base = p.basename(name).replaceAll(RegExp(r'[^\w\-.]'), '_');
    return dir == '.' ? base : p.join(dir, base);
  }
  Future<String> get cacheDirFuture async {
    if (!_isInitialized) await init();
    return _cacheDir;
  }
  String get cacheDir {
    if (!_isInitialized) {
      throw StateError(
          'PathManager.cacheDir accessed before init(); use cacheDirFuture instead');
    }
    return _cacheDir;
  }
  @visibleForTesting
  void debugReset() {
    _instance = null;
    _isInitialized = false;
    // Note: Cannot reset Completer once created, but tests should create new instances
    // Note: Tests should always grab PathManager.instance after calling debugReset()
  }
  @visibleForTesting
  void debugSetCacheDir(String testCacheDir) {
    _cacheDir = testCacheDir;
    _isInitialized = true;
  }
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
          'PathManager.cacheDir accessed before init(); use cacheDirFuture instead');
    }
  }
  void _ensureDirectoryExists(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (e) {}
  }
}
