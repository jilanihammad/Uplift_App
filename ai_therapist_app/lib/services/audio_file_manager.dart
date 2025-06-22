// lib/services/audio_file_manager.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../di/interfaces/i_audio_file_manager.dart';
import 'path_manager.dart';

/// File cleanup manager to prevent race conditions from multiple deletion attempts
/// Extracted from VoiceService to maintain existing safety mechanisms
class FileCleanupManager {
  static final Set<String> _deletingFiles = <String>{};

  /// Safely delete a file, preventing race conditions from multiple deletion attempts
  static Future<void> safeDelete(String filePath) async {
    if (_deletingFiles.contains(filePath)) {
      if (kDebugMode) {
        print('🗑️ File deletion already in progress for: $filePath');
      }
      return;
    }

    _deletingFiles.add(filePath);
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        if (kDebugMode) {
          print('🗑️ Successfully deleted file: $filePath');
        }
      } else {
        if (kDebugMode) {
          print('🗑️ File already deleted: $filePath');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🗑️ Error deleting file $filePath: $e');
      }
    } finally {
      _deletingFiles.remove(filePath);
    }
  }
}

/// Audio file manager implementation
/// Handles file operations, caching, and cleanup for audio files
class AudioFileManager implements IAudioFileManager {
  // Stream controllers for events
  final StreamController<String> _fileDeletedController = StreamController<String>.broadcast();
  final StreamController<String> _fileCachedController = StreamController<String>.broadcast();
  
  // Cache management
  final Map<String, String> _urlToPathCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // Configuration  
  static const List<String> _supportedFormats = ['wav', 'mp3', 'ogg', 'm4a'];
  
  bool _initialized = false;
  
  @override
  Stream<String> get fileDeletedStream => _fileDeletedController.stream;
  
  @override
  Stream<String> get fileCachedStream => _fileCachedController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Initialize PathManager if not already done
      await PathManager.instance.init();
      
      // Create cache directories
      await _ensureDirectoryExists(getCacheDirectory());
      await _ensureDirectoryExists(getTempDirectory());
      
      if (kDebugMode) {
        print('🎵 AudioFileManager initialized successfully');
      }
      
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ AudioFileManager initialization error: $e');
      }
      rethrow;
    }
  }

  @override
  Future<String> saveAudioFile(Uint8List data, {String? fileName, String? extension}) async {
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
      
      if (kDebugMode) {
        print('💾 Saved audio file: $filePath (${data.length} bytes)');
      }
      
      return filePath;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving audio file: $e');
      }
      rethrow;
    }
  }

  @override
  Future<String?> downloadAndCacheAudio(String url) async {
    _ensureInitialized();
    
    if (url.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }
    
    // Check if already cached
    final cachedPath = await getCachedAudioPath(url);
    if (cachedPath != null && await fileExists(cachedPath)) {
      if (kDebugMode) {
        print('📂 Using cached audio: $cachedPath');
      }
      return cachedPath;
    }
    
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      
      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('❌ Failed to download audio: HTTP ${response.statusCode}');
        }
        return null;
      }
      
      // Determine file extension from URL or content-type
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
        // Try to get extension from URL
        final urlPath = uri.path.toLowerCase();
        for (final format in _supportedFormats) {
          if (urlPath.endsWith('.$format')) {
            extension = format;
            break;
          }
        }
      }
      
      // Generate cache file path
      final fileName = 'cached_${_generateUrlHash(url)}.$extension';
      final cacheDir = getCacheDirectory();
      final filePath = p.join(cacheDir, fileName);
      
      // Write to cache
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      
      // Update cache tracking
      await cacheAudioFile(url, filePath);
      
      if (kDebugMode) {
        print('⬇️ Downloaded and cached audio: $filePath (${response.bodyBytes.length} bytes)');
      }
      
      _fileCachedController.add(filePath);
      return filePath;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error downloading audio: $e');
      }
      return null;
    }
  }

  @override
  Future<void> cleanupTempFiles() async {
    _ensureInitialized();
    
    try {
      final tempDir = Directory(getTempDirectory());
      if (!await tempDir.exists()) return;
      
      final entities = await tempDir.list().toList();
      int deletedCount = 0;
      
      for (final entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          // Clean up temp files (those starting with tts_stream_ or similar patterns)
          if (fileName.startsWith('tts_stream_') || 
              fileName.startsWith('temp_') ||
              fileName.startsWith('audio_temp_')) {
            await FileCleanupManager.safeDelete(entity.path);
            _fileDeletedController.add(entity.path);
            deletedCount++;
          }
        }
      }
      
      if (kDebugMode && deletedCount > 0) {
        debugPrint('🧹 Cleaned up $deletedCount temporary files');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error cleaning temp files: $e');
      }
    }
  }

  @override
  Future<void> cleanupOldFiles(Duration maxAge) async {
    _ensureInitialized();
    
    try {
      final now = DateTime.now();
      final directories = [getTempDirectory(), getCacheDirectory()];
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
              
              // Remove from cache tracking if it was cached
              _removeFromCacheTracking(entity.path);
            }
          }
        }
      }
      
      if (kDebugMode && deletedCount > 0) {
        debugPrint('🧹 Cleaned up $deletedCount old files (older than ${maxAge.inHours}h)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error cleaning old files: $e');
      }
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking file existence: $e');
      }
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
      if (kDebugMode) {
        print('❌ Error deleting file: $e');
      }
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
      if (kDebugMode) {
        print('📖 Read audio file: $path (${bytes.length} bytes)');
      }
      return bytes;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error reading audio file: $e');
      }
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
      if (kDebugMode) {
        print('❌ Error getting file size: $e');
      }
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
  String getTempDirectory() {
    _ensureInitialized();
    return p.join(PathManager.instance.cacheDir, 'temp');
  }

  @override
  String getCacheDirectory() {
    _ensureInitialized();
    return p.join(PathManager.instance.cacheDir, 'audio_cache');
  }

  @override
  Future<String> getAudioFilePath(String fileName) async {
    _ensureInitialized();
    
    final sanitizedName = PathManager.instance.sanitizeFileName(fileName);
    final tempDir = getTempDirectory();
    return p.join(tempDir, sanitizedName);
  }

  @override
  Future<void> cacheAudioFile(String url, String localPath) async {
    _urlToPathCache[url] = localPath;
    _cacheTimestamps[url] = DateTime.now();
    
    if (kDebugMode) {
      print('📂 Cached audio mapping: $url -> $localPath');
    }
  }

  @override
  Future<String?> getCachedAudioPath(String url) async {
    final cachedPath = _urlToPathCache[url];
    if (cachedPath != null && await fileExists(cachedPath)) {
      return cachedPath;
    }
    
    // Remove from cache if file no longer exists
    if (cachedPath != null) {
      _urlToPathCache.remove(url);
      _cacheTimestamps.remove(url);
    }
    
    return null;
  }

  @override
  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(getCacheDirectory());
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
        
        if (kDebugMode) {
          print('🧹 Cleared cache: deleted $deletedCount files');
        }
      }
      
      // Clear in-memory cache
      _urlToPathCache.clear();
      _cacheTimestamps.clear();
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing cache: $e');
      }
    }
  }

  @override
  Future<String> convertAudioFormat(String inputPath, String outputFormat) async {
    // This is a placeholder implementation - audio format conversion would require
    // native platform-specific code or FFmpeg integration
    throw UnimplementedError('Audio format conversion not yet implemented');
  }

  @override
  Future<bool> isValidAudioFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      
      // Basic validation based on file extension and size
      final extension = p.extension(path).toLowerCase();
      if (!_supportedFormats.any((format) => extension.endsWith(format))) {
        return false;
      }
      
      final size = await file.length();
      if (size == 0) {
        return false;
      }
      
      // Could add more sophisticated validation here (magic number check, etc.)
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error validating audio file: $e');
      }
      return false;
    }
  }

  @override
  Future<int> getTotalCacheSize() async {
    int totalSize = 0;
    
    try {
      final directories = [getCacheDirectory(), getTempDirectory()];
      
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
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error calculating cache size: $e');
      }
    }
    
    return totalSize;
  }

  @override
  Future<void> limitCacheSize(int maxSizeBytes) async {
    try {
      int currentSize = await getTotalCacheSize();
      
      if (currentSize <= maxSizeBytes) {
        return; // Cache size is within limit
      }
      
      if (kDebugMode) {
        debugPrint('📊 Cache size ${_formatBytes(currentSize)} exceeds limit ${_formatBytes(maxSizeBytes)}, cleaning up...');
      }
      
      // Get all cached files with their timestamps
      final List<FileInfo> fileInfos = [];
      final directories = [getCacheDirectory(), getTempDirectory()];
      
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
      
      // Sort by last modified (oldest first)
      fileInfos.sort((a, b) => a.lastModified.compareTo(b.lastModified));
      
      // Delete oldest files until we're under the limit
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
      
      if (kDebugMode) {
        print('🧹 Cache cleanup: deleted $deletedCount files (${_formatBytes(deletedSize)})');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error limiting cache size: $e');
      }
    }
  }

  @override
  void dispose() {
    _fileDeletedController.close();
    _fileCachedController.close();
    _urlToPathCache.clear();
    _cacheTimestamps.clear();
    
    if (kDebugMode) {
      print('🎵 AudioFileManager disposed');
    }
  }

  // Private helper methods

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('AudioFileManager not initialized. Call initialize() first.');
    }
  }

  Future<void> _ensureDirectoryExists(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating directory $dirPath: $e');
      }
    }
  }

  String _generateUrlHash(String url) {
    // Simple hash using URL's hashCode
    final hash = url.hashCode.abs().toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return '${hash}_$timestamp';
  }

  void _removeFromCacheTracking(String filePath) {
    // Remove from cache tracking by finding the URL that maps to this path
    final urlToRemove = _urlToPathCache.entries
        .where((entry) => entry.value == filePath)
        .map((entry) => entry.key)
        .toList();
    
    for (final url in urlToRemove) {
      _urlToPathCache.remove(url);
      _cacheTimestamps.remove(url);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Helper class for file information during cache management
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