# AI Therapist Backend: LLM Configuration Guide

This guide provides comprehensive instructions for configuring and switching between different LLM providers in the AI Therapist backend system.

## Overview

The unified LLM management system consists of two main components:

1. **`llm_config.py`** - Centralized configuration management
2. **`llm_manager.py`** - Unified interface for all AI operations

## Quick Start

### 1. Switch AI Providers

To switch between providers, modify these constants in `app/core/llm_config.py`:

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

Replace individual service imports with the unified manager:

```python
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

## Safe Provider Switching Guide

### Step 1: Check Current Status

Before making any changes, always check your current configuration:

```bash
# Test your current setup
curl -X GET "http://localhost:8080/api/v1/ai/config"

# Or if deployed
curl -X GET "https://your-domain.com/api/v1/ai/config"
```

### Step 2: Backup Current Configuration

Make a backup of your current working configuration:

```bash
# Copy current config file
cp app/core/llm_config.py app/core/llm_config.py.backup

# Copy current .env file  
cp .env .env.backup
```

### Step 3: Check Required API Keys

Ensure you have the required API key for your target provider:

| Provider | Required Environment Variable | How to Get Key |
|----------|------------------------------|----------------|
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Groq | `GROQ_API_KEY` | https://console.groq.com/keys |
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/ |
| Azure OpenAI | `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` | Azure Portal |
| DeepSeek | `DEEPSEEK_API_KEY` | https://platform.deepseek.com/ |
| Google | `GOOGLE_API_KEY` | Google Cloud Console |

### Step 4: Test Configuration

Test your configuration without restarting the server:

```bash
# Quick syntax check
python -c "from app.core.llm_config import LLMConfig; print('✅ Config file is valid')"

# Check if required API key exists
python -c "
import os
from app.core.llm_config import LLMConfig, ModelType
config = LLMConfig.get_active_model_config(ModelType.LLM)
key = os.getenv(config.api_key_env) if config else None
print(f'✅ API key available: {bool(key)}' if key else '❌ API key missing!')
"
```

### Step 5: Restart and Verify

```bash
# If using Docker
docker-compose restart

# If running locally
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

**Test endpoints in this order:**

1. **Configuration Status:** `GET /api/v1/ai/config`
2. **API Key Test:** `GET /api/v1/ai/test-key`
3. **Health Check:** `GET /health`
4. **Test LLM Generation:** `POST /api/v1/ai/generate`
5. **Test TTS:** `POST /api/v1/voice/synthesize`

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

## Common Switching Scenarios

### Scenario 1: Switch from Groq to OpenAI (Complete Switch)

```python
# In llm_config.py, change:
ACTIVE_LLM_PROVIDER = ModelProvider.OPENAI           # Changed from GROQ
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI           # Changed from GROQ  
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI # Changed from GROQ
```

**Required .env variables:**
```bash
OPENAI_API_KEY=your_openai_key_here
```

### Scenario 2: Switch to Anthropic for LLM, Keep OpenAI for Voice

```python
# In llm_config.py, change:
ACTIVE_LLM_PROVIDER = ModelProvider.ANTHROPIC        # Changed to Anthropic
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI           # Keep OpenAI
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI # Keep OpenAI
```

**Required .env variables:**
```bash
ANTHROPIC_API_KEY=your_anthropic_key_here
OPENAI_API_KEY=your_openai_key_here
```

### Scenario 3: Switch to Groq for Speed, OpenAI for Quality Voice

```python
# In llm_config.py, change:
ACTIVE_LLM_PROVIDER = ModelProvider.GROQ             # Fast inference
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI           # High quality TTS
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.GROQ   # Fast transcription
```

**Required .env variables:**
```bash
GROQ_API_KEY=your_groq_key_here
OPENAI_API_KEY=your_openai_key_here
```

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

## Troubleshooting

### Common Issues

1. **"API key not found"** - Ensure the required API key is set in your `.env` file
2. **"Unsupported provider"** - Check that the provider is listed in `ACTIVE_*_PROVIDER` settings
3. **"No configuration available"** - Verify the provider/model combination exists in `MODELS` dict
4. **Application Won't Start** - Check syntax: `python -c "from app.core.llm_config import LLMConfig"`

### Safe Rollback Procedure

If something goes wrong:

```bash
# Restore config file
cp app/core/llm_config.py.backup app/core/llm_config.py

# Restore environment file
cp .env.backup .env

# Restart application
docker-compose restart
```

### Debug Configuration

Visit `/api/v1/ai/config` to get detailed information about:
- Current active providers
- API key availability
- Model configurations
- Validation errors/warnings

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_LLM_MODEL` | OpenAI chat model | gpt-4o-mini |
| `OPENAI_TTS_MODEL` | OpenAI TTS model | tts-1 |
| `OPENAI_TTS_VOICE` | OpenAI TTS voice | sage |
| `OPENAI_TRANSCRIPTION_MODEL` | OpenAI transcription model | whisper-1 |
| `GROQ_LLM_MODEL_ID` | Groq chat model | llama-3.1-70b-versatile |
| `GROQ_API_BASE_URL` | Groq API endpoint | https://api.groq.com/openai/v1 |
| `ANTHROPIC_MODEL` | Anthropic model | claude-3-5-sonnet-20241022 |

## Best Practices

1. **Always use the unified manager** instead of individual services
2. **Set appropriate API keys** for your chosen providers
3. **Test your configuration** using the `/api/v1/ai/config` endpoint
4. **Handle fallbacks** gracefully when providers are unavailable
5. **Monitor logs** for any configuration or API issues
6. **Test in development** before applying changes to production

## Performance Considerations

- **Groq** provides fastest inference for supported models
- **OpenAI** provides highest quality for most tasks
- **Anthropic** provides best reasoning capabilities
- **Streaming** is supported where available for better UX

The unified system automatically handles provider-specific optimizations and fallbacks.