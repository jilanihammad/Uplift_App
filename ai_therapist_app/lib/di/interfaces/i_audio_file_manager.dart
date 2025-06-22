// lib/di/interfaces/i_audio_file_manager.dart

import 'dart:async';
import 'dart:typed_data';

/// Interface for audio file management operations
/// Handles file operations, caching, and cleanup for audio files
abstract class IAudioFileManager {
  // File operations
  Future<String> saveAudioFile(Uint8List data, {String? fileName, String? extension});
  Future<String?> downloadAndCacheAudio(String url);
  Future<void> cleanupTempFiles();
  Future<void> cleanupOldFiles(Duration maxAge);
  
  // File utilities
  Future<bool> fileExists(String path);
  Future<void> deleteFile(String path);
  Future<Uint8List?> readAudioFile(String path);
  Future<int> getFileSize(String path);
  
  // Path management
  String generateTempFileName(String extension);
  String getTempDirectory();
  String getCacheDirectory();
  Future<String> getAudioFilePath(String fileName);
  
  // Caching
  Future<void> cacheAudioFile(String url, String localPath);
  Future<String?> getCachedAudioPath(String url);
  Future<void> clearCache();
  
  // File format handling
  Future<String> convertAudioFormat(String inputPath, String outputFormat);
  Future<bool> isValidAudioFile(String path);
  
  // Storage management
  Future<int> getTotalCacheSize();
  Future<void> limitCacheSize(int maxSizeBytes);
  
  // Initialization and cleanup
  Future<void> initialize();
  void dispose();
  
  // Events
  Stream<String> get fileDeletedStream;
  Stream<String> get fileCachedStream;
}