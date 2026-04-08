// lib/services/audio_file_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../di/interfaces/i_audio_file_manager.dart';
import 'path_manager.dart';
class FileCleanupManager {
  static final Set<String> _deletingFiles = <String>{};
  static Future<void> safeDelete(String filePath) async {
    if (_deletingFiles.contains(filePath)) {
      return;
    }
    _deletingFiles.add(filePath);
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      } else {
      }
    } catch (e) {
    } finally {
      _deletingFiles.remove(filePath);
    }
  }
}
class AudioFileManager implements IAudioFileManager {
  final StreamController<String> _fileDeletedController =
      StreamController<String>.broadcast();
  final StreamController<String> _fileCachedController =
      StreamController<String>.broadcast();
  final Map<String, String> _urlToPathCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const List<String> _supportedFormats = ['wav', 'mp3', 'ogg', 'm4a'];
  late final Future<void> _initFuture;
  bool _initialized = false;
  AudioFileManager() {
    _initFuture = _realInit();
  }
  @override
  Stream<String> get fileDeletedStream => _fileDeletedController.stream;
  @override
  Stream<String> get fileCachedStream => _fileCachedController.stream;
  @override
  Future<void> initialize() =>
      _initFuture; // Idempotent - just returns the same Future
  Future<void> _realInit() async {
    if (_initialized) return;
    try {
      await PathManager.instance.init();
      final cacheDir = p.join(PathManager.instance.cacheDir, 'audio_cache');
      final tempDir = p.join(PathManager.instance.cacheDir, 'temp');
      await _ensureDirectoryExists(cacheDir);
      await _ensureDirectoryExists(tempDir);
      _initialized = true;
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<String> saveAudioFile(Uint8List data,
      {String? fileName, String? extension}) async {
    _ensureInitialized();
    if (data.isEmpty) {
      throw ArgumentError('Audio data cannot be empty');
    }
    final ext = extension ?? 'wav';
    if (!_supportedFormats.contains(ext.toLowerCase())) {
      throw ArgumentError('Unsupported audio format: $ext');
    }
    final name = fileName ?? generateTempFileName(ext);
    final filePath = await getAudioFilePath(name);
    try {
      final file = File(filePath);
      await file.writeAsBytes(data);
      return filePath;
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    _ensureInitialized();
    if (url.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }
    final cachedPath = await getCachedAudioPath(url);
    if (cachedPath != null && await fileExists(cachedPath)) {
      return cachedPath;
    }
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }
      String extension = 'mp3'; // default
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        if (contentType.contains('wav')) {
          extension = 'wav';
        } else if (contentType.contains('ogg')) {
          extension = 'ogg';
        } else if (contentType.contains('m4a')) {
          extension = 'm4a';
        }
      } else {
        final urlPath = uri.path.toLowerCase();
        for (final format in _supportedFormats) {
          if (urlPath.endsWith('.$format')) {
            extension = format;
            break;
          }
        }
      }
      final fileName = 'cached_${_generateUrlHash(url)}.$extension';
      final cacheDir = await getCacheDirectory();
      final filePath = p.join(cacheDir, fileName);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      await cacheAudioFile(url, filePath);
      _fileCachedController.add(filePath);
      return filePath;
    } catch (e) {
      return null;
    }
  }
  @override
  Future<void> cleanupTempFiles() async {
    await _ensureInitialized();
    try {
      final tempDirPath = await getTempDirectory();
      final tempDir = Directory(tempDirPath);
      if (!await tempDir.exists()) return;
      final entities = await tempDir.list().toList();
      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          if (fileName.startsWith('tts_stream_') ||
              fileName.startsWith('temp_') ||
              fileName.startsWith('audio_temp_')) {
            await FileCleanupManager.safeDelete(entity.path);
            _fileDeletedController.add(entity.path);
            deletedCount++;
          }
        }
      }
    } catch (e) {}
  }
  @override
  Future<void> cleanupOldFiles(Duration maxAge) async {
    await _ensureInitialized();
    try {
      final now = DateTime.now();
      final directories = [await getTempDirectory(), await getCacheDirectory()];
      int deletedCount = 0;
      for (final dirPath in directories) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);
            if (age > maxAge) {
              await FileCleanupManager.safeDelete(entity.path);
              _fileDeletedController.add(entity.path);
              deletedCount++;
              _removeFromCacheTracking(entity.path);
            }
          }
        }
      }
    } catch (e) {}
  }
  @override
  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
  @override
  Future<void> deleteFile(String path) async {
    try {
      await FileCleanupManager.safeDelete(path);
      _fileDeletedController.add(path);
      _removeFromCacheTracking(path);
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<Uint8List?> readAudioFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return bytes;
    } catch (e) {
      return null;
    }
  }
  @override
  Future<int> getFileSize(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return 0;
      }
      return await file.length();
    } catch (e) {
      return 0;
    }
  }
  @override
  String generateTempFileName(String extension) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final cleanExt = extension.replaceAll(RegExp(r'[./\\]'), '');
    return 'temp_audio_$timestamp.$cleanExt';
  }
  @override
  Future<String> getTempDirectory() async {
    await _ensureInitialized();
    return p.join(PathManager.instance.cacheDir, 'temp');
  }
  @override
  Future<String> getCacheDirectory() async {
    await _ensureInitialized();
    return p.join(PathManager.instance.cacheDir, 'audio_cache');
  }
  @override
  Future<String> getAudioFilePath(String fileName) async {
    await _ensureInitialized();
    final sanitizedName = PathManager.instance.sanitizeFileName(fileName);
    final tempDir = await getTempDirectory();
    return p.join(tempDir, sanitizedName);
  }
  @override
  Future<void> cacheAudioFile(String url, String localPath) async {
    _urlToPathCache[url] = localPath;
    _cacheTimestamps[url] = DateTime.now();
  }
  @override
  Future<String?> getCachedAudioPath(String url) async {
    final cachedPath = _urlToPathCache[url];
    if (cachedPath != null && await fileExists(cachedPath)) {
      return cachedPath;
    }
    if (cachedPath != null) {
      _urlToPathCache.remove(url);
      _cacheTimestamps.remove(url);
    }
    return null;
  }
  @override
  Future<void> clearCache() async {
    try {
      final cacheDirPath = await getCacheDirectory();
      final cacheDir = Directory(cacheDirPath);
      if (await cacheDir.exists()) {
        final entities = await cacheDir.list().toList();
        int deletedCount = 0;
        for (final entity in entities) {
          if (entity is File) {
            await FileCleanupManager.safeDelete(entity.path);
            _fileDeletedController.add(entity.path);
            deletedCount++;
          }
        }
      }
      _urlToPathCache.clear();
      _cacheTimestamps.clear();
    } catch (e) {}
  }
  @override
  Future<String> convertAudioFormat(
      String inputPath, String outputFormat) async {
    throw UnimplementedError('Audio format conversion not yet implemented');
  }
  @override
  Future<bool> isValidAudioFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      final extension = p.extension(path).toLowerCase();
      if (!_supportedFormats.any((format) => extension.endsWith(format))) {
        return false;
      }
      final size = await file.length();
      if (size == 0) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  @override
  Future<int> getTotalCacheSize() async {
    int totalSize = 0;
    try {
      final directories = [await getCacheDirectory(), await getTempDirectory()];
      for (final dirPath in directories) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final entities = await dir.list().toList();
          for (final entity in entities) {
            if (entity is File) {
              final stat = await entity.stat();
              totalSize += stat.size;
            }
          }
        }
      }
    } catch (e) {}
    return totalSize;
  }
  @override
  Future<void> limitCacheSize(int maxSizeBytes) async {
    try {
      int currentSize = await getTotalCacheSize();
      if (currentSize <= maxSizeBytes) {
        return; // Cache size is within limit
      }
      final List<FileInfo> fileInfos = [];
      final directories = [await getCacheDirectory(), await getTempDirectory()];
      for (final dirPath in directories) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final entities = await dir.list().toList();
          for (final entity in entities) {
            if (entity is File) {
              final stat = await entity.stat();
              fileInfos.add(FileInfo(
                path: entity.path,
                size: stat.size,
                lastModified: stat.modified,
              ));
            }
          }
        }
      }
      fileInfos.sort((a, b) => a.lastModified.compareTo(b.lastModified));
      int deletedSize = 0;
      int deletedCount = 0;
      for (final fileInfo in fileInfos) {
        if (currentSize - deletedSize <= maxSizeBytes) {
          break; // We've freed enough space
        }
        await FileCleanupManager.safeDelete(fileInfo.path);
        _fileDeletedController.add(fileInfo.path);
        _removeFromCacheTracking(fileInfo.path);
        deletedSize += fileInfo.size;
        deletedCount++;
      }
    } catch (e) {}
  }
  @override
  void dispose() {
    _fileDeletedController.close();
    _fileCachedController.close();
    _urlToPathCache.clear();
    _cacheTimestamps.clear();
  }
  Future<void> _ensureInitialized() => _initFuture;
  Future<void> _ensureDirectoryExists(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {}
  }
  String _generateUrlHash(String url) {
    final hash = url.hashCode.abs().toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return '${hash}_$timestamp';
  }
  void _removeFromCacheTracking(String filePath) {
    final urlToRemove = _urlToPathCache.entries
        .where((entry) => entry.value == filePath)
        .map((entry) => entry.key)
        .toList();
    for (final url in urlToRemove) {
      _urlToPathCache.remove(url);
      _cacheTimestamps.remove(url);
    }
  }
}
class FileInfo {
  final String path;
  final int size;
  final DateTime lastModified;
  FileInfo({
    required this.path,
    required this.size,
    required this.lastModified,
  });
}
