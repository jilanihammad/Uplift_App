import 'package:flutter/foundation.dart';
class WavHeaderUtils {
  static const int streamingPlaceholderSize = 0x7FFFFFFF;
  static const int standardWavHeaderSize = 44;
  static const String riffSignature = 'RIFF';
  static const String waveSignature = 'WAVE';
  static const String dataSignature = 'data';
  static WavHeaderInfo? parseWavHeader(List<int> audioData) {
    if (audioData.length < standardWavHeaderSize) {
      _debugLog(
          '⚠️ WavHeaderUtils: Data too small for WAV header (${audioData.length} bytes)');
      return null;
    }
    try {
      final riffHeader = String.fromCharCodes(audioData.take(4));
      if (riffHeader != riffSignature) {
        _debugLog('⚠️ WavHeaderUtils: Invalid RIFF signature: $riffHeader');
        return null;
      }
      final riffSize = _readUint32LE(audioData, 4);
      final waveHeader = String.fromCharCodes(audioData.skip(8).take(4));
      if (waveHeader != waveSignature) {
        _debugLog('⚠️ WavHeaderUtils: Invalid WAVE signature: $waveHeader');
        return null;
      }
      var offset = 12;
      String? fmtChunkId;
      int? audioFormat;
      int? numChannels;
      int? sampleRate;
      int? byteRate;
      int? blockAlign;
      int? bitsPerSample;
      if (offset + 8 <= audioData.length) {
        fmtChunkId = String.fromCharCodes(audioData.skip(offset).take(4));
        if (fmtChunkId == 'fmt ') {
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
          offset += 8 + chunkSize;
        }
      }
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
  static Uint8List createStreamingHeader(WavHeaderInfo originalHeader) {
    _debugLog(
        '🔧 WavHeaderUtils: Creating streaming header from: $originalHeader');
    final header = ByteData(44); // Standard 44-byte WAV header
    var offset = 0;
    header.setUint8(offset++, 'R'.codeUnitAt(0));
    header.setUint8(offset++, 'I'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint32(offset, streamingPlaceholderSize, Endian.little);
    offset += 4;
    header.setUint8(offset++, 'W'.codeUnitAt(0));
    header.setUint8(offset++, 'A'.codeUnitAt(0));
    header.setUint8(offset++, 'V'.codeUnitAt(0));
    header.setUint8(offset++, 'E'.codeUnitAt(0));
    header.setUint8(offset++, 'f'.codeUnitAt(0));
    header.setUint8(offset++, 'm'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, ' '.codeUnitAt(0));
    header.setUint32(offset, 16, Endian.little);
    offset += 4;
    header.setUint16(offset, originalHeader.audioFormat, Endian.little);
    offset += 2;
    header.setUint16(offset, originalHeader.numChannels, Endian.little);
    offset += 2;
    header.setUint32(offset, originalHeader.sampleRate, Endian.little);
    offset += 4;
    header.setUint32(offset, originalHeader.byteRate, Endian.little);
    offset += 4;
    header.setUint16(offset, originalHeader.blockAlign, Endian.little);
    offset += 2;
    header.setUint16(offset, originalHeader.bitsPerSample, Endian.little);
    offset += 2;
    header.setUint8(offset++, 'd'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));
    header.setUint8(offset++, 't'.codeUnitAt(0));
    header.setUint8(offset++, 'a'.codeUnitAt(0));
    header.setUint32(offset, streamingPlaceholderSize, Endian.little);
    offset += 4;
    _debugLog(
        '✅ WavHeaderUtils: Created streaming header (${header.lengthInBytes} bytes)');
    _debugLog(
        '🔧 Original data size: ${originalHeader.dataChunkSize}, streaming size: $streamingPlaceholderSize');
    return header.buffer.asUint8List();
  }
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
  static Uint8List combineHeaderAndPcm(
      Uint8List streamingHeader, Uint8List pcmData) {
    final combined = Uint8List(streamingHeader.length + pcmData.length);
    combined.setRange(0, streamingHeader.length, streamingHeader);
    combined.setRange(streamingHeader.length, combined.length, pcmData);
    _debugLog(
        '🔧 WavHeaderUtils: Combined header (${streamingHeader.length}B) + PCM (${pcmData.length}B) = ${combined.length}B total');
    return combined;
  }
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
    header.setUint8(offset++, 'R'.codeUnitAt(0));
    header.setUint8(offset++, 'I'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint8(offset++, 'F'.codeUnitAt(0));
    header.setUint32(offset, riffSize, Endian.little);
    offset += 4;
    header.setUint8(offset++, 'W'.codeUnitAt(0));
    header.setUint8(offset++, 'A'.codeUnitAt(0));
    header.setUint8(offset++, 'V'.codeUnitAt(0));
    header.setUint8(offset++, 'E'.codeUnitAt(0));
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
  static int _readUint32LE(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
  static int _readUint16LE(List<int> data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }
  static void _writeUint32LE(List<int> data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }
  static void _debugLog(String message) {
    if (!kDebugMode) {
      return;
    }
  }
  static bool isStreamingFriendly(List<int> audioData) {
    final headerInfo = parseWavHeader(audioData);
    if (headerInfo == null) {
      _debugLog(
          '⚠️ WavHeaderUtils: Cannot determine if streaming-friendly - invalid header');
      return false;
    }
    const int unknownLengthMarker = 0xFFFFFFFF; // 4294967295
    final bool riffStreamingFriendly =
        headerInfo.riffSize == unknownLengthMarker;
    final bool dataStreamingFriendly =
        headerInfo.dataChunkSize == unknownLengthMarker;
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
