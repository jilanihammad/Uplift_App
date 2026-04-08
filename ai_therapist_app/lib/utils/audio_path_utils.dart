library;
class AudioPathUtils {
  static String ensureExtension(String pathOrName, String extension) {
    if (pathOrName.isEmpty) {
      throw ArgumentError('Path or filename cannot be empty');
    }
    final normalizedExt =
        extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    final expectedEnding = '.$normalizedExt';
    if (pathOrName.toLowerCase().endsWith(expectedEnding)) {
      return pathOrName; // Already has correct extension
    }
    return '$pathOrName$expectedEnding';
  }
  static String ensureWav(String pathOrName) {
    return ensureExtension(pathOrName, 'wav');
  }
  static String ensureMp3(String pathOrName) {
    return ensureExtension(pathOrName, 'mp3');
  }
  static String ensureOgg(String pathOrName) {
    return ensureExtension(pathOrName, 'ogg');
  }
  static String validateBasename(String basename) {
    if (basename.contains('.')) {
      throw ArgumentError('Basename should not contain extensions: $basename');
    }
    return basename;
  }
  static String generateTimestampId([String prefix = 'tts']) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }
}
