// lib/di/interfaces/i_audio_file_manager.dart
import 'dart:async';
import 'dart:typed_data';
abstract class IAudioFileManager {
  Future<String> saveAudioFile(Uint8List data,
      {String? fileName, String? extension});
  Future<String?> downloadAndCacheAudio(String url);
  Future<void> cleanupTempFiles();
  Future<void> cleanupOldFiles(Duration maxAge);
  Future<bool> fileExists(String path);
  Future<void> deleteFile(String path);
  Future<Uint8List?> readAudioFile(String path);
  Future<int> getFileSize(String path);
  String generateTempFileName(String extension);
  Future<String> getTempDirectory();
  Future<String> getCacheDirectory();
  Future<String> getAudioFilePath(String fileName);
  Future<void> cacheAudioFile(String url, String localPath);
  Future<String?> getCachedAudioPath(String url);
  Future<void> clearCache();
  Future<String> convertAudioFormat(String inputPath, String outputFormat);
  Future<bool> isValidAudioFile(String path);
  Future<int> getTotalCacheSize();
  Future<void> limitCacheSize(int maxSizeBytes);
  Future<void> initialize();
  void dispose();
  Stream<String> get fileDeletedStream;
  Stream<String> get fileCachedStream;
}
