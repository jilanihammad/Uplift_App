import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Utility for handling OPUS/OGG header detection and buffering
///
/// OPUS streams in OGG containers require specific header sequences:
/// 1. OpusHead - Contains codec parameters (channel count, sample rate, etc.)
/// 2. OpusTags - Contains metadata (title, artist, etc.)
///
/// ExoPlayer needs both headers before it can start decoding OPUS audio.
/// This utility detects and buffers these headers for proper streaming.
class OpusHeaderUtils {
  /// OGG page signature (4 bytes: "OggS")
  static const List<int> oggPageSignature = [0x4F, 0x67, 0x67, 0x53]; // "OggS"

  /// OpusHead signature (8 bytes: "OpusHead")
  static const List<int> opusHeadSignature = [
    0x4F,
    0x70,
    0x75,
    0x73,
    0x48,
    0x65,
    0x61,
    0x64
  ]; // "OpusHead"

  /// OpusTags signature (8 bytes: "OpusTags")
  static const List<int> opusTagsSignature = [
    0x4F,
    0x70,
    0x75,
    0x73,
    0x54,
    0x61,
    0x67,
    0x73
  ]; // "OpusTags"

  /// Minimum expected size for complete OPUS headers (OpusHead + OpusTags)
  /// This is a conservative estimate - actual size varies but rarely exceeds 2KB
  static const int minHeaderBufferSize = 2048; // 2KB buffer for headers

  /// Maximum size to scan for headers (safety limit)
  static const int maxHeaderScanSize = 8192; // 8KB max scan

  /// Check if data contains OGG/OPUS format
  static bool isOpusFormat(List<int> data) {
    if (data.length < 4) return false;

    // Check for OGG page signature at the beginning
    for (int i = 0; i < 4; i++) {
      if (data[i] != oggPageSignature[i]) {
        return false;
      }
    }

    if (kDebugMode) {
      debugPrint('✅ OpusHeaderUtils: Detected OGG container format');
    }

    return true;
  }

  /// Check if data contains WAV format (fallback detection)
  static bool isWavFormat(List<int> data) {
    if (data.length < 12) return false;

    // Check for RIFF signature
    final riffSignature = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
    final waveSignature = [0x57, 0x41, 0x56, 0x45]; // "WAVE"

    // Check RIFF at offset 0
    for (int i = 0; i < 4; i++) {
      if (data[i] != riffSignature[i]) {
        return false;
      }
    }

    // Check WAVE at offset 8
    for (int i = 0; i < 4; i++) {
      if (data[8 + i] != waveSignature[i]) {
        return false;
      }
    }

    return true;
  }

  /// Parse OPUS headers from OGG stream
  /// Returns OpusHeaderInfo if both OpusHead and OpusTags are found
  static OpusHeaderInfo? parseOpusHeaders(List<int> data) {
    if (data.length < minHeaderBufferSize) {
      if (kDebugMode) {
        debugPrint(
            '⏳ OpusHeaderUtils: Buffer too small for complete headers (${data.length} < $minHeaderBufferSize)');
      }
      return null; // Need more data
    }

    if (!isOpusFormat(data)) {
      if (kDebugMode) {
        debugPrint('❌ OpusHeaderUtils: Not OPUS/OGG format');
      }
      return null;
    }

    // Scan for OpusHead and OpusTags
    int? opusHeadOffset;
    int? opusTagsOffset;
    int? opusDataOffset;

    final scanLimit = data.length.clamp(0, maxHeaderScanSize);

    for (int i = 0; i <= scanLimit - 8; i++) {
      // Check for OpusHead signature
      if (opusHeadOffset == null &&
          _matchesSignature(data, i, opusHeadSignature)) {
        opusHeadOffset = i;
        if (kDebugMode) {
          debugPrint('🎯 OpusHeaderUtils: Found OpusHead at offset $i');
        }
      }

      // Check for OpusTags signature
      if (opusTagsOffset == null &&
          _matchesSignature(data, i, opusTagsSignature)) {
        opusTagsOffset = i;
        if (kDebugMode) {
          debugPrint('🎯 OpusHeaderUtils: Found OpusTags at offset $i');
        }
      }

      // If we have both headers, look for the end of headers (start of audio data)
      if (opusHeadOffset != null &&
          opusTagsOffset != null &&
          opusDataOffset == null) {
        // Audio data typically starts after the second header page
        // We'll use a heuristic: look for the next OGG page after OpusTags
        final searchStart = opusTagsOffset + 8;
        for (int j = searchStart; j <= scanLimit - 4; j++) {
          if (_matchesSignature(data, j, oggPageSignature)) {
            // Found potential audio data page
            opusDataOffset = j;
            if (kDebugMode) {
              debugPrint('🎯 OpusHeaderUtils: Found audio data start at offset $j');
            }
            break;
          }
        }
      }
    }

    if (opusHeadOffset == null || opusTagsOffset == null) {
      if (kDebugMode) {
        debugPrint(
            '⏳ OpusHeaderUtils: Missing required headers - OpusHead: ${opusHeadOffset != null}, OpusTags: ${opusTagsOffset != null}');
      }
      return null; // Need more data
    }

    // Calculate total header size
    final headerEndOffset = opusDataOffset ??
        (opusTagsOffset! +
            256); // Conservative estimate if no audio data found yet

    final headerInfo = OpusHeaderInfo(
      opusHeadOffset: opusHeadOffset,
      opusTagsOffset: opusTagsOffset,
      audioDataOffset: opusDataOffset,
      totalHeaderSize: headerEndOffset,
      hasCompleteHeaders: opusDataOffset != null,
    );

    if (kDebugMode) {
      debugPrint('✅ OpusHeaderUtils: Parsed OPUS headers: $headerInfo');
    }

    return headerInfo;
  }

  /// Extract complete OPUS headers (OpusHead + OpusTags + any additional header pages)
  static Uint8List? extractOpusHeaders(
      List<int> data, OpusHeaderInfo headerInfo) {
    if (!headerInfo.hasCompleteHeaders) {
      if (kDebugMode) {
        debugPrint('⚠️ OpusHeaderUtils: Cannot extract incomplete headers');
      }
      return null;
    }

    if (data.length < headerInfo.totalHeaderSize) {
      if (kDebugMode) {
        debugPrint('⚠️ OpusHeaderUtils: Data too small for header extraction');
      }
      return null;
    }

    final headers =
        Uint8List.fromList(data.take(headerInfo.totalHeaderSize).toList());

    if (kDebugMode) {
      debugPrint(
          '📦 OpusHeaderUtils: Extracted ${headers.length} bytes of OPUS headers');
    }

    return headers;
  }

  /// Extract OPUS audio data (everything after headers)
  static Uint8List extractOpusAudioData(
      List<int> data, OpusHeaderInfo headerInfo) {
    final audioStartOffset =
        headerInfo.audioDataOffset ?? headerInfo.totalHeaderSize;

    if (audioStartOffset >= data.length) {
      return Uint8List(0); // No audio data yet
    }

    final audioData = Uint8List.fromList(data.skip(audioStartOffset).toList());

    if (kDebugMode) {
      debugPrint(
          '🎵 OpusHeaderUtils: Extracted ${audioData.length} bytes of OPUS audio data');
    }

    return audioData;
  }

  /// Helper: Check if signature matches at given offset
  static bool _matchesSignature(
      List<int> data, int offset, List<int> signature) {
    if (offset + signature.length > data.length) return false;

    for (int i = 0; i < signature.length; i++) {
      if (data[offset + i] != signature[i]) {
        return false;
      }
    }

    return true;
  }

  /// Combine OPUS headers with audio data
  static Uint8List combineOpusHeadersAndAudio(
      Uint8List headers, Uint8List audioData) {
    final combined = Uint8List(headers.length + audioData.length);
    combined.setRange(0, headers.length, headers);
    combined.setRange(headers.length, combined.length, audioData);

    if (kDebugMode) {
      debugPrint(
          '🔧 OpusHeaderUtils: Combined headers (${headers.length}B) + audio (${audioData.length}B) = ${combined.length}B total');
    }

    return combined;
  }
}

/// Information about OPUS headers found in the stream
class OpusHeaderInfo {
  final int opusHeadOffset;
  final int opusTagsOffset;
  final int? audioDataOffset;
  final int totalHeaderSize;
  final bool hasCompleteHeaders;

  const OpusHeaderInfo({
    required this.opusHeadOffset,
    required this.opusTagsOffset,
    this.audioDataOffset,
    required this.totalHeaderSize,
    required this.hasCompleteHeaders,
  });

  @override
  String toString() {
    return 'OpusHeaderInfo('
        'opusHead: $opusHeadOffset, '
        'opusTags: $opusTagsOffset, '
        'audioData: $audioDataOffset, '
        'headerSize: ${totalHeaderSize}B, '
        'complete: $hasCompleteHeaders'
        ')';
  }
}
