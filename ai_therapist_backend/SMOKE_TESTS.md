# Backend Smoke Tests Documentation

Comprehensive smoke testing infrastructure for TTS endpoints, including both REST API and WebSocket Live modes with Gemini integration.

## Overview

The smoke test suite validates:
- **REST TTS API** - Direct LLMManager calls with metadata validation
- **WebSocket Live TTS** - Real-time streaming via `/ws/tts` endpoint
- **Audio Quality** - MIME type, sample rate, format validation
- **Performance** - TTFB (Time To First Byte) metrics
- **Deployment Health** - Pre-production validation for staging/production

## Test Tools

### 1. `testTTS.py` - Interactive CLI Smoke Test

Comprehensive command-line tool for manual and automated testing.

#### Features:
- Dual-mode support (REST and WebSocket Live)
- TTFB measurement and validation
- Audio file generation and analysis
- Metadata extraction (MIME type, sample rate)
- JSON output for automation
- Deployment environment testing (local/staging/production)

#### Usage Examples:

```bash
# Test REST API mode (local)
python testTTS.py \
  --api-key $GOOGLE_API_KEY \
  --text "Hello from Gemini" \
  --voice kore

# Test WebSocket Live mode (local)
python testTTS.py \
  --mode live \
  --url ws://localhost:8000 \
  --text "Testing live streaming" \
  --voice kore

# Test against staging deployment
python testTTS.py \
  --mode live \
  --url wss://staging-backend.run.app \
  --text "Staging validation test" \
  --timeout 30

# Test with JSON output (for CI/CD)
python testTTS.py \
  --mode live \
  --url ws://localhost:8000 \
  --text "Automated test" \
  --json-output > test-results.json

# Test and save audio output
python testTTS.py \
  --mode live \
  --url ws://localhost:8000 \
  --voice kore \
  --output my-test-audio.ogg
```

#### Output:

```
============================================================
🧪 TTS Backend Smoke Test - Mode: LIVE
============================================================
Text: 'Testing live streaming'
Voice: kore
Output: test-live.ogg
------------------------------------------------------------

============================================================
📊 Test Results
============================================================
✅ Audio received: 45632 bytes
✅ MIME type: audio/ogg; codecs=opus
✅ Sample rate: 24000 Hz
✅ TTFB: 287 ms
⏱️  Total duration: 1243 ms
✅ Streaming verified: 8 chunks

📁 Output file: test-live.ogg (45632 bytes)
✅ Valid OGG file signature

============================================================
✅ Test PASSED
============================================================
💾 Audio saved to: /path/to/test-live.ogg
```

### 2. `tests/test_tts_smoke.py` - Pytest Suite

Automated test suite for CI/CD integration.

#### Features:
- Pytest framework integration
- Parallel test execution
- Configurable via environment variables
- JSON test reports
- Assertion-based validation
- Skip tests if dependencies missing

#### Usage Examples:

```bash
# Run all TTS smoke tests
pytest tests/test_tts_smoke.py -v

# Run only WebSocket Live tests
pytest tests/test_tts_smoke.py -v -k "live"

# Run against staging with custom timeout
export TEST_BASE_URL=https://staging-backend.run.app
export TEST_TIMEOUT=60
pytest tests/test_tts_smoke.py -v

# Generate JSON report
pytest tests/test_tts_smoke.py -v \
  --json-report \
  --json-report-file=test-results.json

# Run with custom command-line options
pytest tests/test_tts_smoke.py -v \
  --base-url=https://staging-backend.run.app \
  --google-api-key=$GOOGLE_API_KEY

# Run specific test class
pytest tests/test_tts_smoke.py::TestTTSWebSocketLive -v

# Run with verbose output and stop on first failure
pytest tests/test_tts_smoke.py -vsx
```

#### Test Coverage:

| Test Class | Tests | Description |
|------------|-------|-------------|
| `TestTTSRestAPI` | 2 tests | REST API TTS generation and metadata |
| `TestTTSWebSocketLive` | 3 tests | WebSocket streaming, metadata, performance |
| `TestTTSConfiguration` | 3 tests | Configuration validation |

### 3. `scripts/test_deployment.sh` - Deployment Validation Script

Bash script for comprehensive deployment smoke tests.

#### Features:
- Health check validation
- Multi-environment support (staging/production)
- Automated test execution
- Metrics extraction and validation
- CI/CD pipeline integration
- Color-coded output

#### Usage Examples:

```bash
# Test staging deployment
export GOOGLE_API_KEY=your-key
./scripts/test_deployment.sh staging

# Test production deployment
export GOOGLE_API_KEY=your-key
export PRODUCTION_URL=https://your-production-url.run.app
./scripts/test_deployment.sh production

# Custom staging URL
export STAGING_URL=https://custom-staging.run.app
export GOOGLE_API_KEY=your-key
./scripts/test_deployment.sh staging

# With custom timeout
export TEST_TIMEOUT=60
export GOOGLE_API_KEY=your-key
./scripts/test_deployment.sh staging
```

#### Output:

```
========================================
Backend Deployment Smoke Test
========================================
Environment: staging
Target URL:  https://staging-backend.run.app
Timeout:     30s

[1/5] Checking server availability...
✓ Server is reachable
✓ GOOGLE_API_KEY is set

[2/5] Testing health check endpoint...
✓ Health check passed
{
  "status": "healthy",
  "timestamp": "2025-10-25T10:30:00Z"
}

[3/5] Testing WebSocket TTS (Live mode)...
✓ WebSocket TTS test passed
  TTFB:        267ms
  Audio size:  42856 bytes
  MIME type:   audio/ogg; codecs=opus
  Sample rate: 24000 Hz

[4/5] Running pytest test suite...
✓ Pytest suite passed

[5/5] Validating backend configuration...
✓ TTS configuration is valid
  Provider:  google
  Model:     gemini-2.5-flash-native-audio-preview-09-2025
  Streaming: true

========================================
✓ All smoke tests passed!
========================================

Deployment on staging is healthy and ready.
Target URL: https://staging-backend.run.app
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GOOGLE_API_KEY` | Yes* | - | Google Gemini API key |
| `TEST_BASE_URL` | No | `http://localhost:8000` | Backend base URL |
| `TEST_TIMEOUT` | No | `30` | Timeout in seconds |
| `TEST_VOICE` | No | `kore` | Default voice for tests |
| `TEST_TTFB_THRESHOLD` | No | `500` | TTFB threshold in milliseconds |
| `STAGING_URL` | No | - | Staging deployment URL |
| `PRODUCTION_URL` | No | - | Production deployment URL |

*Required for TTS tests. Tests will be skipped if not provided.

### Test Modes

#### REST Mode
- Direct LLMManager API calls
- Single HTTP request/response
- Returns complete audio file
- MIME type: `audio/wav`
- Use for: Unit testing, basic validation

#### Live Mode (WebSocket)
- Real-time streaming via `/ws/tts`
- Multiple audio chunks
- TTFB measurement
- MIME type: `audio/ogg; codecs=opus` (Gemini Live)
- Use for: Performance testing, production validation

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Backend Smoke Tests

on:
  push:
    branches: [main, staging]
  pull_request:
    branches: [main]

jobs:
  smoke-tests:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'

      - name: Install dependencies
        run: |
          cd ai_therapist_backend
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
          pip install websockets pytest pytest-asyncio

      - name: Run smoke tests
        env:
          GOOGLE_API_KEY: ${{ secrets.GOOGLE_API_KEY }}
          TEST_BASE_URL: http://localhost:8000
        run: |
          cd ai_therapist_backend
          # Start backend in background
          python dev_server.py &
          sleep 5
          # Run tests
          pytest tests/test_tts_smoke.py -v --json-report --json-report-file=results.json

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: ai_therapist_backend/results.json
```

### Cloud Build Example

```yaml
steps:
  # Build backend image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/backend:$SHORT_SHA', '.']
    dir: 'ai_therapist_backend'

  # Deploy to staging
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'run'
      - 'deploy'
      - 'backend-staging'
      - '--image=gcr.io/$PROJECT_ID/backend:$SHORT_SHA'
      - '--region=us-central1'
      - '--platform=managed'

  # Run smoke tests against staging
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'run'
      - '--env'
      - 'GOOGLE_API_KEY=$_GOOGLE_API_KEY'
      - '--env'
      - 'STAGING_URL=https://backend-staging-$PROJECT_ID.run.app'
      - 'gcr.io/$PROJECT_ID/backend:$SHORT_SHA'
      - 'bash'
      - 'scripts/test_deployment.sh'
      - 'staging'

  # Promote to production if tests pass
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'run'
      - 'services'
      - 'update-traffic'
      - 'backend-production'
      - '--to-revisions=LATEST=100'
      - '--region=us-central1'
```

## Validation Criteria

### Audio Metadata

| Property | Expected Value | Validation |
|----------|----------------|------------|
| MIME Type (REST) | `audio/wav` | String match |
| MIME Type (Live) | `audio/ogg; codecs=opus` | Contains check |
| Sample Rate | `24000` Hz | Exact match |
| Channels | `1` (mono) | Exact match |
| Bit Depth | `16-bit` | Exact match |

### Performance Metrics

| Metric | Target | Threshold | Severity |
|--------|--------|-----------|----------|
| TTFB (Live) | <300ms | <500ms | Warning if exceeded |
| Total Duration | - | <30s | Fail if exceeded |
| Audio Size | >1KB | - | Fail if empty |
| Chunk Count | >1 | - | Fail if 0 |

### Health Checks

| Endpoint | Expected | Validation |
|----------|----------|------------|
| `/health` | `{"status": "healthy"}` | JSON status field |
| `/system/tts-config` | Valid JSON | Required fields present |
| `/ws/tts` | Connection + hello | WebSocket handshake |

## Troubleshooting

### Common Issues

#### 1. "Connection Refused" Error

**Symptom**: `Connection refused to ws://localhost:8000/ws/tts`

**Solutions**:
- Ensure backend server is running: `python dev_server.py`
- Check correct port (default: 8000)
- Verify firewall settings
- Test with `curl http://localhost:8000/health`

#### 2. "GOOGLE_API_KEY not set" Warning

**Symptom**: Tests skipped with API key warning

**Solutions**:
- Set environment variable: `export GOOGLE_API_KEY=your-key`
- Add to `.env` file in backend root
- Pass via command line: `--api-key YOUR_KEY`

#### 3. TTFB Exceeds Threshold

**Symptom**: `TTFB 847ms exceeds threshold 500ms`

**Solutions**:
- Check backend logs for processing delays
- Verify Gemini API response time
- Increase threshold: `export TEST_TTFB_THRESHOLD=1000`
- Check network latency to deployment

#### 4. WebSocket Timeout

**Symptom**: `Timeout after 30s`

**Solutions**:
- Increase timeout: `--timeout 60` or `export TEST_TIMEOUT=60`
- Check backend processing logs
- Verify Gemini API availability
- Test with shorter text

#### 5. Invalid MIME Type

**Symptom**: `MIME type mismatch: expected 'audio/ogg; codecs=opus', got 'audio/wav'`

**Solutions**:
- Verify `GOOGLE_TTS_MODE=live` is set
- Check `LLMConfig.get_tts_mode()` returns `"live"`
- Restart backend after configuration changes

## Best Practices

### Pre-Deployment Checklist

Before deploying to staging/production:

1. ✅ Run local smoke tests
   ```bash
   python testTTS.py --mode live --url ws://localhost:8000
   pytest tests/test_tts_smoke.py -v
   ```

2. ✅ Validate configuration
   ```bash
   curl http://localhost:8000/system/tts-config | jq
   ```

3. ✅ Check TTFB metrics
   ```bash
   python testTTS.py --mode live --url ws://localhost:8000 --json-output | jq '.ttfb_ms'
   ```

4. ✅ Test with multiple voices
   ```bash
   for voice in kore puck charon; do
     python testTTS.py --mode live --url ws://localhost:8000 --voice $voice
   done
   ```

5. ✅ Verify audio output quality
   ```bash
   # Play generated audio file
   ffplay test-live.ogg
   # Or on macOS
   afplay test-live.ogg
   ```

### Staging Validation Workflow

```bash
# 1. Deploy to staging
gcloud run deploy backend-staging --image gcr.io/PROJECT/backend:TAG

# 2. Wait for deployment
sleep 10

# 3. Run smoke tests
export GOOGLE_API_KEY=your-key
export STAGING_URL=https://backend-staging.run.app
./scripts/test_deployment.sh staging

# 4. If tests pass, promote to production
gcloud run services update-traffic backend-production --to-revisions LATEST=100
```

### Continuous Monitoring

Set up recurring smoke tests in production:

```bash
# Cron job (every 15 minutes)
*/15 * * * * /path/to/scripts/test_deployment.sh production >> /var/log/smoke-tests.log 2>&1
```

## Appendix

### Audio Format Specifications

#### Gemini Live (WebSocket)
- **Container**: OGG
- **Codec**: Opus
- **Sample Rate**: 24000 Hz
- **Channels**: 1 (mono)
- **Bitrate**: Variable
- **MIME Type**: `audio/ogg; codecs=opus`

#### Gemini REST
- **Container**: WAV
- **Encoding**: Linear PCM
- **Sample Rate**: 24000 Hz
- **Channels**: 1 (mono)
- **Bit Depth**: 16-bit
- **MIME Type**: `audio/wav`

### Performance Benchmarks

Based on production measurements:

| Metric | P50 | P90 | P99 | Target |
|--------|-----|-----|-----|--------|
| TTFB (Live) | 267ms | 423ms | 587ms | <500ms |
| Total Duration | 1.2s | 2.3s | 3.8s | <5s |
| Audio Size | 42KB | 68KB | 94KB | >1KB |
| Chunk Count | 8 | 14 | 21 | >1 |

---

**Last Updated**: 2025-10-25
**Maintainer**: Backend Team
**Related Docs**: `GROK_INTEGRATION.md`, `CLAUDE.md`
