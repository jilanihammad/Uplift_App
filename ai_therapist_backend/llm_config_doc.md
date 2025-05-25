# LLM Configuration Guide: Safe Provider Switching

This guide provides step-by-step instructions for safely switching between different LLM providers and service endpoints without breaking your AI Therapist application.

## 🚨 IMPORTANT: Before You Start

### 1. Current Status Check
Before making any changes, always check your current configuration:

```bash
# Test your current setup
curl -X GET "http://localhost:8080/api/v1/ai/config"

# Or if deployed
curl -X GET "https://your-domain.com/api/v1/ai/config"
```

### 2. Backup Current Configuration
Make a backup of your current working configuration:

```bash
# Copy current config file
cp app/core/llm_config.py app/core/llm_config.py.backup

# Copy current .env file  
cp .env .env.backup
```

---

## 📋 Step-by-Step Provider Switching

### STEP 1: Check Available Providers

First, see what providers are currently available:

**File to check:** `app/core/llm_config.py`

Look for these sections:
- `ACTIVE_LLM_PROVIDER` (lines ~33-35)
- `ACTIVE_TTS_PROVIDER` (lines ~33-35) 
- `ACTIVE_TRANSCRIPTION_PROVIDER` (lines ~33-35)

**Available providers:**
- `ModelProvider.OPENAI` - OpenAI GPT models
- `ModelProvider.GROQ` - Fast Groq inference  
- `ModelProvider.ANTHROPIC` - Claude models
- `ModelProvider.AZURE_OPENAI` - Azure-hosted OpenAI
- `ModelProvider.DEEPSEEK` - DeepSeek models
- `ModelProvider.GOOGLE` - Google Gemini models

### STEP 2: Check Required API Keys

**Before switching**, ensure you have the required API key for your target provider:

| Provider | Required Environment Variable | How to Get Key |
|----------|------------------------------|----------------|
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Groq | `GROQ_API_KEY` | https://console.groq.com/keys |
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/ |
| Azure OpenAI | `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` | Azure Portal |
| DeepSeek | `DEEPSEEK_API_KEY` | https://platform.deepseek.com/ |
| Google | `GOOGLE_API_KEY` | Google Cloud Console |

### STEP 3: Add API Key to Environment

**Edit your `.env` file** (create if doesn't exist):

```bash
# Example for switching to Anthropic
ANTHROPIC_API_KEY=your_anthropic_key_here

# Example for switching to Groq
GROQ_API_KEY=your_groq_key_here

# Keep existing keys for fallback
OPENAI_API_KEY=your_existing_openai_key
```

### STEP 4: Update Configuration File

**Edit:** `app/core/llm_config.py`

**Find lines ~33-35 and modify ONLY these lines:**

```python
# =============================================================================
# ACTIVE MODEL SELECTION - CHANGE THESE TO SWITCH MODELS EASILY
# =============================================================================

# BEFORE (example)
ACTIVE_LLM_PROVIDER = ModelProvider.GROQ
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI        
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI

# AFTER (example - switching to Anthropic for LLM)
ACTIVE_LLM_PROVIDER = ModelProvider.ANTHROPIC     # ← Changed this line
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI        # ← Keep existing if working
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI  # ← Keep existing if working
```

**⚠️ CRITICAL: Only change the provider constants. Do NOT modify:**
- Model configurations in the `MODELS` dictionary
- Class methods
- Import statements
- Any other parts of the file

### STEP 5: Test Configuration (Before Restarting)

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

### STEP 6: Restart Application

```bash
# If using Docker
docker-compose restart

# If running locally
# Stop current process (Ctrl+C) then restart:
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080

# If using gunicorn
pkill gunicorn
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080
```

### STEP 7: Verify Everything Works

**Test endpoints in this order:**

1. **Configuration Status:**
```bash
curl -X GET "http://localhost:8080/api/v1/ai/config"
```
✅ Should show your new provider as active and available

2. **API Key Test:**
```bash
curl -X GET "http://localhost:8080/api/v1/ai/test-key"
```
✅ Should show successful test for your new provider

3. **Health Check:**
```bash
curl -X GET "http://localhost:8080/health"
```
✅ Should show all services as available

4. **Test LLM Generation:**
```bash
curl -X POST "http://localhost:8080/api/v1/ai/generate" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, this is a test message", "history": []}'
```
✅ Should return a response from your new provider

5. **Test TTS (if you changed TTS provider):**
```bash
curl -X POST "http://localhost:8080/api/v1/voice/synthesize" \
  -H "Content-Type: application/json" \
  -d '{"text": "This is a test"}'
```
✅ Should return audio URL

---

## 🔄 Safe Rollback Procedure

If something goes wrong, here's how to quickly rollback:

### STEP 1: Restore Configuration
```bash
# Restore config file
cp app/core/llm_config.py.backup app/core/llm_config.py

# Restore environment file
cp .env.backup .env
```

### STEP 2: Restart Application
```bash
# Restart using same method as above
docker-compose restart
# OR
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

### STEP 3: Verify Rollback Success
```bash
curl -X GET "http://localhost:8080/api/v1/ai/config"
```

---

## 📋 Common Switching Scenarios

### Scenario 1: Switch from Groq to OpenAI (Complete Switch)

**Current:** Groq for everything  
**Target:** OpenAI for everything

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

**Current:** Mixed setup  
**Target:** Anthropic for chat, OpenAI for voice services

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

**Current:** Various  
**Target:** Groq for fast LLM, OpenAI for high-quality voice

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

---

## 🚨 Troubleshooting Common Issues

### Issue 1: "API key not found" Error

**Symptom:** Configuration shows provider as unavailable
**Solution:**
1. Check your `.env` file has the correct variable name
2. Restart the application to reload environment variables
3. Use the test endpoint: `/api/v1/ai/test-key`

### Issue 2: "Unsupported provider" Error

**Symptom:** Error when generating responses  
**Solution:**
1. Check spelling in `llm_config.py` (must match exactly)
2. Ensure provider exists in `ModelProvider` enum
3. Verify the provider has a configuration in `MODELS` dictionary

### Issue 3: Application Won't Start

**Symptom:** Import errors or startup failures
**Solution:**
1. Check syntax: `python -c "from app.core.llm_config import LLMConfig"`
2. Restore from backup: `cp llm_config.py.backup llm_config.py`
3. Check for typos in provider names

### Issue 4: Some Services Work, Others Don't

**Symptom:** LLM works but TTS fails
**Solution:**
1. Check that you have API keys for ALL active providers
2. Some providers don't support all service types
3. Check `/api/v1/ai/config` for specific service availability

---

## 📊 Testing Checklist

After any provider switch, test these functions:

- [ ] **Basic Health Check** - `/health` endpoint returns 200
- [ ] **Configuration Valid** - `/api/v1/ai/config` shows new provider active
- [ ] **API Keys Work** - `/api/v1/ai/test-key` succeeds
- [ ] **LLM Generation** - `/api/v1/ai/generate` returns response
- [ ] **TTS Generation** - `/api/v1/voice/synthesize` creates audio
- [ ] **Audio Transcription** - `/api/v1/voice/transcribe` processes audio
- [ ] **WebSocket Chat** - `/api/v1/ai/ws/chat` streams responses
- [ ] **WebSocket TTS** - `/api/v1/voice/ws/tts` streams audio

---

## 🔧 Advanced Configuration

### Custom Model IDs

You can override specific model IDs without changing providers:

```python
# In llm_config.py, modify these optional overrides:
ACTIVE_LLM_MODEL = "gpt-4"  # Override default OpenAI model
ACTIVE_TTS_MODEL = "tts-1-hd"  # Override default TTS model
ACTIVE_TRANSCRIPTION_MODEL = "whisper-1"  # Override default transcription model
```

### Environment Variable Overrides

You can also override models via environment variables:

```bash
# In .env file
OPENAI_LLM_MODEL=gpt-4o
GROQ_LLM_MODEL_ID=llama-3.1-8b-instant
ANTHROPIC_MODEL=claude-3-haiku-20240307
```

---

## 📞 Support

If you encounter issues:

1. **Check the logs** for detailed error messages
2. **Use the config endpoint** (`/api/v1/ai/config`) for debugging info
3. **Test individual components** using the test endpoints
4. **Restore from backup** if all else fails

Remember: Always test in a development environment before applying changes to production! 