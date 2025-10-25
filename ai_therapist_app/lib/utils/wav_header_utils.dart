import 'package:flutter/foundation.dart';

/// Utility for modifying WAV headers to enable true streaming audio playback
///
/// Standard WAV files specify exact data chunk sizes, causing ExoPlayer to stop
/// when it reaches that limit. This utility modifies headers to use "unknown length"
/// placeholders, allowing continuous streaming until the stream closes naturally.
class WavHeaderUtils {
  /// Placeholder size for unlimited streaming (0x7FFFFFFF)
  /// ExoPlayer treats this as "unknown length" and continues reading until EOF
  static const int streamingPlaceholderSize = 0x7FFFFFFF;

  /// Standard WAV header size (44 bytes for PCM format)
  static const int standardWavHeaderSize = 44;

  /// RIFF header signature
  static const String riffSignature = 'RIFF';

  /// WAVE format signature
  static const String waveSignature = 'WAVE';

  /// Data chunk signature
  static const String dataSignature = 'data';

  /// Extract and validate WAV header information from audio data
  ///
  /// Returns null if the data doesn't contain a valid WAV header
  /// Returns WavHeaderInfo if valid header is found
  static WavHeaderInfo? parseWavHeader(List<int> audioData) {
    if (audioData.length < standardWavHeaderSize) {
      _debugLog(
          '⚠️ WavHeaderUtils: Data too small for WAV header (${audioData.length} bytes)');
      return null;
    }

    try {
      // Check RIFF signature (bytes 0-3)
      final riffHeader = String.fromCharCodes(audioData.take(4));
      if (riffHeader != riffSignature) {
        _debugLog('⚠️ WavHeaderUtils: Invalid RIFF signature: $riffHeader');
        return null;
      }

      // Extract RIFF chunk size (bytes 4-7, little endian)
      final riffSize = _readUint32LE(audioData, 4);

      // Check WAVE signature (bytes 8-11)
      final waveHeader = String.fromCharCodes(audioData.skip(8).take(4));
      if (waveHeader != waveSignature) {
        _debugLog('⚠️ WavHeaderUtils: Invalid WAVE signature: $waveHeader');
        return null;
      }

      // Find fmt chunk (should start at byte 12)
      var offset = 12;
      String? fmtChunkId;
      int? audioFormat;
      int? numChannels;
      int? sampleRate;
      int? byteRate;
      int? blockAlign;
      int? bitsPerSample;

      // Parse fmt chunk
      if (offset + 8 <= audioData.length) {
        fmtChunkId = String.fromCharCodes(audioData.skip(offset).take(4));
        if (fmtChunkId == 'fmt ') {
          // Skip fmt chunk size, we know it's 16 for PCM
          offset += 8;

          if (offset + 16 <= audioData.length) {
            audioFormat = _readUint16LE(audioData, offset);
            numChannels = _readUint16LE(audioData, offset + 2);
            sampleRate = _readUint32LE(audioData, offset + 4);
            byteRate = _readUint32LE(audioData, offset + 8);
            blockAlign = _readUint16LE(audioData, offset + 12);
            bitsPerSample = _readUint16LE(audioData, offset + 14);
            offset += 16;
          }
        }
      }

      // Find data chunk (skip any additional chunks)
      String? dataChunkId;
      int? dataChunkSize;
      int? dataChunkOffset;

      while (offset + 8 <= audioData.length) {
        final chunkId = String.fromCharCodes(audioData.skip(offset).take(4));
        final chunkSize = _readUint32LE(audioData, offset + 4);

        if (chunkId == dataSignature) {
          dataChunkId = chunkId;
          dataChunkSize = chunkSize;
          dataChunkOffset = offset;
          break;
        } else {
          // Skip this chunk
          offset += 8 + chunkSize;
        }
      }

      // Validate required fields
      if (fmtChunkId == null ||
          dataChunkId == null ||
          audioFormat == null ||
          numChannels == null ||
          sampleRate == null ||
          dataChunkSize == null ||
          dataChunkOffset == null) {
        _debugLog('⚠️ WavHeaderUtils: Missing required WAV header fields');
        return null;
      }

      final headerInfo = WavHeaderInfo(
        riffSize: riffSize,
        audioFormat: audioFormat,
        numChannels: numChannels,
        sampleRate: sampleRate,
        byteRate: byteRate ?? 0,
        blockAlign: blockAlign ?? 0,
        bitsPerSample: bitsPerSample ?? 16,
        dataChunkSize: dataChunkSize,
        dataChunkOffset: dataChunkOffset,
        totalHeaderSize: dataChunkOffset + 8, // Include data chunk header
      );

      _debugLog('✅ WavHeaderUtils: Parsed WAV header: $headerInfo');

      return headerInfo;
    } catch (e) {
      _debugLog('❌ WavHeaderUtils: Error parsing WAV header: $e');
      return null;
    }
  }

  /// Create streaming-friendly WAV header with placeholder sizes
  ///
  /// Takes the original header info and generates a new header with:
  /// - RIFF chunk size set to streaming placeholder
  /// - Data chunk size set to streaming placeholder
  /// - All other format parameters preserved
  static Uint8List createStreamingHeader(WavHeaderInfo originalHeader) {
    _debugLog(
        '🔧 WavHeaderUtils: Creating streaming header from: $originalHeader');

    final header = ByteData(44); // Standard 44-byte WAV header
    var offset = 0;

    // RIFF header
    header.setUint8(offset++, 'R'.codeUnitAt(0));
    header.setUint8(offset++, 'I'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));

    // RIFF chunk size (placeholder for streaming)
    header.setUint32(offset, streamingPlaceholderSize, Endian.little);
    offset += 4;

    // WAVE format
    header.setUint8(offset++, 'W'.codeUnitAt(0));
    header.setUint8(offset++, 'A'.codeUnitAt(0));
    header.setUint8(offset++, 'V'.codeUnitAt(0));
    header.setUint8(offset++, 'E'.codeUnitAt(0));

    // fmt subchunk
    header.setUint8(offset++, 'f'.codeUnitAt(0));
    header.setUint8(offset++, 'm'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, ' '.codeUnitAt(0));

    // fmt subchunk size (16 for PCM)
    header.setUint32(offset, 16, Endian.little);
    offset += 4;

    // Audio format (preserve original)
    header.setUint16(offset, originalHeader.audioFormat, Endian.little);
    offset += 2;

    // Number of channels (preserve original)
    header.setUint16(offset, originalHeader.numChannels, Endian.little);
    offset += 2;

    // Sample rate (preserve original)
    header.setUint32(offset, originalHeader.sampleRate, Endian.little);
    offset += 4;

    // Byte rate (preserve original)
    header.setUint32(offset, originalHeader.byteRate, Endian.little);
    offset += 4;

    // Block align (preserve original)
    header.setUint16(offset, originalHeader.blockAlign, Endian.little);
    offset += 2;

    // Bits per sample (preserve original)
    header.setUint16(offset, originalHeader.bitsPerSample, Endian.little);
    offset += 2;

    // data subchunk
    header.setUint8(offset++, 'd'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));

    // data subchunk size (placeholder for streaming)
    header.setUint32(offset, streamingPlaceholderSize, Endian.little);
    offset += 4;

    _debugLog(
        '✅ WavHeaderUtils: Created streaming header (${header.lengthInBytes} bytes)');
    _debugLog(
        '🔧 Original data size: ${originalHeader.dataChunkSize}, streaming size: $streamingPlaceholderSize');

    return header.buffer.asUint8List();
  }

  /// Extract PCM data from WAV audio buffer (skip header)
  ///
  /// Returns the raw PCM audio data without any WAV headers
  static Uint8List extractPcmData(
      List<int> audioData, WavHeaderInfo headerInfo) {
    final pcmStartOffset = headerInfo.totalHeaderSize;

    if (pcmStartOffset >= audioData.length) {
      _debugLog('⚠️ WavHeaderUtils: No PCM data found after header');
      return Uint8List(0);
    }

    final pcmData = Uint8List.fromList(audioData.skip(pcmStartOffset).toList());

    _debugLog(
        '📊 WavHeaderUtils: Extracted ${pcmData.length} bytes of PCM data');

    return pcmData;
  }

  /// Combine streaming header with PCM data
  ///
  /// Creates a complete audio buffer with streaming-friendly header + PCM data
  static Uint8List combineHeaderAndPcm(
      Uint8List streamingHeader, Uint8List pcmData) {
    final combined = Uint8List(streamingHeader.length + pcmData.length);
    combined.setRange(0, streamingHeader.length, streamingHeader);
    combined.setRange(streamingHeader.length, combined.length, pcmData);

    _debugLog(
        '🔧 WavHeaderUtils: Combined header (${streamingHeader.length}B) + PCM (${pcmData.length}B) = ${combined.length}B total');

    return combined;
  }

  /// Logs detailed header information for debugging diagnostics.
  static void logWavHeaderDetails(List<int> audioData, String context) {
    final header = parseWavHeader(audioData);
    if (header == null) {
      _debugLog('❌ WavHeaderUtils[$context]: invalid or incomplete WAV header');
      return;
    }

    final payloadBytes =
        (audioData.length - header.totalHeaderSize).clamp(0, audioData.length);

    _debugLog('📋 WavHeaderUtils[$context] header details:');
    _debugLog(
        '  Channels: ${header.numChannels}, Sample rate: ${header.sampleRate} Hz, Bits: ${header.bitsPerSample}');
    _debugLog(
        '  Byte rate: ${header.byteRate}, Block align: ${header.blockAlign}');
    _debugLog(
        '  RIFF size: ${header.riffSize}, Data size: ${header.dataChunkSize}, Payload bytes: $payloadBytes');
  }

  /// Validates RIFF/data chunk sizes and corrects them if necessary.
  static List<int> validateAndFixWavHeader(List<int> audioData) {
    if (audioData.length < standardWavHeaderSize) {
      _debugLog(
          '⚠️ WavHeaderUtils: Cannot fix header; buffer smaller than $standardWavHeaderSize bytes');
      return List<int>.from(audioData);
    }

    final header = parseWavHeader(audioData);
    if (header == null) {
      return List<int>.from(audioData);
    }

    final fixed = List<int>.from(audioData);
    final payloadSize =
        (fixed.length - header.totalHeaderSize).clamp(0, fixed.length).toInt();
    final expectedRiffSize =
        (payloadSize + standardWavHeaderSize - 8).clamp(0, 0xFFFFFFFF).toInt();

    bool changed = false;
    const unknownMarker = 0xFFFFFFFF;

    if (header.riffSize == unknownMarker ||
        header.riffSize != expectedRiffSize) {
      _writeUint32LE(fixed, 4, expectedRiffSize);
      changed = true;
    }

    final dataChunkSizeOffset = header.dataChunkOffset + 4;
    if (header.dataChunkSize == unknownMarker ||
        header.dataChunkSize != payloadSize) {
      _writeUint32LE(fixed, dataChunkSizeOffset, payloadSize);
      changed = true;
    }

    if (changed) {
      _debugLog(
          '✅ WavHeaderUtils: Corrected WAV header sizes (payload: $payloadSize bytes)');
    } else {
      _debugLog('ℹ️ WavHeaderUtils: WAV header already consistent');
    }

    return fixed;
  }

  /// Creates a standard PCM WAV header for the provided payload size.
  static List<int> createWavHeader({
    required int dataSize,
    int sampleRate = 44100,
    int bitsPerSample = 16,
    int numChannels = 1,
  }) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final riffSize =
        (dataSize + standardWavHeaderSize - 8).clamp(0, 0xFFFFFFFF).toInt();

    final header = ByteData(standardWavHeaderSize);
    var offset = 0;

    // RIFF chunk
    header.setUint8(offset++, 'R'.codeUnitAt(0));
    header.setUint8(offset++, 'I'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint32(offset, riffSize, Endian.little);
    offset += 4;

    // WAVE
    header.setUint8(offset++, 'W'.codeUnitAt(0));
    header.setUint8(offset++, 'A'.codeUnitAt(0));
    header.setUint8(offset++, 'V'.codeUnitAt(0));
    header.setUint8(offset++, 'E'.codeUnitAt(0));

    // fmt chunk
    header.setUint8(offset++, 'f'.codeUnitAt(0));
    header.setUint8(offset++, 'm'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, ' '.codeUnitAt(0));
    header.setUint32(offset, 16, Endian.little);
    offset += 4;
    header.setUint16(offset, 1, Endian.little); // PCM format
    offset += 2;
    header.setUint16(offset, numChannels, Endian.little);
    offset += 2;
    header.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    header.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    header.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    header.setUint16(offset, bitsPerSample, Endian.little);
    offset += 2;

    // data chunk
    header.setUint8(offset++, 'd'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));
    header.setUint32(
        offset, dataSize.clamp(0, 0xFFFFFFFF).toInt(), Endian.little);

    _debugLog(
        '🎛️ WavHeaderUtils: Created WAV header (channels: $numChannels, sampleRate: $sampleRate, data: $dataSize bytes)');

    return header.buffer.asUint8List();
  }

  /// Helper: Read 32-bit little-endian unsigned integer
  static int _readUint32LE(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Helper: Read 16-bit little-endian unsigned integer
  static int _readUint16LE(List<int> data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  /// Helper: Write 32-bit little-endian unsigned integer.
  static void _writeUint32LE(List<int> data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }

  /// Debug logging utility routed through `debugPrint` in debug mode.
  static void _debugLog(String message) {
    if (!kDebugMode) {
      return;
    }
    // ignore: avoid_print
    debugPrint(message);
  }

  /// Check if WAV headers are already streaming-friendly
  ///
  /// Returns true if the WAV file already has unlimited streaming markers:
  /// - RIFF chunk size = 0xFFFFFFFF (unknown length)
  /// - Data chunk size = 0xFFFFFFFF (unknown length)
  ///
  /// These markers indicate the backend already sent perfect streaming headers
  /// and no modification is needed.
  static bool isStreamingFriendly(List<int> audioData) {
    final headerInfo = parseWavHeader(audioData);

    if (headerInfo == null) {
      _debugLog(
          '⚠️ WavHeaderUtils: Cannot determine if streaming-friendly - invalid header');
      return false;
    }

    // Check for standard unknown length markers
    const int unknownLengthMarker = 0xFFFFFFFF; // 4294967295

    final bool riffStreamingFriendly =
        headerInfo.riffSize == unknownLengthMarker;
    final bool dataStreamingFriendly =
        headerInfo.dataChunkSize == unknownLengthMarker;

    // Consider streaming-friendly if either RIFF or data chunk has unknown length marker
    final bool isStreamingFriendly =
        riffStreamingFriendly || dataStreamingFriendly;

    _debugLog('🔍 WavHeaderUtils: Streaming compatibility check:');
    _debugLog(
        '  RIFF size: ${headerInfo.riffSize} (streaming: $riffStreamingFriendly)');
    _debugLog(
        '  Data size: ${headerInfo.dataChunkSize} (streaming: $dataStreamingFriendly)');
    _debugLog('  Overall streaming-friendly: $isStreamingFriendly');

    return isStreamingFriendly;
  }
}

/// Information extracted from a WAV header
class WavHeaderInfo {
  final int riffSize;
  final int audioFormat;
  final int numChannels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final int dataChunkSize;
  final int dataChunkOffset;
  final int totalHeaderSize;

  const WavHeaderInfo({
    required this.riffSize,
    required this.audioFormat,
    required this.numChannels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataChunkSize,
    required this.dataChunkOffset,
    required this.totalHeaderSize,
  });

  @override
  String toString() {
    return 'WavHeaderInfo('
        'format: $audioFormat, '
        'channels: $numChannels, '
        'sampleRate: ${sampleRate}Hz, '
        'bits: $bitsPerSample, '
        'dataSize: ${dataChunkSize}B'
        ')';
  }
}
