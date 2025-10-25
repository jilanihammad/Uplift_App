import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Manages cleanup of temporary files and resources
///
/// Responsible for deleting temporary audio files and other resources
class ResourceCleaner {
  // Stream controllers
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  // Streams for external components to listen to
  Stream<String?> get errorStream => _errorController.stream;

  // File type extensions to clean
  final List<String> _tempFileExtensions = [
    '.m4a', // Recording files
    '.mp3', // TTS files
    '.wav', // Other audio files
  ];

  // Constructor
  ResourceCleaner();

  // Clean up temporary files older than specified duration
  Future<int> cleanupTempFiles(
      {Duration maxAge = const Duration(hours: 24)}) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final List<FileSystemEntity> entities = await tempDir.list().toList();

      final DateTime now = DateTime.now();
      int filesDeleted = 0;

      for (final entity in entities) {
        if (entity is File) {
          final String extension = entity.path.split('.').last;
          if (_tempFileExtensions.contains('.$extension')) {
            final FileStat stats = await entity.stat();
            final Duration age = now.difference(stats.modified);

            if (age > maxAge) {
              await entity.delete();
              filesDeleted++;

              if (kDebugMode) {
                debugPrint('🧹 Deleted temp file: ${entity.path}');
              }
            }
          }
        }
      }

      if (kDebugMode && filesDeleted > 0) {
        debugPrint('🧹 Cleanup complete. Deleted $filesDeleted temporary files.');
      }

      return filesDeleted;
    } catch (e) {
      _errorController.add('Error cleaning up temporary files: $e');
      if (kDebugMode) {
        debugPrint('❌ Cleanup error: $e');
      }
      return 0;
    }
  }

  // Delete a specific file if it exists
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();

        if (kDebugMode) {
          debugPrint('🧹 Deleted file: $filePath');
        }

        return true;
      } else {
        return false;
      }
    } catch (e) {
      _errorController.add('Error deleting file: $e');
      if (kDebugMode) {
        debugPrint('❌ File deletion error: $e');
      }
      return false;
    }
  }

  // Clean up a list of file paths
  Future<int> cleanupFiles(List<String> filePaths) async {
    int filesDeleted = 0;

    for (final path in filePaths) {
      final success = await deleteFile(path);
      if (success) filesDeleted++;
    }

    return filesDeleted;
  }

  // Clean up resources
  Future<void> dispose() async {
    await _errorController.close();
  }
}
