# 🚀 Quick Reference: LLM Provider Switching

## ⚡ Quick Switch Steps

### 1. Backup First
```bash
cp app/core/llm_config.py app/core/llm_config.py.backup
cp .env .env.backup
```

### 2. Add API Key to .env
```bash
# Add your new provider's API key
echo "ANTHROPIC_API_KEY=your_key_here" >> .env
```

### 3. Switch Provider (Edit llm_config.py lines ~33-35)
```python
ACTIVE_LLM_PROVIDER = ModelProvider.ANTHROPIC        # Change this line
ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI           # Keep if working
ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.OPENAI # Keep if working
```

### 4. Test & Restart
```bash
# Test config syntax
python -c "from app.core.llm_config import LLMConfig; print('✅ Valid')"

# Restart app
docker-compose restart
# OR
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

### 5. Verify Working
```bash
curl -X GET "http://localhost:8080/api/v1/ai/config"
curl -X POST "http://localhost:8080/api/v1/ai/generate" \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'
```

---

## 🔧 Provider Options

| Provider | Speed | Quality | Cost | Best For |
|----------|-------|---------|------|----------|
| **GROQ** | ⚡⚡⚡ | ⭐⭐⭐ | 💰 | Fast responses |
| **OPENAI** | ⚡⚡ | ⭐⭐⭐⭐⭐ | 💰💰💰 | Best quality |
| **ANTHROPIC** | ⚡⚡ | ⭐⭐⭐⭐⭐ | 💰💰 | Best reasoning |
| **GOOGLE** | ⚡⚡ | ⭐⭐⭐⭐ | 💰💰 | Good balance |

---

## 🚨 Emergency Rollback
```bash
# If something breaks:
cp app/core/llm_config.py.backup app/core/llm_config.py
cp .env.backup .env
docker-compose restart
```

---

## 📱 Essential Test Commands

```bash
# Check current setup
curl -X GET "http://localhost:8080/api/v1/ai/config"

# Test API keys
curl -X GET "http://localhost:8080/api/v1/ai/test-key"

# Test chat
curl -X POST "http://localhost:8080/api/v1/ai/generate" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello world"}'

# Test TTS
curl -X POST "http://localhost:8080/api/v1/voice/synthesize" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test audio"}'
```

---

## 🔑 Required API Keys

| Provider | Environment Variable | Get Key From |
|----------|---------------------|---------------|
| OpenAI | `OPENAI_API_KEY` | platform.openai.com |
| Groq | `GROQ_API_KEY` | console.groq.com |
| Anthropic | `ANTHROPIC_API_KEY` | console.anthropic.com |
| Google | `GOOGLE_API_KEY` | cloud.google.com |

---

## ⚠️ Remember

1. **Always backup before changes**
2. **Only edit the 3 ACTIVE_* lines**
3. **Test after every change**
4. **Keep working API keys as fallback**
5. **Restart app after config changes** 