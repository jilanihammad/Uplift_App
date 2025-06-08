import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class PathManager {
  static PathManager? _instance;
  static PathManager get instance => _instance ??= PathManager._();
  PathManager._();

  late final String _cacheDir;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true; // race-free guard

    _cacheDir = (await getTemporaryDirectory()).path;
    assert(_cacheDir.isNotEmpty, 'Invalid cache dir');
    if (kDebugMode) {
      print('🗂️ PathManager initialized: $_cacheDir');
    }
  }

  String ttsFile([String? id, String ext = 'wav']) {
    _ensureInitialized();
    final safeId = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    return p.join(_cacheDir, 'tts_stream_$safeId.$ext');
  }

  String recordingFile(String uuid) {
    _ensureInitialized();
    return p.join(_cacheDir, '$uuid.m4a');
  }

  String vadMonitorFile() {
    _ensureInitialized();
    return p.join(
        _cacheDir, 'vad_monitor.m4a'); // Keep .m4a for VAD compatibility
  }

  String sanitizeFileName(String path) {
    final dir = p.dirname(path);
    final base = p.basename(path).replaceAll(RegExp(r'[^\w\-.]'), '_');
    return dir == '.' ? base : p.join(dir, base);
  }

  Future<String> get cacheDirFuture async {
    if (!_isInitialized) await init();
    return _cacheDir;
  }

  String get cacheDir {
    _ensureInitialized();
    return _cacheDir;
  }

  @visibleForTesting
  void debugReset() {
    _instance = null;
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
          'PathManager used before init(); call await PathManager.instance.init() first.');
    }
  }
}
