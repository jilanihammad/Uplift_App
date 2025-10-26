# TTS Smoke Tests - Quick Reference

## ⚡ Quick Start

```bash
# 1. Install dependencies (first time only)
pip install websockets pytest pytest-asyncio

# 2. Set API key
export GOOGLE_API_KEY=your-google-api-key

# 3. Start backend (if testing locally)
python dev_server.py

# 4. Run smoke test
python testTTS.py --mode live --url ws://localhost:8000
```

## 📋 Common Commands

### Local Testing

```bash
# Test REST mode
python testTTS.py --api-key $GOOGLE_API_KEY

# Test WebSocket Live mode
python testTTS.py --mode live --url ws://localhost:8000

# Run pytest suite
pytest tests/test_tts_smoke.py -v
```

### Staging Testing

```bash
# Before deploying
export GOOGLE_API_KEY=your-key
./scripts/test_deployment.sh staging

# After deployment
python testTTS.py --mode live --url wss://staging-backend.run.app
```

### Production Validation

```bash
# Smoke test production
export GOOGLE_API_KEY=your-key
./scripts/test_deployment.sh production

# Manual validation
python testTTS.py \
  --mode live \
  --url wss://ai-therapist-backend-385290373302.us-central1.run.app
```

## 🎯 Test Checklist

Before deploying:
- [ ] Local smoke test passes (`testTTS.py --mode live`)
- [ ] Pytest suite passes (`pytest tests/test_tts_smoke.py`)
- [ ] TTFB < 500ms (check output)
- [ ] Audio file generated successfully
- [ ] MIME type correct (`audio/ogg; codecs=opus`)
- [ ] Sample rate = 24000 Hz

After deploying to staging:
- [ ] Deployment script passes (`./scripts/test_deployment.sh staging`)
- [ ] Health check returns 200
- [ ] TTS config endpoint accessible
- [ ] WebSocket connection successful
- [ ] All pytest tests pass against staging

## 🔍 Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection refused | Check server is running: `curl http://localhost:8000/health` |
| GOOGLE_API_KEY error | Set environment: `export GOOGLE_API_KEY=your-key` |
| TTFB too high | Check backend logs, verify Gemini API status |
| Timeout | Increase timeout: `--timeout 60` |
| Invalid MIME type | Verify `GOOGLE_TTS_MODE=live` is set |

## 📊 Expected Output

### Successful Test
```
============================================================
🧪 TTS Backend Smoke Test - Mode: LIVE
============================================================
...
✅ Audio received: 45632 bytes
✅ MIME type: audio/ogg; codecs=opus
✅ Sample rate: 24000 Hz
✅ TTFB: 287 ms
✅ Test PASSED
```

### Failed Test
```
❌ Test failed: Connection refused to ws://localhost:8000/ws/tts
```

## 🚀 CI/CD Integration

```bash
# In your CI/CD pipeline
export GOOGLE_API_KEY=${{ secrets.GOOGLE_API_KEY }}
./scripts/test_deployment.sh staging
# If successful, promote to production
```

## 📖 Full Documentation

See `SMOKE_TESTS.md` for complete documentation.
