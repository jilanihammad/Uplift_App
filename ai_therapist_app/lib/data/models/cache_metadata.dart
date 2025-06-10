class CacheMetadata {
  final String cacheKey;
  final bool shouldCache;
  final int cacheDuration; // seconds
  final List<String> contextTags;
  final String emotionalTone;

  const CacheMetadata({
    required this.cacheKey,
    required this.shouldCache,
    required this.cacheDuration,
    required this.contextTags,
    required this.emotionalTone,
  });

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      cacheKey: json['cache_key'] ?? '',
      shouldCache: json['should_cache'] ?? true,
      cacheDuration: json['cache_duration'] ?? 604800, // 7 days default
      contextTags: List<String>.from(json['context_tags'] ?? []),
      emotionalTone: json['emotional_tone'] ?? 'neutral',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cache_key': cacheKey,
      'should_cache': shouldCache,
      'cache_duration': cacheDuration,
      'context_tags': contextTags,
      'emotional_tone': emotionalTone,
    };
  }
}

class TtsResponse {
  final String responseText;
  final String audioUrl;
  final CacheMetadata cacheMetadata;

  const TtsResponse({
    required this.responseText,
    required this.audioUrl,
    required this.cacheMetadata,
  });

  factory TtsResponse.fromJson(Map<String, dynamic> json) {
    return TtsResponse(
      responseText: json['response_text'] ?? '',
      audioUrl: json['audio_url'] ?? '',
      cacheMetadata: CacheMetadata.fromJson(json['cache_metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'response_text': responseText,
      'audio_url': audioUrl,
      'cache_metadata': cacheMetadata.toJson(),
    };
  }
}
