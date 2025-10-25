class TtsConfigDto {
  final String provider;
  final String? model;
  final String? voice;
  final int? sampleRateHz;
  final String? audioEncoding;
  final String? responseFormat;
  final bool? supportsStreaming;

  const TtsConfigDto({
    required this.provider,
    this.model,
    this.voice,
    this.sampleRateHz,
    this.audioEncoding,
    this.responseFormat,
    this.supportsStreaming,
  });

  factory TtsConfigDto.fromJson(Map<String, dynamic> json) {
    return TtsConfigDto(
      provider: (json['provider'] as String?)?.trim() ?? '',
      model: (json['model'] as String?)?.trim(),
      voice: (json['voice'] as String?)?.trim(),
      sampleRateHz: json['sample_rate_hz'] is int
          ? json['sample_rate_hz'] as int
          : int.tryParse(json['sample_rate_hz']?.toString() ?? ''),
      audioEncoding: (json['audio_encoding'] as String?)?.trim(),
      responseFormat: (json['response_format'] as String?)?.trim(),
      supportsStreaming: json['supports_streaming'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'model': model,
      'voice': voice,
      'sample_rate_hz': sampleRateHz,
      'audio_encoding': audioEncoding,
      'response_format': responseFormat,
      'supports_streaming': supportsStreaming,
    };
  }
}
