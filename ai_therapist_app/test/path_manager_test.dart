import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/services/path_manager.dart';
import 'dart:io';

void main() {
  // CRITICAL: Bootstrap Flutter test binding for platform channels
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PathManager', () {
    late PathManager pathManager;

    setUp(() async {
      // Reset PathManager state between tests
      PathManager.instance.debugReset();
      pathManager = PathManager.instance;

      // Skip normal init in test environment - directly set test cache directory
      final testDir = Directory.systemTemp.createTempSync('test_cache');
      pathManager.debugSetCacheDir(testDir.path);
    });

    test('Path round-trip should work (BEST TEST)', () async {
      const id = 'test123';
      final path = pathManager.ttsFile(id);

      // Actually test that file operations work with generated paths
      await File(path).writeAsBytes([1, 2, 3]);
      expect(File(path).existsSync(), isTrue,
          reason: 'File should exist after creation: $path');
      await File(path).delete();
      expect(File(path).existsSync(), isFalse,
          reason: 'File should not exist after deletion: $path');
    });

    test('TTS paths should not contain dangerous patterns', () {
      final ttsPath = pathManager.ttsFile('123');
      expect(ttsPath.contains('..'), false,
          reason: 'TTS path should not contain double dots: $ttsPath');
      expect(RegExp(r'\/{2,}').hasMatch(ttsPath), false,
          reason: 'TTS path should not contain double slashes: $ttsPath');
    });

    test('Recording paths should not contain dangerous patterns', () {
      final recordingPath =
          pathManager.recordingFile('10633a19-09a9-40db-bbd2-978db010df87');
      expect(recordingPath.contains('..'), false,
          reason:
              'Recording path should not contain double dots: $recordingPath');
      expect(RegExp(r'\/{2,}').hasMatch(recordingPath), false,
          reason:
              'Recording path should not contain double slashes: $recordingPath');
    });

    test('Filename sanitization should preserve directory structure', () {
      const input = 'some/path/test@file#name.wav';
      final result = pathManager.sanitizeFileName(input);
      // Use path.join to create expected result for cross-platform compatibility
      expect(result, endsWith('test_file_name.wav'));
      expect(result, contains('some'));
      expect(result, contains('path'));
    });

    test('TTS collision prevention with microseconds', () async {
      final path1 = pathManager.ttsFile(); // Auto-generate ID
      await Future.delayed(const Duration(
          milliseconds: 1)); // Ensure different timestamp (use ms not μs)
      final path2 = pathManager.ttsFile(); // Auto-generate ID
      expect(path1, isNot(equals(path2)),
          reason: 'Auto-generated paths should be unique');
    });

    test('PathManager should throw clear error when accessed before init', () {
      // Use debugReset to test uninitialized state
      pathManager.debugReset();
      expect(
        () => PathManager.instance.cacheDir,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('use cacheDirFuture instead'),
        )),
      );
      // Re-initialize for other tests (set test cache dir directly)
      final testDir = Directory.systemTemp.createTempSync('test_cache_reset');
      pathManager = PathManager.instance;
      pathManager.debugSetCacheDir(testDir.path);
    });

    test('PathManager should initialize properly', () {
      expect(pathManager.cacheDir, isNotEmpty);
      // In test environment, we use a temp directory, not the app-specific directory
      expect(
          pathManager.cacheDir,
          anyOf(
            contains('com.maya.uplift'),
            contains('test_cache'),
            contains('temp'),
          ));
    });

    test('Subdirectory organization should work correctly', () {
      final ttsPath = pathManager.ttsFile('test');
      final recordingPath =
          pathManager.recordingFile('10633a19-09a9-40db-bbd2-978db010df87');
      final vadPath = pathManager.vadMonitorFile();

      expect(
          ttsPath,
          anyOf(
            contains('/${PathManager.SUBDIR_TTS}/'),
            contains('\\${PathManager.SUBDIR_TTS}\\'),
          ));
      expect(
          recordingPath,
          anyOf(
            contains('/${PathManager.SUBDIR_RECORDINGS}/'),
            contains('\\${PathManager.SUBDIR_RECORDINGS}\\'),
          ));
      expect(
          vadPath,
          anyOf(
            contains('/${PathManager.SUBDIR_VAD}/'),
            contains('\\${PathManager.SUBDIR_VAD}\\'),
          ));
    });

    test('Extension security should strip dangerous dots', () {
      final path1 = pathManager.ttsFile('test', '../../../etc/passwd');
      final path2 = pathManager.ttsFile('test', '..\\..\\windows\\system32');

      expect(path1, isNot(contains('..')));
      expect(path2, isNot(contains('..')));
      expect(path1, endsWith('.etcpasswd'));
      expect(path2, endsWith('.windowssystem32'));
    });

    test('Path traversal protection should work', () {
      // Try to get paths with suspicious content and verify they're safe
      final safePath = pathManager.ttsFile('test');
      expect(safePath, isNot(contains('..')));
      expect(safePath, isNot(contains('ccom.')));
      expect(safePath, isNot(contains('mayaa.')));
      expect(safePath, isNot(contains('cachee')));
    });

    test('UUID validation should reject invalid formats', () {
      expect(
        () => pathManager.recordingFile('invalid-uuid'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => pathManager.recordingFile('10633a19-09a9-40db-bbd2-978db010df87'),
        returnsNormally,
      );
    });

    test('Constants should be immutable and secure', () {
      expect(PathManager.SUBDIR_TTS, equals('tts'));
      expect(PathManager.SUBDIR_RECORDINGS, equals('recordings'));
      expect(PathManager.SUBDIR_VAD, equals('vad'));
      expect(PathManager.TTS_PREFIX, equals('tts_stream_'));
      expect(PathManager.TTS_DEFAULT_EXT, equals('wav'));
      expect(PathManager.RECORDING_EXT, equals('m4a'));
      expect(PathManager.VAD_FILENAME, equals('vad_monitor.m4a'));
    });
  });
}
