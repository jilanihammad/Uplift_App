# Centralized LLM Configuration System

This document explains how to use the new centralized LLM configuration system that allows you to easily switch between different LLM providers and models with minimal code changes.

## 🎯 Overview

The centralized LLM configuration system provides:
- **One-location configuration** - Change providers/models in a single file
- **Support for multiple providers** - OpenAI, Anthropic, Google, Groq, and custom providers
- **Direct API calls** - Option to bypass backend and call LLM providers directly
- **TTS integration** - Centralized configuration for Text-to-Speech services
- **Easy switching** - Change entire app behavior with 2-3 line changes

## 📁 File Structure

```
lib/config/
├── llm_config.dart          # Main configuration file
└── README_LLM_CONFIG.md     # This documentation

lib/data/datasources/remote/
└── api_client.dart          # Updated with direct LLM calls

lib/services/
├── message_processor.dart   # Updated with direct LLM support
└── audio_generator.dart     # Updated with direct TTS support
```

## ⚡ Quick Start

### 1. Switch LLM Provider and Model

Edit `lib/config/llm_config.dart`:

```dart
/// Active LLM Provider - Change this to switch providers
static const LLMProvider _activeLLMProvider = LLMProvider.openai; // Change this

/// Active LLM Model ID for the selected provider
static const String _activeLLMModelId = 'gpt-4o'; // Change this

/// Active TTS Provider (if different from LLM provider)
static const LLMProvider _activeTTSProvider = LLMProvider.openai;

/// Active TTS Model ID
static const String _activeTTSModelId = 'tts-1';
```

### 2. Enable Direct API Calls (Optional)

To bypass your backend and call LLM providers directly:

**For LLM calls**, edit `lib/services/message_processor.dart`:
```dart
// Set this to true to bypass backend and call LLM providers directly
static const bool _useDirectLLMCalls = true; // Change to true
```

**For TTS calls**, edit `lib/services/audio_generator.dart`:
```dart
// Set this to true to bypass backend and call TTS providers directly
static const bool _useDirectTTSCalls = true; // Change to true
```

### 3. Set API Keys

For direct API calls, you need to store API keys. Currently using SharedPreferences (in production, use flutter_secure_storage):

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('OPENAI_API_KEY', 'your-api-key-here');
await prefs.setString('ANTHROPIC_API_KEY', 'your-api-key-here');
await prefs.setString('GROQ_API_KEY', 'your-api-key-here');
```

## 🔧 Supported Providers

### OpenAI
- **Models**: `gpt-4o`, `gpt-4o-mini`
- **TTS**: `tts-1`, `tts-1-hd`
- **API Key**: `OPENAI_API_KEY`

### Anthropic
- **Models**: `claude-3-5-sonnet-20241022`, `claude-3-haiku-20240307`
- **TTS**: Not available
- **API Key**: `ANTHROPIC_API_KEY`

### Google
- **Models**: `gemini-1.5-pro`, `gemini-1.5-flash`
- **TTS**: Not available
- **API Key**: `GOOGLE_API_KEY`

### Groq
- **Models**: `llama-3.1-70b-versatile`, `llama-3.1-8b-instant`
- **TTS**: Not available
- **API Key**: `GROQ_API_KEY`

### Custom Providers
You can add custom providers by extending the configuration maps in `llm_config.dart`.

## 🎛️ Configuration Examples

### Example 1: Use OpenAI GPT-4o with Backend Proxy
```dart
// In llm_config.dart
static const LLMProvider _activeLLMProvider = LLMProvider.openai;
static const String _activeLLMModelId = 'gpt-4o';

// In message_processor.dart
static const bool _useDirectLLMCalls = false; // Use backend

// In audio_generator.dart  
static const bool _useDirectTTSCalls = false; // Use backend
```

### Example 2: Use Groq Llama with Direct API Calls
```dart
// In llm_config.dart
static const LLMProvider _activeLLMProvider = LLMProvider.groq;
static const String _activeLLMModelId = 'llama-3.1-70b-versatile';

// In message_processor.dart
static const bool _useDirectLLMCalls = true; // Direct calls

// In audio_generator.dart (still use backend for TTS since Groq doesn't have TTS)
static const bool _useDirectTTSCalls = false; // Use backend
```

### Example 3: Use Claude with OpenAI TTS
```dart
// In llm_config.dart
static const LLMProvider _activeLLMProvider = LLMProvider.anthropic;
static const String _activeLLMModelId = 'claude-3-5-sonnet-20241022';
static const LLMProvider _activeTTSProvider = LLMProvider.openai;
static const String _activeTTSModelId = 'tts-1';

// In message_processor.dart
static const bool _useDirectLLMCalls = true; // Direct calls

// In audio_generator.dart
static const bool _useDirectTTSCalls = true; // Direct calls
```

## 🔄 How It Works

### Backend Proxy Mode (Default)
```
App → MessageProcessor → ApiClient → Your Backend → LLM Provider
App → AudioGenerator → VoiceService → Your Backend → TTS Provider
```

### Direct API Mode
```
App → MessageProcessor → ApiClient → LLM Provider (direct)
App → AudioGenerator → TTS Provider (direct)
```

## 🚀 Benefits

1. **Easy Provider Switching**: Change providers by modifying 1-2 constants
2. **Cost Optimization**: Switch to cheaper models during development
3. **Fallback Support**: Use different providers for different purposes
4. **Development Speed**: Skip backend for prototyping
5. **Provider Comparison**: Easy A/B testing between providers

## 🔧 Adding New Providers

To add a new provider (e.g., Cohere):

1. Add to the enum:
```dart
enum LLMProvider {
  openai,
  anthropic,
  google,
  groq,
  cohere, // Add new provider
  custom,
}
```

2. Add configuration:
```dart
static const Map<String, LLMModelConfig> _cohereModels = {
  'command-r-plus': LLMModelConfig(
    modelId: 'command-r-plus',
    endpoint: 'https://api.cohere.ai/v1/chat',
    headers: {'Content-Type': 'application/json'},
    defaultParams: {'max_tokens': 4000, 'temperature': 0.7},
    apiKeyEnvVar: 'COHERE_API_KEY',
  ),
};
```

3. Add to helper method:
```dart
static Map<String, LLMModelConfig> _getModelsForProvider(LLMProvider provider) {
  switch (provider) {
    // ... existing cases
    case LLMProvider.cohere:
      return _cohereModels;
  }
}
```

4. Add request body builder in `api_client.dart`:
```dart
case LLMProvider.cohere:
  return _buildCohereStyleBody(config, systemPrompt, userMessage, 
                               conversationHistory, additionalParams);
```

## 🐛 Troubleshooting

### Common Issues

1. **API Key Not Found**
   - Ensure API keys are stored with correct environment variable names
   - Use SharedPreferences or flutter_secure_storage

2. **Model Not Found**
   - Check that the model ID exists in the provider's configuration
   - Verify the model is available in your API plan

3. **Invalid Response Format**
   - Check the response parsing logic for your provider
   - Some providers have different response structures

4. **Network Errors**
   - Verify internet connectivity
   - Check if provider endpoints are accessible
   - Ensure API keys are valid

### Debug Mode

The system includes debug logging. Look for messages like:
```
[LLMConfig] Using LLM: groq - llama-3.1-70b-versatile
[MessageProcessor] Direct LLM response received: 150 characters
[AudioGenerator] Making direct TTS call to tts-1
```

## 📊 Performance Considerations

- **Direct calls** are faster (no backend hop) but require API key management
- **Backend proxy** is more secure but adds latency
- **Caching** is implemented for both LLM responses and TTS audio
- **Fallback responses** ensure the app works even if APIs fail

## 🔒 Security Notes

- Store API keys securely (use flutter_secure_storage in production)
- Consider rate limiting for direct API calls
- Monitor API usage and costs
- Implement proper error handling for failed requests

## 📝 Future Enhancements

- GUI configuration panel
- A/B testing framework
- Cost tracking and optimization
- Automatic provider failover
- Per-user provider preferences 