/// Centralized LLM Configuration - Change LLM providers and models in one place
/// This configuration system allows easy switching between OpenAI, Anthropic, Google, and other providers
/// by simply changing the active provider and model IDs in one location.
library;

import 'package:flutter/foundation.dart';

/// Supported LLM Providers
enum LLMProvider {
  openai,
  anthropic,
  google,
  groq,
  custom,
}

/// LLM Model Configuration
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

/// TTS Provider Configuration
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

/// Centralized LLM Configuration Class
class LLMConfig {
  // =================================================================
  // CONFIGURATION SECTION - CHANGE THESE TO SWITCH PROVIDERS/MODELS
  // =================================================================

  /// Active LLM Provider - Change this to switch providers
  static const LLMProvider _activeLLMProvider = LLMProvider.groq;

  /// Active LLM Model ID for the selected provider
  static const String _activeLLMModelId = 'llama-4-scout-17b-16e-instruct';

  /// Default TTS Provider (if different from LLM provider)
  static const LLMProvider _defaultTTSProvider = LLMProvider.openai;

  /// Default TTS Model ID
  static const String _defaultTTSModelId = 'gpt-4o-mini-tts';

  /// Default TTS Voice
  static const String _defaultTTSVoice = 'coral';

  /// Default audio characteristics used when backend doesn't supply overrides
  static const int _defaultTTSSampleRate = 24000;
  static const String _defaultTTSAudioEncoding = 'LINEAR16';
  static const String _defaultTTSResponseFormat = 'wav';
  static const bool _defaultTTSSupportsStreaming = true;
  static const String _defaultTTSMode = 'rest';
  static const String _defaultTtsMimeType = 'audio/wav';

  /// Runtime overrides supplied by backend configuration
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
  // PROVIDER CONFIGURATIONS - Add new providers here
  // =================================================================

  /// OpenAI Configuration
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

  /// Anthropic Configuration
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

  /// Google Configuration
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

  /// Groq Configuration
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

  /// TTS Model Configurations
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
  // PUBLIC API - Use these methods to get current configurations
  // =================================================================

  /// Get the current active LLM configuration
  static LLMModelConfig get currentLLMConfig {
    final models = _getModelsForProvider(_activeLLMProvider);
    final config = models[_activeLLMModelId];

    if (config == null) {
      throw Exception(
          'Model $_activeLLMModelId not found for provider $_activeLLMProvider. '
          'Available models: ${models.keys.join(', ')}');
    }

    if (kDebugMode) {
      debugPrint(
          '[LLMConfig] Using LLM: $_activeLLMProvider - $_activeLLMModelId');
    }

    return config;
  }

  /// Get the current active TTS configuration
  static TTSModelConfig get currentTTSConfig {
    final provider = activeTTSProvider;
    final modelId = activeTTSModelId;
    final models = _getTTSModelsForProvider(provider);
    final baseConfig = models[modelId];

    if (baseConfig == null) {
      throw Exception('TTS Model $modelId not found for provider $provider. '
          'Available models: ${models.keys.join(', ')}');
    }

    if (kDebugMode) {
      debugPrint('[LLMConfig] Using TTS: $provider - $modelId');
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

  /// Get active provider information
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

  /// Allow runtime overrides provided by the backend configuration endpoint.
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
      _overrideTTSVoice = voice;
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

    if (kDebugMode) {
      debugPrint('[LLMConfig] Applied remote TTS config override: '
          'provider=${activeTTSProvider.name}, '
          'model=$activeTTSModelId, '
          'voice=$activeTTSVoice, '
          'sampleRate=$activeTTSSampleRate, '
          'encoding=$activeTTSAudioEncoding, '
          'format=$activeTTSResponseFormat, '
          'mode=$activeTTSMode, '
          'mime=$activeTtsMimeType');
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

  /// Get all available models for a provider
  static Map<String, LLMModelConfig> getAvailableModelsForProvider(
      LLMProvider provider) {
    return _getModelsForProvider(provider);
  }

  /// Get all available TTS models for a provider
  static Map<String, TTSModelConfig> getAvailableTTSModelsForProvider(
      LLMProvider provider) {
    return _getTTSModelsForProvider(provider);
  }

  // =================================================================
  // PRIVATE HELPER METHODS
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

  /// Validate current configuration
  static bool validateConfiguration() {
    try {
      final llmConfig = currentLLMConfig;
      final ttsConfig = currentTTSConfig;

      if (kDebugMode) {
        debugPrint('[LLMConfig] Configuration validation passed');
        debugPrint('  LLM: ${llmConfig.modelId} (${llmConfig.endpoint})');
        debugPrint('  TTS: ${ttsConfig.modelId} (${ttsConfig.endpoint})');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LLMConfig] Configuration validation failed: $e');
      }
      return false;
    }
  }
}
