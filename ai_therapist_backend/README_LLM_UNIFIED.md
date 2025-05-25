# Unified LLM Management System

This document describes the unified LLM management system implemented in the AI Therapist backend, which provides a single point of control for switching between different AI providers and models.

## Overview

The unified system consists of two main components:

1. **`llm_config.py`** - Centralized configuration management
2. **`llm_manager.py`** - Unified interface for all AI operations

## Quick Start

### 1. Switch AI Providers

To switch between providers, simply modify the constants in `app/core/llm_config.py`:

```python
# Change these to switch models easily
ACTIVE_LLM_PROVIDER = ModelProvider.GROQ          # or OPENAI, ANTHROPIC, etc.
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI        # or GROQ
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI  # or GROQ
```

### 2. Set API Keys

Add the required API keys to your `.env` file:

```bash
# OpenAI (required for TTS/transcription if using OpenAI)
OPENAI_API_KEY=your_openai_key_here

# Groq (required for LLM if using Groq)
GROQ_API_KEY=your_groq_key_here

# Anthropic (required if using Claude)
ANTHROPIC_API_KEY=your_anthropic_key_here

# Other optional providers
AZURE_OPENAI_API_KEY=your_azure_key_here
AZURE_OPENAI_ENDPOINT=your_azure_endpoint_here
DEEPSEEK_API_KEY=your_deepseek_key_here
GOOGLE_API_KEY=your_google_key_here
```

### 3. Use the Unified Interface

In your code, replace individual service imports with the unified manager:

```python
# OLD WAY - Don't do this anymore
from app.services.openai_service import openai_service
from app.services.groq_service import groq_service

# NEW WAY - Use unified manager
from app.services.llm_manager import llm_manager

# Generate response (routes to active LLM provider automatically)
response = await llm_manager.generate_response(
    message="Hello", 
    context=conversation_history,
    system_prompt="You are a helpful assistant"
)

# Text-to-speech (routes to active TTS provider automatically) 
success = await llm_manager.text_to_speech("Hello world", "output.mp3")

# Transcription (routes to active transcription provider automatically)
text = await llm_manager.transcribe_audio("audio_file.mp3")
```

## Supported Providers

### LLM Providers
- **OpenAI** - GPT models (gpt-4o-mini, gpt-4, etc.)
- **Groq** - Fast inference (llama-3.1-70b-versatile, etc.)
- **Anthropic** - Claude models (claude-3-5-sonnet, etc.)
- **Azure OpenAI** - Azure-hosted OpenAI models
- **DeepSeek** - DeepSeek chat models
- **Google** - Gemini models

### TTS Providers
- **OpenAI** - High-quality text-to-speech
- **Groq** - OpenAI-compatible TTS (if available)

### Transcription Providers
- **OpenAI** - Whisper models
- **Groq** - Fast Whisper inference

## Configuration Details

### Model Configuration Structure

Each model is configured with:

```python
ModelConfig(
    provider=ModelProvider.OPENAI,
    model_id="gpt-4o-mini",
    base_url="https://api.openai.com/v1",
    api_key_env="OPENAI_API_KEY",
    default_params={
        "temperature": 0.7,
        "max_tokens": 1000
    },
    supports_streaming=True,
    max_tokens_limit=128000
)
```

### Environment Variables

The system uses these environment variables for model configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_LLM_MODEL` | OpenAI chat model | gpt-4o-mini |
| `OPENAI_TTS_MODEL` | OpenAI TTS model | tts-1 |
| `OPENAI_TTS_VOICE` | OpenAI TTS voice | sage |
| `OPENAI_TRANSCRIPTION_MODEL` | OpenAI transcription model | whisper-1 |
| `GROQ_LLM_MODEL_ID` | Groq chat model | llama-3.1-70b-versatile |
| `GROQ_API_BASE_URL` | Groq API endpoint | https://api.groq.com/openai/v1 |
| `ANTHROPIC_MODEL` | Anthropic model | claude-3-5-sonnet-20241022 |

## API Endpoints

### Status and Testing

- **GET `/api/v1/ai/status`** - Get status of all AI services
- **GET `/api/v1/ai/test-key`** - Test all API keys
- **GET `/api/v1/ai/config`** - Get detailed configuration and validation info

### Chat and Generation

- **POST `/api/v1/ai/generate`** - Generate AI response
- **WebSocket `/api/v1/ai/ws/chat`** - Streaming chat interface

### Voice Services

- **POST `/api/v1/voice/synthesize`** - Text-to-speech
- **POST `/api/v1/voice/transcribe`** - Audio transcription
- **POST `/api/v1/voice/tts`** - Alternative TTS endpoint

## Migration Guide

### From Individual Services

If you have existing code using individual services, here's how to migrate:

#### LLM Chat Completions

```python
# OLD
from app.services.groq_service import groq_service
response = await groq_service.generate_response(message, system_prompt, context=history)

# NEW
from app.services.llm_manager import llm_manager
response = await llm_manager.generate_response(message, history, system_prompt)
```

#### Text-to-Speech

```python
# OLD
from app.services.openai_service import openai_service
success = await openai_service.text_to_speech(text, output_file, params)

# NEW  
from app.services.llm_manager import llm_manager
success = await llm_manager.text_to_speech(text, output_file, **params)
```

#### Transcription

```python
# OLD
from app.services.openai_service import openai_service
text = await openai_service.transcribe_audio(audio_file)

# NEW
from app.services.llm_manager import llm_manager  
text = await llm_manager.transcribe_audio(audio_file)
```

## Debugging and Troubleshooting

### Check Configuration Status

Visit `/api/v1/ai/config` to get detailed information about:
- Current active providers
- API key availability
- Model configurations
- Validation errors/warnings

### Test API Keys

Visit `/api/v1/ai/test-key` to test all configured API keys and ensure they're working.

### Common Issues

1. **"API key not found"** - Ensure the required API key is set in your `.env` file
2. **"Unsupported provider"** - Check that the provider is listed in `ACTIVE_*_PROVIDER` settings
3. **"No configuration available"** - Verify the provider/model combination exists in `MODELS` dict

### Logs

The system provides detailed logging. Check your application logs for:
- Service initialization messages
- API call successes/failures  
- Configuration validation results

## Adding New Providers

To add a new provider:

1. **Add to enums**:
```python
class ModelProvider(str, Enum):
    # ... existing providers ...
    NEW_PROVIDER = "new_provider"
```

2. **Add model configurations**:
```python
(ModelProvider.NEW_PROVIDER, ModelType.LLM): ModelConfig(
    provider=ModelProvider.NEW_PROVIDER,
    model_id="new-model-id",
    base_url="https://api.newprovider.com/v1",
    api_key_env="NEW_PROVIDER_API_KEY",
    default_params={"temperature": 0.7},
    supports_streaming=True
)
```

3. **Implement provider methods** in `llm_manager.py`:
```python
async def _generate_new_provider_response(self, message, context, system_prompt, user_info, **kwargs):
    # Implementation for new provider
    pass
```

4. **Add routing** in the main generation method:
```python
elif self.llm_config.provider == ModelProvider.NEW_PROVIDER:
    return await self._generate_new_provider_response(message, context, system_prompt, user_info, **kwargs)
```

## Best Practices

1. **Always use the unified manager** instead of individual services
2. **Set appropriate API keys** for your chosen providers
3. **Test your configuration** using the `/api/v1/ai/config` endpoint
4. **Handle fallbacks** gracefully when providers are unavailable
5. **Monitor logs** for any configuration or API issues

## Performance Considerations

- **Groq** provides fastest inference for supported models
- **OpenAI** provides highest quality for most tasks
- **Anthropic** provides best reasoning capabilities
- **Streaming** is supported where available for better UX

The unified system automatically handles provider-specific optimizations and fallbacks. 