#!/bin/bash
#
# Backend Deployment Smoke Test Script
#
# Run comprehensive smoke tests against a deployed backend (staging or production).
# Designed to run in CI/CD pipelines before promoting new revisions.
#
# Usage:
#   ./scripts/test_deployment.sh [staging|production]
#
# Environment Variables:
#   STAGING_URL      - URL of staging deployment
#   PRODUCTION_URL   - URL of production deployment
#   GOOGLE_API_KEY   - Google API key for TTS tests
#   TEST_TIMEOUT     - Timeout in seconds (default: 30)
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${1:-staging}"
STAGING_URL="${STAGING_URL:-https://staging-ai-therapist-backend.run.app}"
PRODUCTION_URL="${PRODUCTION_URL:-https://ai-therapist-backend-385290373302.us-central1.run.app}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Determine target URL
if [ "$ENVIRONMENT" = "production" ]; then
    TARGET_URL="$PRODUCTION_URL"
else
    TARGET_URL="$STAGING_URL"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Backend Deployment Smoke Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Environment: ${YELLOW}$ENVIRONMENT${NC}"
echo -e "Target URL:  ${YELLOW}$TARGET_URL${NC}"
echo -e "Timeout:     ${YELLOW}${TEST_TIMEOUT}s${NC}"
echo ""

# Check if server is reachable
echo -e "${BLUE}[1/5] Checking server availability...${NC}"
if curl -f -s -o /dev/null -w "%{http_code}" "$TARGET_URL/health" | grep -q "200"; then
    echo -e "${GREEN}✓ Server is reachable${NC}"
else
    echo -e "${RED}✗ Server not reachable at $TARGET_URL/health${NC}"
    exit 1
fi

# Check if GOOGLE_API_KEY is set
if [ -z "$GOOGLE_API_KEY" ]; then
    echo -e "${YELLOW}⚠ GOOGLE_API_KEY not set. TTS tests will be skipped.${NC}"
    SKIP_TTS=true
else
    echo -e "${GREEN}✓ GOOGLE_API_KEY is set${NC}"
    SKIP_TTS=false
fi

# Test 1: Health Check Endpoint
echo ""
echo -e "${BLUE}[2/5] Testing health check endpoint...${NC}"
HEALTH_RESPONSE=$(curl -s "$TARGET_URL/health")
if echo "$HEALTH_RESPONSE" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed${NC}"
    echo "$HEALTH_RESPONSE" | jq '.'
else
    echo -e "${RED}✗ Health check failed${NC}"
    echo "$HEALTH_RESPONSE"
    exit 1
fi

# Test 2: WebSocket TTS Live Mode (if API key available)
echo ""
echo -e "${BLUE}[3/5] Testing WebSocket TTS (Live mode)...${NC}"
if [ "$SKIP_TTS" = true ]; then
    echo -e "${YELLOW}⚠ Skipped (GOOGLE_API_KEY not set)${NC}"
else
    cd "$PROJECT_ROOT"

    # Run testTTS.py with live mode
    WS_URL="${TARGET_URL/https/wss}"
    WS_URL="${WS_URL/http/ws}"

    if python testTTS.py \
        --mode live \
        --url "$WS_URL" \
        --text "Deployment smoke test for $ENVIRONMENT" \
        --timeout "$TEST_TIMEOUT" \
        --output "/tmp/test-deployment-${ENVIRONMENT}.ogg" \
        --json-output > /tmp/test-result.json 2>&1; then

        echo -e "${GREEN}✓ WebSocket TTS test passed${NC}"

        # Extract and display metrics
        TTFB=$(jq -r '.ttfb_ms' /tmp/test-result.json)
        AUDIO_SIZE=$(jq -r '.audio_size_bytes' /tmp/test-result.json)
        MIME_TYPE=$(jq -r '.mime_type' /tmp/test-result.json)
        SAMPLE_RATE=$(jq -r '.sample_rate' /tmp/test-result.json)

        echo -e "  TTFB:        ${GREEN}${TTFB}ms${NC}"
        echo -e "  Audio size:  ${GREEN}${AUDIO_SIZE} bytes${NC}"
        echo -e "  MIME type:   ${GREEN}${MIME_TYPE}${NC}"
        echo -e "  Sample rate: ${GREEN}${SAMPLE_RATE} Hz${NC}"

        # Validate TTFB threshold
        if [ "${TTFB%.*}" -gt 500 ]; then
            echo -e "${YELLOW}⚠ TTFB exceeds 500ms threshold${NC}"
        fi

    else
        echo -e "${RED}✗ WebSocket TTS test failed${NC}"
        cat /tmp/test-result.json
        exit 1
    fi
fi

# Test 3: Pytest Suite
echo ""
echo -e "${BLUE}[4/5] Running pytest test suite...${NC}"
cd "$PROJECT_ROOT"

if [ "$SKIP_TTS" = true ]; then
    echo -e "${YELLOW}⚠ Skipped (GOOGLE_API_KEY not set)${NC}"
else
    if pytest tests/test_tts_smoke.py \
        -v \
        --base-url="$TARGET_URL" \
        --google-api-key="$GOOGLE_API_KEY" \
        --tb=short \
        -x; then

        echo -e "${GREEN}✓ Pytest suite passed${NC}"
    else
        echo -e "${RED}✗ Pytest suite failed${NC}"
        exit 1
    fi
fi

# Test 4: Configuration Validation
echo ""
echo -e "${BLUE}[5/5] Validating backend configuration...${NC}"

# Check TTS config endpoint
TTS_CONFIG=$(curl -s "$TARGET_URL/system/tts-config")
if echo "$TTS_CONFIG" | jq -e '.provider' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ TTS configuration is valid${NC}"

    PROVIDER=$(echo "$TTS_CONFIG" | jq -r '.provider')
    MODEL=$(echo "$TTS_CONFIG" | jq -r '.model')
    SUPPORTS_STREAMING=$(echo "$TTS_CONFIG" | jq -r '.supports_streaming')

    echo -e "  Provider:  ${GREEN}${PROVIDER}${NC}"
    echo -e "  Model:     ${GREEN}${MODEL}${NC}"
    echo -e "  Streaming: ${GREEN}${SUPPORTS_STREAMING}${NC}"
else
    echo -e "${YELLOW}⚠ TTS configuration endpoint returned unexpected format${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ All smoke tests passed!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Deployment on ${YELLOW}$ENVIRONMENT${NC} is healthy and ready."
echo -e "Target URL: ${YELLOW}$TARGET_URL${NC}"
echo ""

exit 0
