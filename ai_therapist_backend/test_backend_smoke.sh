#!/bin/bash

# Backend Smoke Test Suite
# One-command validation of all endpoints and optimizations
# Usage: ./test_backend_smoke.sh [backend_url]

set -e  # Exit on any error

# Configuration
BACKEND_URL="${1:-http://localhost:8000}"
TIMEOUT=30
TEST_SESSION_ID="smoke-test-$(date +%s)"
TEMP_DIR="/tmp/backend_smoke_test"
mkdir -p "$TEMP_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED_TESTS++))
}

fail() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED_TESTS++))
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Test helper function
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local expected_status="${4:-200}"
    local payload="$5"
    
    ((TOTAL_TESTS++))
    log "Testing $name..."
    
    local temp_file="$TEMP_DIR/response_$TOTAL_TESTS.json"
    local curl_cmd="curl -s -w '%{http_code}' -o '$temp_file' -X $method"
    
    if [ "$method" = "POST" ] && [ -n "$payload" ]; then
        curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$payload'"
    fi
    
    curl_cmd="$curl_cmd --connect-timeout $TIMEOUT --max-time $TIMEOUT '$BACKEND_URL$endpoint'"
    
    # Execute curl and capture status code
    local status_code
    status_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
    
    if [ "$status_code" = "$expected_status" ]; then
        success "$name (HTTP $status_code)"
        return 0
    else
        fail "$name (Expected HTTP $expected_status, got $status_code)"
        if [ -f "$temp_file" ]; then
            echo "Response preview:"
            head -n 3 "$temp_file" | sed 's/^/  /'
        fi
        return 1
    fi
}

# Test streaming endpoint
test_streaming_endpoint() {
    local name="$1"
    local endpoint="$2"
    local payload="$3"
    
    ((TOTAL_TESTS++))
    log "Testing $name (streaming)..."
    
    local temp_file="$TEMP_DIR/stream_response_$TOTAL_TESTS.txt"
    
    # Use timeout to limit streaming test duration
    if timeout 10s curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --connect-timeout $TIMEOUT \
        "$BACKEND_URL$endpoint" > "$temp_file" 2>/dev/null; then
        
        if [ -s "$temp_file" ]; then
            local response_size=$(wc -c < "$temp_file")
            success "$name (${response_size} bytes received)"
            return 0
        else
            fail "$name (No data received)"
            return 1
        fi
    else
        fail "$name (Connection failed or timeout)"
        return 1
    fi
}

# Measure TTFB for performance validation
measure_ttfb() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local payload="$4"
    
    log "Measuring TTFB for $name..."
    
    local curl_cmd="curl -s -w '%{time_starttransfer}\\n' -o /dev/null -X $method"
    
    if [ "$method" = "POST" ] && [ -n "$payload" ]; then
        curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$payload'"
    fi
    
    curl_cmd="$curl_cmd --connect-timeout $TIMEOUT --max-time $TIMEOUT '$BACKEND_URL$endpoint'"
    
    local ttfb
    ttfb=$(eval "$curl_cmd" 2>/dev/null || echo "999.999")
    
    # Convert to milliseconds
    local ttfb_ms=$(echo "$ttfb * 1000" | bc -l 2>/dev/null | cut -d. -f1)
    
    echo "$ttfb_ms"
}

# Start tests
echo "🚀 Backend Smoke Test Suite"
echo "=================================="
echo "Backend URL: $BACKEND_URL"
echo "Test Session: $TEST_SESSION_ID"
echo "Timestamp: $(date)"
echo ""

# Phase 1: Basic Health Checks
log "Phase 1: Basic Health Checks"
test_endpoint "Health Check" "GET" "/health"
test_endpoint "Metrics Endpoint" "GET" "/metrics"

# Phase 2: Optimization Status Endpoints
log "Phase 2: Optimization Status Endpoints"
test_endpoint "Phase 1 Status" "GET" "/phase1/status"
test_endpoint "Phase 2 Status" "GET" "/phase2/status"
test_endpoint "Performance Report" "GET" "/performance"

# Phase 3: LLM Endpoints with TTFB Measurement
log "Phase 3: LLM Endpoints with TTFB Measurement"

# Standard LLM test
llm_payload='{
    "history": [
        {"role": "user", "content": "Hello, this is a smoke test message", "sequence": 1}
    ]
}'

# Test streaming endpoint
test_streaming_endpoint "LLM Chat Streaming" "/sessions/$TEST_SESSION_ID/chat_stream" "$llm_payload"

# Measure TTFB for LLM
llm_ttfb=$(measure_ttfb "LLM TTFB" "POST" "/sessions/$TEST_SESSION_ID/chat_stream" "$llm_payload")
if [ "$llm_ttfb" -lt 1500 ]; then  # 1.5s threshold
    success "LLM TTFB within acceptable range (${llm_ttfb}ms)"
    ((PASSED_TESTS++))
else
    warn "LLM TTFB higher than expected (${llm_ttfb}ms)"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Phase 4: TTS Endpoints with Buffer Size Testing
log "Phase 4: TTS Endpoints (Short & Long Input)"

# Short TTS test (10 words) - catch buffer regressions
short_tts_payload='{
    "text": "This is a short text for buffer testing.",
    "voice": "alloy",
    "model": "tts-1"
}'

test_endpoint "TTS Short Input" "POST" "/voice/synthesize" "200" "$short_tts_payload"

# Long TTS test (100+ words) - catch buffer regressions
long_tts_payload='{
    "text": "This is a much longer text input designed to test buffer handling capabilities. It contains multiple sentences with various punctuation marks, numbers like 123 and 456, and should be long enough to trigger any potential buffer size issues. The purpose is to ensure that the text-to-speech system can handle longer inputs without encountering memory allocation problems, buffer overflows, or other issues that might arise with larger text payloads. This comprehensive test helps validate the robustness of the TTS implementation.",
    "voice": "alloy", 
    "model": "tts-1"
}'

test_endpoint "TTS Long Input" "POST" "/voice/synthesize" "200" "$long_tts_payload"

# Measure TTFB for TTS
tts_ttfb=$(measure_ttfb "TTS TTFB" "POST" "/voice/synthesize" "$short_tts_payload")
if [ "$tts_ttfb" -lt 800 ]; then  # 800ms threshold
    success "TTS TTFB within acceptable range (${tts_ttfb}ms)"
    ((PASSED_TESTS++))
else
    warn "TTS TTFB higher than expected (${tts_ttfb}ms)"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Phase 5: API Endpoints (if available)
log "Phase 5: Legacy API Endpoints"
test_endpoint "LLM Status (Legacy)" "GET" "/api/v1/llm/status"

# Phase 6: Performance Summary
log "Phase 6: Performance Summary"
echo ""
echo "📊 Performance Metrics:"
echo "  LLM TTFB: ${llm_ttfb}ms"
echo "  TTS TTFB: ${tts_ttfb}ms"
echo ""

# Save results for tracking
results_file="$TEMP_DIR/smoke_test_results.csv"
echo "timestamp,llm_ttfb_ms,tts_ttfb_ms,passed_tests,failed_tests,total_tests" > "$results_file"
echo "$(date -Iseconds),$llm_ttfb,$tts_ttfb,$PASSED_TESTS,$FAILED_TESTS,$TOTAL_TESTS" >> "$results_file"

# Final Results
echo "=================================="
echo "📋 Smoke Test Results"
echo "=================================="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All smoke tests passed!${NC}"
    echo "✅ Backend is ready for operation"
    echo ""
    echo "Results saved to: $results_file"
    exit 0
else
    echo -e "\n${RED}⚠️  $FAILED_TESTS test(s) failed${NC}"
    echo "❌ Backend may have issues"
    echo ""
    echo "Check logs and fix issues before proceeding"
    echo "Results saved to: $results_file"
    exit 1
fi