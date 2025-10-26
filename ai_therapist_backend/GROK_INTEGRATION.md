# Grok LLM Integration Guide

This document explains how to use Grok (x.ai) as your LLM provider in the AI Therapist backend.

## Overview

Grok has been integrated as a new LLM provider alongside OpenAI, Groq, Anthropic, Google Gemini, Azure OpenAI, and DeepSeek. It uses an OpenAI-compatible API which makes it seamless to integrate.

## Setup Instructions

### 1. Get Your Grok API Key

1. Visit https://console.x.ai/
2. Navigate to your team's API keys section
3. Create a new API key
4. Copy the key for use in your environment configuration

### 2. Configure Environment Variables

Add the following to your `.env` file in the `ai_therapist_backend` directory:

```bash
# Grok API Configuration
XAI_API_KEY=your-xai-api-key-here

# Optional: Override default model (default is grok-4-fast-non-reasoning)
GROK_LLM_MODEL=grok-4-fast-non-reasoning

# Optional: Override base URL (default is https://api.x.ai/v1)
GROK_API_BASE_URL=https://api.x.ai/v1
```

### 3. Activate Grok as Your LLM Provider

Update `app/core/llm_config.py` line 39:

```python
ACTIVE_LLM_PROVIDER = ModelProvider.GROK  # Change from GOOGLE to GROK
```

### 4. Restart Your Backend Server

```bash
# If using dev server
python dev_server.py

# If using uvicorn
python -m uvicorn app.main:app --reload
```

## Available Grok Models

Grok offers several models you can use:

- **grok-4-fast-non-reasoning** (default) - Fastest Grok-4 model optimized for speed
- **grok-2-latest** - Latest Grok-2 model
- **grok-2-vision-1212** - Grok-2 with vision capabilities
- **grok-beta** - Beta version with latest features

To change the model, set `GROK_LLM_MODEL` in your `.env` file.

## Features

- ✅ **Chat Completions**: Full conversational AI support
- ✅ **Streaming**: Real-time streaming responses
- ✅ **Large Context**: 131K token context window
- ✅ **OpenAI Compatible**: Uses familiar OpenAI SDK patterns

## Testing Grok Integration

### Using the API Health Endpoint

```bash
# Check if Grok is configured correctly
curl http://localhost:8000/health

# Test LLM with simple prompt
curl -X POST "http://localhost:8000/ai/response" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, tell me about yourself"}'
```

### Using Python Test Script

Create a test file `test_grok.py`:

```python
import asyncio
from app.services.llm_manager import llm_manager

async def test_grok():
    # Test basic response
    response = await llm_manager.generate_response("Hello! What can you help me with?")
    print(f"Response: {response}")

    # Test streaming
    print("\nStreaming response:")
    async for chunk in llm_manager.stream_chat_completion("Tell me a short story"):
        print(chunk, end='', flush=True)
    print()

if __name__ == "__main__":
    asyncio.run(test_grok())
```

Run the test:
```bash
cd ai_therapist_backend
python test_grok.py
```

## Configuration Options

### Default Parameters

The default Grok configuration includes:

```python
{
    "temperature": 0.7,      # Creativity level (0.0 to 1.0)
    "max_tokens": 1000,      # Maximum response length
    "top_p": 1.0,           # Nucleus sampling parameter
    "stream": False          # Enable/disable streaming by default
}
```

### Customizing Parameters

You can override these when calling the LLM manager:

```python
# Custom temperature and max tokens
response = await llm_manager.generate_response(
    "Your message here",
    temperature=0.9,
    max_tokens=2000
)
```

## Switching Between Providers

You can easily switch between LLM providers by changing `ACTIVE_LLM_PROVIDER` in `llm_config.py`:

```python
# Use Grok
ACTIVE_LLM_PROVIDER = ModelProvider.GROK

# Use OpenAI
ACTIVE_LLM_PROVIDER = ModelProvider.OPENAI

# Use Groq
ACTIVE_LLM_PROVIDER = ModelProvider.GROQ

# Use Anthropic
ACTIVE_LLM_PROVIDER = ModelProvider.ANTHROPIC

# Use Google Gemini
ACTIVE_LLM_PROVIDER = ModelProvider.GOOGLE
```

## Troubleshooting

### Common Issues

1. **"API key not found" error**
   - Ensure `XAI_API_KEY` is set in your `.env` file
   - Restart your backend server after adding the key

2. **"Unsupported LLM provider" error**
   - Check that `ACTIVE_LLM_PROVIDER = ModelProvider.GROK` in `llm_config.py`
   - Verify you've imported the latest code changes

3. **Connection errors**
   - Verify your API key is valid at https://console.x.ai/
   - Check your network connection
   - Ensure the base URL is correct (`https://api.x.ai/v1`)

### Debugging

Enable debug logging to see detailed request/response information:

```python
import logging
logging.getLogger("app.services.llm_manager").setLevel(logging.DEBUG)
```

## Next Steps

After implementing Grok in the backend:

1. **Frontend Integration**: Update your Flutter app to work with the Grok-powered backend
2. **Testing**: Thoroughly test the chatbot functionality with Grok responses
3. **Monitoring**: Monitor response quality and latency
4. **Fine-tuning**: Adjust temperature and other parameters based on user feedback

## API Reference

### Key Files Modified

- `app/core/llm_config.py` - Grok provider configuration
- `app/services/llm_manager.py` - Routing logic for Grok
- `CLAUDE.md` - Updated documentation

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `XAI_API_KEY` | Yes | - | Your x.ai API key |
| `GROK_LLM_MODEL` | No | `grok-4-fast-non-reasoning` | Model to use |
| `GROK_API_BASE_URL` | No | `https://api.x.ai/v1` | API endpoint |

## Support

For issues or questions:
- x.ai Documentation: https://docs.x.ai/
- x.ai Console: https://console.x.ai/

---

*Last Updated: 2025-10-25*
