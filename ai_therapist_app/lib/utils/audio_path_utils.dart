/// Audio path utilities to prevent double extension bugs.
///
/// This utility provides functions to ensure consistent audio file naming
/// and prevent double extensions like .wav.wav that can cause playback issues.
library;

class AudioPathUtils {
  /// Ensures a filename or path has a single audio extension.
  ///
  /// Prevents double extensions by checking if the path already ends with
  /// the specified extension (case-insensitive).
  ///
  /// Examples:
  /// - `ensureExtension("audio", "wav")` → `"audio.wav"`
  /// - `ensureExtension("audio.wav", "wav")` → `"audio.wav"` (unchanged)
  /// - `ensureExtension("/path/to/audio", "wav")` → `"/path/to/audio.wav"`
  /// - `ensureExtension("/path/to/audio.wav", "wav")` → `"/path/to/audio.wav"` (unchanged)
  static String ensureExtension(String pathOrName, String extension) {
    if (pathOrName.isEmpty) {
      throw ArgumentError('Path or filename cannot be empty');
    }

    // Normalize extension (remove leading dot, make lowercase)
    final normalizedExt =
        extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    final expectedEnding = '.$normalizedExt';

    // Check if path already ends with the extension (case-insensitive)
    if (pathOrName.toLowerCase().endsWith(expectedEnding)) {
      return pathOrName; // Already has correct extension
    }

    return '$pathOrName$expectedEnding';
  }

  /// Ensures a filename or path has a .wav extension.
  ///
  /// Convenience method for WAV files specifically.
  ///
  /// Examples:
  /// - `ensureWav("audio")` → `"audio.wav"`
  /// - `ensureWav("audio.wav")` → `"audio.wav"` (unchanged)
  static String ensureWav(String pathOrName) {
    return ensureExtension(pathOrName, 'wav');
  }

  /// Ensures a filename or path has a .mp3 extension.
  ///
  /// Convenience method for MP3 files specifically.
  static String ensureMp3(String pathOrName) {
    return ensureExtension(pathOrName, 'mp3');
  }

  /// Ensures a filename or path has a .ogg extension.
  ///
  /// Convenience method for OGG files specifically.
  static String ensureOgg(String pathOrName) {
    return ensureExtension(pathOrName, 'ogg');
  }

  /// Validates that a basename contains no file extensions.
  ///
  /// Useful for ensuring clean basenames before applying extensions.
  /// Throws ArgumentError if the basename contains dots.
  ///
  /// Examples:
  /// - `validateBasename("audio")` → `"audio"` (valid)
  /// - `validateBasename("audio.wav")` → throws ArgumentError
  static String validateBasename(String basename) {
    if (basename.contains('.')) {
      throw ArgumentError('Basename should not contain extensions: $basename');
    }
    return basename;
  }

  /// Generates a clean timestamp-based ID without extensions.
  ///
  /// Returns a string like "tts_1751243751996444" suitable for use
  /// as a base filename ID.
  static String generateTimestampId([String prefix = 'tts']) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }
}
