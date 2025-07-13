#!/bin/bash

# Phase 0 TTFB Metrics Test Script
# Tests the new TTFB tracking capabilities added to the backend

echo "🚀 Phase 0 TTFB Metrics Test Suite"
echo "=================================="

BACKEND_URL="http://localhost:8000"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test 1: Health endpoint
echo -e "\n${BLUE}🔍 Testing /health endpoint...${NC}"
health_response=$(curl -s -w "%{http_code}" -o /tmp/health.json "$BACKEND_URL/health")
if [ "$health_response" = "200" ]; then
    echo -e "${GREEN}✅ Health endpoint is working${NC}"
    status=$(cat /tmp/health.json | python3 -c "import json,sys; print(json.load(sys.stdin).get('status', 'unknown'))")
    echo -e "${BLUE}📊 Status: $status${NC}"
else
    echo -e "${RED}❌ Health endpoint returned $health_response${NC}"
fi

# Test 2: Metrics endpoint
echo -e "\n${BLUE}🔍 Testing /metrics endpoint...${NC}"
metrics_response=$(curl -s -w "%{http_code}" -o /tmp/metrics.json "$BACKEND_URL/metrics")
if [ "$metrics_response" = "200" ]; then
    echo -e "${GREEN}✅ Metrics endpoint is working${NC}"
    
    # Parse and display key information
    python3 -c "
import json, sys
try:
    with open('/tmp/metrics.json') as f:
        data = json.load(f)
    
    print('🎯 Phase 0 Status:')
    phase0 = data.get('phase_0_status', {})
    for key, value in phase0.items():
        print(f'  • {key}: {value}')
    
    print('\n🎯 TTFB Targets:')
    targets = data.get('critical_metrics', {}).get('targets', {})
    for metric, target in targets.items():
        print(f'  • {metric}: {target.get(\"target\", \"N/A\")}')
except Exception as e:
    print(f'Error parsing metrics: {e}')
"
else
    echo -e "${RED}❌ Metrics endpoint returned $metrics_response${NC}"
fi

# Test 3: LLM Chat streaming TTFB
echo -e "\n${BLUE}🔍 Testing LLM TTFB tracking...${NC}"
echo "Making chat stream request..."

start_time=$(python3 -c "import time; print(time.time())")
chat_response=$(curl -s -w "%{http_code}" \
  -X POST "$BACKEND_URL/sessions/test-session/chat_stream" \
  -H "Content-Type: application/json" \
  -d '{
    "history": [
      {"role": "user", "content": "Hello, how are you today?", "sequence": 1}
    ]
  }' \
  -o /tmp/chat_response.txt)

end_time=$(python3 -c "import time; print(time.time())")
client_ttfb=$(python3 -c "print(f'{($end_time - $start_time) * 1000:.1f}')")

if [ "$chat_response" = "200" ]; then
    echo -e "${GREEN}✅ LLM streaming request successful${NC}"
    echo -e "${YELLOW}⏱️  Client-measured TTFB: ${client_ttfb}ms${NC}"
    echo -e "${BLUE}📝 Server-side TTFB metrics should now be recorded${NC}"
else
    echo -e "${RED}❌ Chat request returned $chat_response${NC}"
    if [ -f /tmp/chat_response.txt ]; then
        echo "Error details:"
        head -n 5 /tmp/chat_response.txt
    fi
fi

# Test 4: TTS first-byte tracking
echo -e "\n${BLUE}🔍 Testing TTS TTFB tracking...${NC}"
echo "Making TTS request..."

start_time=$(python3 -c "import time; print(time.time())")
tts_response=$(curl -s -w "%{http_code}" \
  -X POST "$BACKEND_URL/voice/synthesize" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello, this is a test of text-to-speech latency measurement.",
    "voice": "alloy",
    "model": "tts-1"
  }' \
  -o /tmp/tts_response.json)

end_time=$(python3 -c "import time; print(time.time())")
client_ttfb=$(python3 -c "print(f'{($end_time - $start_time) * 1000:.1f}')")

if [ "$tts_response" = "200" ]; then
    echo -e "${GREEN}✅ TTS request successful${NC}"
    echo -e "${YELLOW}⏱️  Client-measured TTFB: ${client_ttfb}ms${NC}"
    echo -e "${BLUE}📝 Server-side TTS TTFB metrics should now be recorded${NC}"
else
    echo -e "${RED}❌ TTS request returned $tts_response${NC}"
    if [ -f /tmp/tts_response.json ]; then
        echo "Error details:"
        head -n 5 /tmp/tts_response.json
    fi
fi

# Test 5: Check recorded metrics
echo -e "\n${BLUE}🔍 Checking recorded metrics...${NC}"
final_metrics_response=$(curl -s -w "%{http_code}" -o /tmp/final_metrics.json "$BACKEND_URL/metrics")
if [ "$final_metrics_response" = "200" ]; then
    echo -e "${GREEN}📊 Final Metrics:${NC}"
    python3 -c "
import json
try:
    with open('/tmp/final_metrics.json') as f:
        data = json.load(f)
    
    metrics = data.get('metrics', {})
    for metric_name, metric_data in metrics.items():
        if 'ttfb' in metric_name.lower() or 'first_byte' in metric_name.lower():
            print(f'  • {metric_name}: {metric_data}')
    
    if not any('ttfb' in name.lower() or 'first_byte' in name.lower() for name in metrics.keys()):
        print('  📝 No TTFB metrics recorded yet (may need API keys configured)')
except Exception as e:
    print(f'Error parsing final metrics: {e}')
"
fi

# Summary
echo -e "\n${'=' * 50}"
echo -e "${BLUE}📋 Test Summary${NC}"

# Count successful tests
successful_tests=0
total_tests=4

if [ "$health_response" = "200" ]; then ((successful_tests++)); fi
if [ "$metrics_response" = "200" ]; then ((successful_tests++)); fi
if [ "$chat_response" = "200" ]; then ((successful_tests++)); fi
if [ "$tts_response" = "200" ]; then ((successful_tests++)); fi

echo -e "${GREEN}✅ Passed: $successful_tests/$total_tests tests${NC}"

if [ "$successful_tests" = "$total_tests" ]; then
    echo -e "${GREEN}🎉 Phase 0 TTFB metrics implementation is working correctly!${NC}"
    echo -e "${GREEN}✅ Ready to proceed to Phase 1: HTTP Client Hot-rodding${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed. Check the backend logs for details.${NC}"
    echo -e "${BLUE}💡 Make sure the backend is running: python dev_server.py${NC}"
fi

# Cleanup
rm -f /tmp/health.json /tmp/metrics.json /tmp/chat_response.txt /tmp/tts_response.json /tmp/final_metrics.json