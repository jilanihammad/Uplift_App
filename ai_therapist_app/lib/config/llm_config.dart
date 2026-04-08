library;
enum LLMProvider {
  openai,
  anthropic,
  google,
  groq,
  custom,
}
class LLMModelConfig {
  final String modelId;
  final String endpoint;
  final Map<String, String> headers;
  final Map<String, dynamic> defaultParams;
  final String apiKeyEnvVar;
  final double? maxTokens;
  final double? temperature;
  const LLMModelConfig({
    required this.modelId,
    required this.endpoint,
    required this.headers,
    this.defaultParams = const {},
    required this.apiKeyEnvVar,
    this.maxTokens,
    this.temperature,
  });
}
class TTSModelConfig {
  final String modelId;
  final String endpoint;
  final Map<String, String> headers;
  final Map<String, dynamic> defaultParams;
  final String apiKeyEnvVar;
  final String? voice;
  const TTSModelConfig({
    required this.modelId,
    required this.endpoint,
    required this.headers,
    this.defaultParams = const {},
    required this.apiKeyEnvVar,
    this.voice,
  });
}
class LLMConfig {
  // =================================================================
  // =================================================================
  static const LLMProvider _activeLLMProvider = LLMProvider.groq;
  static const String _activeLLMModelId = 'llama-4-scout-17b-16e-instruct';
  static const LLMProvider _defaultTTSProvider = LLMProvider.openai;
  static const String _defaultTTSModelId = 'gpt-4o-mini-tts';
  static const String _defaultTTSVoice = 'sage';
  static const Map<String, String> _voiceDisplayNames = {
    'sage': 'Maya',
    'coral': 'Alie',
    'nova': 'Cindy',
  };
  static const int _defaultTTSSampleRate = 24000;
  static const String _defaultTTSAudioEncoding = 'LINEAR16';
  static const String _defaultTTSResponseFormat = 'wav';
  static const bool _defaultTTSSupportsStreaming = true;
  static const String _defaultTTSMode = 'rest';
  static const String _defaultTtsMimeType = 'audio/wav';
  static LLMProvider? _overrideTTSProvider;
  static String? _overrideTTSModelId;
  static String? _overrideTTSVoice;
  static int? _overrideTTSSampleRate;
  static String? _overrideTTSAudioEncoding;
  static String? _overrideTTSResponseFormat;
  static bool? _overrideTTSSupportsStreaming;
  static String? _overrideTTSMode;
  static String? _overrideTtsMimeType;
  // =================================================================
  // =================================================================
  static const Map<String, LLMModelConfig> _openaiModels = {
    'gpt-4o': LLMModelConfig(
      modelId: 'gpt-4o',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
        'stream': false,
      },
      apiKeyEnvVar: 'OPENAI_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
    'gpt-4o-mini': LLMModelConfig(
      modelId: 'gpt-4o-mini',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
        'stream': false,
      },
      apiKeyEnvVar: 'OPENAI_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
  };
  static const Map<String, LLMModelConfig> _anthropicModels = {
    'claude-3-5-sonnet-20241022': LLMModelConfig(
      modelId: 'claude-3-5-sonnet-20241022',
      endpoint: 'https://api.anthropic.com/v1/messages',
      headers: {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
      },
      apiKeyEnvVar: 'ANTHROPIC_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
    'claude-3-haiku-20240307': LLMModelConfig(
      modelId: 'claude-3-haiku-20240307',
      endpoint: 'https://api.anthropic.com/v1/messages',
      headers: {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
      },
      apiKeyEnvVar: 'ANTHROPIC_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
  };
  static const Map<String, LLMModelConfig> _googleModels = {
    'gemini-1.5-pro': LLMModelConfig(
      modelId: 'gemini-1.5-pro',
      endpoint:
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'generationConfig': {
          'maxOutputTokens': 512,
          'temperature': 0.7,
        },
      },
      apiKeyEnvVar: 'GOOGLE_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
    'gemini-2.5-flash': LLMModelConfig(
      modelId: 'gemini-2.5-flash',
      endpoint:
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'generationConfig': {
          'maxOutputTokens': 512,
          'temperature': 0.7,
        },
      },
      apiKeyEnvVar: 'GOOGLE_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
  };
  static const Map<String, LLMModelConfig> _groqModels = {
    'llama-3.1-70b-versatile': LLMModelConfig(
      modelId: 'llama-3.1-70b-versatile',
      endpoint: 'https://api.groq.com/openai/v1/chat/completions',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
        'stream': false,
      },
      apiKeyEnvVar: 'GROQ_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
    'llama-3.1-8b-instant': LLMModelConfig(
      modelId: 'llama-3.1-8b-instant',
      endpoint: 'https://api.groq.com/openai/v1/chat/completions',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'max_tokens': 512,
        'temperature': 0.7,
        'stream': false,
      },
      apiKeyEnvVar: 'GROQ_API_KEY',
      maxTokens: 512,
      temperature: 0.7,
    ),
  };
  static const Map<String, TTSModelConfig> _openaiTTSModels = {
    'tts-1': TTSModelConfig(
      modelId: 'tts-1',
      endpoint: 'https://api.openai.com/v1/audio/speech',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'response_format': 'mp3',
        'speed': 1.0,
      },
      apiKeyEnvVar: 'OPENAI_API_KEY',
      voice: 'alloy',
    ),
    'tts-1-hd': TTSModelConfig(
      modelId: 'tts-1-hd',
      endpoint: 'https://api.openai.com/v1/audio/speech',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'response_format': 'mp3',
        'speed': 1.0,
      },
      apiKeyEnvVar: 'OPENAI_API_KEY',
      voice: 'alloy',
    ),
  };
  static const Map<String, TTSModelConfig> _googleTTSModels = {
    'gemini-2.5-flash-preview-tts': TTSModelConfig(
      modelId: 'gemini-2.5-flash-preview-tts',
      endpoint:
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent',
      headers: {
        'Content-Type': 'application/json',
      },
      defaultParams: {
        'audio_encoding': 'LINEAR16',
        'response_format': 'wav',
        'sample_rate_hz': 24000,
      },
      apiKeyEnvVar: 'GOOGLE_API_KEY',
      voice: 'kore',
    ),
  };
  // =================================================================
  // =================================================================
  static LLMModelConfig get currentLLMConfig {
    final models = _getModelsForProvider(_activeLLMProvider);
    final config = models[_activeLLMModelId];
    if (config == null) {
      throw Exception(
          'Model $_activeLLMModelId not found for provider $_activeLLMProvider. '
          'Available models: ${models.keys.join(', ')}');
    }
    return config;
  }
  static TTSModelConfig get currentTTSConfig {
    final provider = activeTTSProvider;
    final modelId = activeTTSModelId;
    final models = _getTTSModelsForProvider(provider);
    final baseConfig = models[modelId];
    if (baseConfig == null) {
      throw Exception('TTS Model $modelId not found for provider $provider. '
          'Available models: ${models.keys.join(', ')}');
    }
    final mergedParams = Map<String, dynamic>.from(baseConfig.defaultParams);
    mergedParams['voice'] = activeTTSVoice;
    mergedParams['sample_rate_hz'] = activeTTSSampleRate;
    mergedParams['audio_encoding'] = activeTTSAudioEncoding;
    mergedParams['response_format'] = activeTTSResponseFormat;
    mergedParams['mode'] = activeTTSMode;
    mergedParams['mime_type'] = activeTtsMimeType;
    return TTSModelConfig(
      modelId: modelId,
      endpoint: baseConfig.endpoint,
      headers: baseConfig.headers,
      defaultParams: mergedParams,
      apiKeyEnvVar: baseConfig.apiKeyEnvVar,
      voice: activeTTSVoice,
    );
  }
  static LLMProvider get activeLLMProvider => _activeLLMProvider;
  static LLMProvider get activeTTSProvider =>
      _overrideTTSProvider ?? _defaultTTSProvider;
  static String get activeLLMModelId => _activeLLMModelId;
  static String get activeTTSModelId =>
      _overrideTTSModelId ?? _defaultTTSModelId;
  static String get activeTTSVoice => _overrideTTSVoice ?? _defaultTTSVoice;
  static int get activeTTSSampleRate =>
      _overrideTTSSampleRate ?? _defaultTTSSampleRate;
  static String get activeTTSAudioEncoding =>
      _overrideTTSAudioEncoding ?? _defaultTTSAudioEncoding;
  static String get activeTTSResponseFormat =>
      _overrideTTSResponseFormat ?? _defaultTTSResponseFormat;
  static bool get activeTTSSupportsStreaming =>
      _overrideTTSSupportsStreaming ?? _defaultTTSSupportsStreaming;
  static String get activeTTSMode => _overrideTTSMode ?? _defaultTTSMode;
  static String get activeTtsMimeType =>
      _overrideTtsMimeType ?? _defaultTtsMimeType;
  static Map<String, String> get voiceDisplayNames =>
      Map.unmodifiable(_voiceDisplayNames);
  static List<String> get availableVoiceIds =>
      List.unmodifiable(_voiceDisplayNames.keys);
  static String displayNameForVoice(String voiceId) =>
      _voiceDisplayNames[voiceId] ?? voiceId;
  static void setPreferredTtsVoice(String voiceId) {
    if (voiceId.isEmpty) {
      return;
    }
    _overrideTTSVoice = voiceId;
  }
  static void applyRemoteTtsConfig({
    required String provider,
    String? model,
    String? voice,
    int? sampleRateHz,
    String? audioEncoding,
    String? responseFormat,
    bool? supportsStreaming,
    String? mode,
    String? mimeType,
  }) {
    final normalizedProvider = _providerFromString(provider);
    if (normalizedProvider != null) {
      _overrideTTSProvider = normalizedProvider;
    }
    if (model != null && model.isNotEmpty) {
      _overrideTTSModelId = model;
    }
    if (voice != null && voice.isNotEmpty) {
      setPreferredTtsVoice(voice);
    }
    if (sampleRateHz != null && sampleRateHz > 0) {
      _overrideTTSSampleRate = sampleRateHz;
    }
    if (audioEncoding != null && audioEncoding.isNotEmpty) {
      _overrideTTSAudioEncoding = audioEncoding;
    }
    if (responseFormat != null && responseFormat.isNotEmpty) {
      _overrideTTSResponseFormat = responseFormat;
    }
    if (supportsStreaming != null) {
      _overrideTTSSupportsStreaming = supportsStreaming;
    }
    if (mode != null && mode.isNotEmpty) {
      _overrideTTSMode = mode;
    }
    if (mimeType != null && mimeType.isNotEmpty) {
      _overrideTtsMimeType = mimeType;
    }
  }
  static LLMProvider? _providerFromString(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final normalized = value.toLowerCase();
    for (final provider in LLMProvider.values) {
      if (provider.name.toLowerCase() == normalized) {
        return provider;
      }
    }
    return null;
  }
  static Map<String, LLMModelConfig> getAvailableModelsForProvider(
      LLMProvider provider) {
    return _getModelsForProvider(provider);
  }
  static Map<String, TTSModelConfig> getAvailableTTSModelsForProvider(
      LLMProvider provider) {
    return _getTTSModelsForProvider(provider);
  }
  // =================================================================
  // =================================================================
  static Map<String, LLMModelConfig> _getModelsForProvider(
      LLMProvider provider) {
    switch (provider) {
      case LLMProvider.openai:
        return _openaiModels;
      case LLMProvider.anthropic:
        return _anthropicModels;
      case LLMProvider.google:
        return _googleModels;
      case LLMProvider.groq:
        return _groqModels;
      case LLMProvider.custom:
        return {}; // Custom configurations would be loaded differently
    }
  }
  static Map<String, TTSModelConfig> _getTTSModelsForProvider(
      LLMProvider provider) {
    switch (provider) {
      case LLMProvider.openai:
        return _openaiTTSModels;
      case LLMProvider.google:
        return _googleTTSModels;
      case LLMProvider.anthropic:
      case LLMProvider.groq:
      case LLMProvider.custom:
        return {}; // These providers don't have TTS models configured yet
    }
  }
  static bool validateConfiguration() {
    try {
      final llmConfig = currentLLMConfig;
      final ttsConfig = currentTTSConfig;
      return true;
    } catch (e) {
      return false;
    }
  }
}
