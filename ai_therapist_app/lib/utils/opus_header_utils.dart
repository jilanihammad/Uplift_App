import 'package:flutter/foundation.dart';
class OpusHeaderUtils {
  static const List<int> oggPageSignature = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
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
  static const int minHeaderBufferSize = 2048; // 2KB buffer for headers
  static const int maxHeaderScanSize = 8192; // 8KB max scan
  static bool isOpusFormat(List<int> data) {
    if (data.length < 4) return false;
    for (int i = 0; i < 4; i++) {
      if (data[i] != oggPageSignature[i]) {
        return false;
      }
    }
    return true;
  }
  static bool isWavFormat(List<int> data) {
    if (data.length < 12) return false;
    final riffSignature = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
    final waveSignature = [0x57, 0x41, 0x56, 0x45]; // "WAVE"
    for (int i = 0; i < 4; i++) {
      if (data[i] != riffSignature[i]) {
        return false;
      }
    }
    for (int i = 0; i < 4; i++) {
      if (data[8 + i] != waveSignature[i]) {
        return false;
      }
    }
    return true;
  }
  static OpusHeaderInfo? parseOpusHeaders(List<int> data) {
    if (data.length < minHeaderBufferSize) {
      return null; // Need more data
    }
    if (!isOpusFormat(data)) {
      return null;
    }
    int? opusHeadOffset;
    int? opusTagsOffset;
    int? opusDataOffset;
    final scanLimit = data.length.clamp(0, maxHeaderScanSize);
    for (int i = 0; i <= scanLimit - 8; i++) {
      if (opusHeadOffset == null &&
          _matchesSignature(data, i, opusHeadSignature)) {
        opusHeadOffset = i;
      }
      if (opusTagsOffset == null &&
          _matchesSignature(data, i, opusTagsSignature)) {
        opusTagsOffset = i;
      }
      if (opusHeadOffset != null &&
          opusTagsOffset != null &&
          opusDataOffset == null) {
        final searchStart = opusTagsOffset + 8;
        for (int j = searchStart; j <= scanLimit - 4; j++) {
          if (_matchesSignature(data, j, oggPageSignature)) {
            opusDataOffset = j;
            break;
          }
        }
      }
    }
    if (opusHeadOffset == null || opusTagsOffset == null) {
      return null; // Need more data
    }
    final headerEndOffset = opusDataOffset ??
        (opusTagsOffset +
            256); // Conservative estimate if no audio data found yet
    final headerInfo = OpusHeaderInfo(
      opusHeadOffset: opusHeadOffset,
      opusTagsOffset: opusTagsOffset,
      audioDataOffset: opusDataOffset,
      totalHeaderSize: headerEndOffset,
      hasCompleteHeaders: opusDataOffset != null,
    );
    return headerInfo;
  }
  static Uint8List? extractOpusHeaders(
      List<int> data, OpusHeaderInfo headerInfo) {
    if (!headerInfo.hasCompleteHeaders) {
      return null;
    }
    if (data.length < headerInfo.totalHeaderSize) {
      return null;
    }
    final headers =
        Uint8List.fromList(data.take(headerInfo.totalHeaderSize).toList());
    return headers;
  }
  static Uint8List extractOpusAudioData(
      List<int> data, OpusHeaderInfo headerInfo) {
    final audioStartOffset =
        headerInfo.audioDataOffset ?? headerInfo.totalHeaderSize;
    if (audioStartOffset >= data.length) {
      return Uint8List(0); // No audio data yet
    }
    final audioData = Uint8List.fromList(data.skip(audioStartOffset).toList());
    return audioData;
  }
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
  static Uint8List combineOpusHeadersAndAudio(
      Uint8List headers, Uint8List audioData) {
    final combined = Uint8List(headers.length + audioData.length);
    combined.setRange(0, headers.length, headers);
    combined.setRange(headers.length, combined.length, audioData);
    return combined;
  }
}
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
